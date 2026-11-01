# frozen_string_literal: true

require "tempfile"
require_relative "bb"
require_relative "leak_check"
require_relative "private_repo"

module Installer
  module BbSnapshot
    GENERAL_KEYS = %w[showKeyboardHints showGitChanges steerActiveThreadOnEnter terminalCopyOnSelect
                      confirmThreadArchive showDiagnosticEvents keepHistoryAfterContextClear summarizeShellCommands
                      defaultProviderId streamerMode allowFastServiceTier telemetryEnabled managedBranchPrefix
                      idleProviderSessionTimeoutMinutes earlyAdopter showUnhandledProviderEvents].freeze
    UI_KEYS = %w[sidebar.organizationMode sidebar.threadGrouping.environment sidebar.chronologicalSort
                 sidebar.sortDirection sidebar.sectionOrder sidebar.manualSectionOrder sidebar.machineSectionOrder
                 sidebar.threadListProvider sidebar.navigationProvider composer.provider
                 sidebar.hiddenFooterItems sidebar.footerOrder sidebar.pluginPanelOrder sidebar.visiblePluginPanels].freeze
    TOP_LEVEL_KEYS = (Bb::LIST_KEYS + Bb::MAP_KEYS + %w[plugin_settings keyboard theme profiles ui_capture_allowlist]).freeze
    CREDENTIAL_KEY = /secret|password|token|credential|api[_-]?key|headers/i
    HEADER = "# Work-free bb recipe and capture allowlist. See docs/bb.md before adding keys or plugins.\n"

    module_function

    def approved_ids(config)
      (Array(config["plugins"]).map { |entry| Bb.plugin_id(entry) } + Array(config["enable"]) + Array(config["disable"])).uniq
    end

    def validate!(config)
      unknown = config.keys - TOP_LEVEL_KEYS
      raise Installer::Error, "Unsupported bb.yml sections: #{unknown.join(', ')}" unless unknown.empty?
      raise Installer::Error, "Capture only supports the shared recipe; keep private profiles out of bb.yml" unless config.fetch("profiles", {}).empty?

      { "settings" => GENERAL_KEYS, "ui" => UI_KEYS }.each do |section, allowed|
        unknown = config.fetch(section, {}).keys - allowed
        raise Installer::Error, "Unapproved #{section} keys in bb.yml: #{unknown.join(', ')}" unless unknown.empty?
      end
      config.fetch("ui_capture_allowlist", {}).each do |key, entries|
        unless UI_KEYS.include?(key) && entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(String) }
          raise Installer::Error, "UI capture approvals require a supported key and a list of entries"
        end
      end
      config.fetch("plugin_settings", {}).each do |id, values|
        raise Installer::Error, "Settings require an approved plugin: #{id}" unless approved_ids(config).include?(id)
        raise Installer::Error, "Credential fields cannot be captured for #{id}" if values.keys.any? { |key| CREDENTIAL_KEY.match?(key) }
      end
    end

    def refresh_keys(template, live, section)
      template.to_h do |key, _|
        raise Installer::Error, "bb no longer reports approved #{section} key #{key}; review bb.yml" unless live.key?(key)

        [key, live.fetch(key)]
      end
    end

    def capture(config, current)
      validate!(config)
      saved = Marshal.load(Marshal.dump(config))
      notes = []
      ids = approved_ids(config)
      notes << "#{(current.fetch(:plugins).keys - ids).size} unlisted plugins were not captured; sources are never discovered automatically."
      saved["enable"], saved["disable"] = ids.partition do |id|
        if current.fetch(:plugins).key?(id)
          current.fetch(:plugins).fetch(id)
        else
          notes << "Plugin #{id} is absent; kept its saved enabled state."
          !Array(config["disable"]).include?(id)
        end
      end
      saved["settings"] = refresh_keys(config.fetch("settings", {}), current.fetch(:settings), "general")
      if saved["settings"]["managedBranchPrefix"] != config.dig("settings", "managedBranchPrefix")
        notes << "Changed free-text managedBranchPrefix was not captured; edit the recipe after review."
        saved["settings"]["managedBranchPrefix"] = config.fetch("settings").fetch("managedBranchPrefix")
      end
      if saved["settings"].key?("defaultProviderId") && !%w[pi claude-code codex].include?(saved["settings"]["defaultProviderId"])
        raise Installer::Error, "The default provider is not approved for capture"
      end
      saved["experiments"] = refresh_keys(config.fetch("experiments", {}), current.fetch(:experiments), "experiment")
      saved["completed_turns"] = refresh_keys(config.fetch("completed_turns", {}), current.fetch(:settings).fetch("providerCompletedTurnDisplay", {}), "completed turns")
      saved["plugin_settings"] = capture_plugin_settings(config.fetch("plugin_settings", {}), current, notes)
      saved["ui_capture_allowlist"] = config.fetch("ui_capture_allowlist", {}).dup
      saved["ui"] = refresh_keys(config.fetch("ui", {}), current.fetch(:ui), "UI").to_h do |key, value|
        approved = config.fetch("ui").fetch(key)
        if approved.is_a?(Array)
          approved = saved["ui_capture_allowlist"].fetch(key, approved)
          saved["ui_capture_allowlist"][key] = approved
          filtered = value.select { |entry| approved.include?(entry) }
          notes << "Unlisted entries in #{key} were not captured." if filtered != value
          value = filtered
        elsif key.end_with?("Provider", ".provider") && value != approved
          notes << "Changed UI provider #{key} was not captured; approve it in bb.yml first."
          value = approved
        end
        [key, value]
      end
      saved["keyboard"] = capture_keyboard(config.fetch("keyboard", []), current.fetch(:keyboard), notes)
      theme = current.fetch(:theme)
      if theme == config["theme"] || (theme&.start_with?("plugin:") && ids.include?(theme.split(":")[1]))
        saved["theme"] = theme
      else
        notes << "The current theme is not approved; kept the saved theme."
      end
      [saved, notes]
    end

    def capture_plugin_settings(template, current, notes)
      template.to_h do |id, values|
        unless current.fetch(:plugin_settings).key?(id)
          notes << "Settings for #{id} are unavailable (disabled or absent); kept the saved values."
          next [id, values]
        end
        schemas = current.fetch(:plugin_schemas).fetch(id)
        values.each_key do |key|
          schema = schemas[key]
          if schema.nil? || schema["secret"] || !%w[string number boolean select].include?(schema["type"])
            raise Installer::Error, "Cannot safely capture #{id}.#{key}; its schema is absent, secret, or unsupported"
          end
          value = current.fetch(:plugin_settings).fetch(id).fetch(key)
          valid = case schema.fetch("type")
                  when "number" then value.is_a?(Numeric) && value.finite?
                  when "boolean" then value == true || value == false
                  when "select" then schema.fetch("options").include?(value)
                  when "string" then value.is_a?(String)
                  end
          raise Installer::Error, "Invalid value type for #{id}.#{key}; capture stopped" unless valid
        end
        refreshed = refresh_keys(values, current.fetch(:plugin_settings).fetch(id), "#{id} setting")
        refreshed.each do |key, value|
          next unless schemas.fetch(key)["type"] == "string" && value != values.fetch(key)

          notes << "Changed free-text setting #{id}.#{key} was not captured; edit the recipe after review."
          refreshed[key] = values.fetch(key)
        end
        [id, refreshed]
      end
    end

    def capture_keyboard(template, live, notes)
      template.map { |entry| entry.fetch("command") }.uniq.flat_map do |command|
        overrides = live.select { |entry| entry.fetch("command") == command }
        if overrides.empty?
          notes << "No saved keyboard override for #{command}; kept the recipe (remove it manually to stop managing it)."
          next template.select { |entry| entry.fetch("command") == command }
        end
        overrides.map do |entry|
          result = { "command" => command, "shortcut" => Bb.shortcut_text(entry["shortcut"]) }
          result["platform"] = entry["platform"] if entry["platform"]
          result
        end
      end
    end

    def export!(path: Bb::CONFIG_FILE, denylist: nil)
      raise Installer::Error, "Refusing to replace a symlinked bb recipe" if File.symlink?(path)

      config = Bb.load_config(path)
      validate!(config)
      saved, notes = capture(config, Bb.current_state(config.fetch("plugin_settings", {}).keys))
      content = HEADER + YAML.dump(saved)
      denylist ||= LeakCheck.denylist(File.join(PrivateRepo.dir, LeakCheck::DENYLIST_FILE))
      findings = LeakCheck.scan(content, denylist)
      unless findings.empty?
        labels = findings.map { |finding| "line #{finding[:line]}: #{LeakCheck.redacted_label(finding)}" }.join("\n")
        raise Installer::Error, "Refusing to write bb.yml: privacy check failed (values redacted)\n#{labels}"
      end
      if File.read(path) != content
        Tempfile.create([".bb-", ".yml"], File.dirname(path)) do |file|
          file.write(content)
          file.flush
          file.fsync
          File.chmod(File.stat(path).mode & 0o777, file.path)
          File.rename(file.path, path)
        end
      end
      notes.each { |note| Utils.warn(note) }
      Utils.warn("No private denylist is available; only generic privacy patterns were checked.") if denylist.empty?
      Utils.success("Captured approved bb settings in #{path}; review the diff before committing. No live settings were changed.")
      true
    end
  end
end
