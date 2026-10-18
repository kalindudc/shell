# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require_relative "errors"
require_relative "bb_app"

module Installer
  # Brings a running bb in line with bb.yml through the bb CLI. bb keeps these
  # preferences in its own database, so they cannot be stowed like dotfiles.
  # The step only adds and changes: anything missing from bb.yml is left alone.
  module Bb
    CONFIG_FILE = File.expand_path("../../bb.yml", __dir__)
    PLUGIN_ENTRY = /\A(?<id>[a-z0-9][a-z0-9-]*)@[a-z0-9][a-z0-9-]*\z/
    CLI_HINT = "open bb, then run: task bb"
    LIST_KEYS = %w[marketplaces plugins enable disable].freeze
    MAP_KEYS = %w[settings completed_turns experiments ui].freeze

    module_function

    def load_config(path = CONFIG_FILE)
      YAML.load_file(path)
    end

    # Lists from the profile are added to the shared lists; its maps and theme win key by key.
    def desired_state(config, profile)
      extra = config.fetch("profiles", {}).fetch(profile, nil) || {}
      desired = LIST_KEYS.to_h { |key| [key, Array(config[key]) + Array(extra[key])] }
      MAP_KEYS.each { |key| desired[key] = (config[key] || {}).merge(extra[key] || {}) }
      desired["plugin_settings"] = (config["plugin_settings"] || {}).merge(extra["plugin_settings"] || {}) do |_id, shared, own|
        shared.merge(own)
      end
      desired["theme"] = extra.fetch("theme", config["theme"])
      desired
    end

    # A plugin is <id>@<marketplace>, or { id, source } for one that no marketplace lists.
    def plugin_id(entry)
      if entry.is_a?(Hash)
        return entry["id"] if entry["id"] && entry["source"]

        raise Installer::Error, "bb.yml plugins given as a map need id and source, got: #{entry}"
      end

      match = PLUGIN_ENTRY.match(entry.to_s)
      raise Installer::Error, "bb.yml plugins must look like <id>@<marketplace>, got: #{entry}" unless match

      match[:id]
    end

    def install_source(entry)
      entry.is_a?(Hash) ? entry.fetch("source") : entry
    end

    # Marketplaces come first so the plugin installs that follow can resolve <id>@<marketplace>,
    # and plugins are installed before their settings and the UI preferences that name them.
    def plan(desired, current)
      installed = current.fetch(:plugins)
      to_install = desired["plugins"].reject { |entry| installed.key?(plugin_id(entry)) }
      installing = to_install.map { |entry| plugin_id(entry) }

      marketplace_commands(desired["marketplaces"], current.fetch(:marketplaces)) +
        to_install.map { |entry| ["bb", "plugin", "install", install_source(entry), "--yes"] } +
        enable_commands(desired["enable"], installed, installing) +
        disable_commands(desired["disable"], installed) +
        plugin_setting_commands(desired["plugin_settings"], current.fetch(:plugin_settings), installed.keys + installing) +
        setting_commands(desired["settings"], current.fetch(:settings)) +
        completed_turn_commands(desired["completed_turns"], current.fetch(:settings)) +
        experiment_commands(desired["experiments"], current.fetch(:experiments)) +
        ui_commands(desired["ui"], current.fetch(:ui)) +
        theme_commands(desired["theme"], current.fetch(:theme))
    end

    def marketplace_commands(marketplaces, known_names)
      marketplaces
        .reject { |marketplace| known_names.include?(marketplace.fetch("name")) }
        .map { |marketplace| ["bb", "marketplace", "add", marketplace.fetch("source")] }
    end

    # A plugin installed in the same run starts enabled.
    def enable_commands(ids, installed, installing)
      ids
        .reject { |id| installed[id] == true || installing.include?(id) }
        .map { |id| ["bb", "plugin", "enable", id] }
    end

    def disable_commands(ids, installed)
      ids
        .select { |id| installed[id] == true }
        .map { |id| ["bb", "plugin", "disable", id] }
    end

    # Settings of a plugin that is neither installed nor being installed cannot be written.
    def plugin_setting_commands(plugin_settings, current_settings, available_ids)
      plugin_settings.select { |id, _| available_ids.include?(id) }.flat_map do |id, values|
        current_values = current_settings.fetch(id, {})
        values
          .reject { |key, value| current_values[key] == value }
          .map { |key, value| ["bb", "plugin", "config", id, "set", key, value.to_s] }
      end
    end

    def setting_commands(settings, current_settings)
      settings
        .reject { |key, value| current_settings[key] == value }
        .map { |key, value| ["bb", "settings", "general", key, value.to_s] }
    end

    def completed_turn_commands(displays, current_settings)
      current_displays = current_settings["providerCompletedTurnDisplay"] || {}
      displays
        .reject { |provider, display| current_displays[provider] == display }
        .map { |provider, display| ["bb", "settings", "completed-turns", provider, display] }
    end

    def experiment_commands(experiments, current_experiments)
      experiments
        .reject { |key, value| current_experiments[key] == value }
        .map { |key, value| ["bb", "settings", "experiment", key, value.to_s] }
    end

    # `bb settings ui set` takes plain text for strings and JSON for lists.
    def ui_commands(preferences, current_preferences)
      preferences
        .reject { |key, value| current_preferences[key] == value }
        .map { |key, value| ["bb", "settings", "ui", "set", key, value.is_a?(String) ? value : JSON.generate(value)] }
    end

    def theme_commands(theme, current_theme)
      return [] if theme.nil? || theme == current_theme

      [["bb", "theme", "set", theme]]
    end

    def current_state(plugin_settings_ids)
      settings = bb_json("settings", "show")
      plugins = bb_json("plugin", "list").fetch("plugins").to_h { |plugin| [plugin.fetch("id"), plugin.fetch("enabled")] }
      {
        marketplaces: bb_json("marketplace", "list").map { |marketplace| marketplace.fetch("name") },
        plugins: plugins,
        plugin_settings: (plugin_settings_ids & plugins.keys).to_h { |id| [id, bb_json("plugin", "config", id).fetch("values")] },
        settings: settings.fetch("generalSettings"),
        experiments: settings.fetch("experiments", {}),
        ui: bb_json("settings", "ui", "list").fetch("preferences").transform_values { |preference| preference.fetch("value") },
        theme: settings.dig("appearance", "themeId")
      }
    end

    def bb_json(*args)
      stdout, stderr, status = Open3.capture3("bb", *args, "--json")
      unless status.success?
        detail = stderr.strip.empty? ? "" : ": #{stderr.strip}"
        raise Installer::CommandFailed, "Command failed: bb #{args.join(" ")} --json#{detail}"
      end

      # JSON is UTF-8, but Open3 tags output with the locale encoding (US-ASCII under LANG=C).
      JSON.parse(stdout.force_encoding(Encoding::UTF_8))
    end

    def apply!(config: load_config, profile: "default")
      unless Installer::BbApp.ensure_running!
        Installer::Utils.warn("bb is not installed or did not start, skipping bb setup: #{CLI_HINT}")
        return false
      end

      Installer::BbApp.install_cli_command!
      desired = desired_state(config, profile)
      commands = plan(desired, current_state(desired["plugin_settings"].keys))
      if commands.empty?
        Installer::Utils.log("bb already matches bb.yml (profile: #{profile})")
        return true
      end

      Installer::Utils.log("Applying bb.yml (profile: #{profile})...")
      commands.each { |command| Installer::Utils.run!(*command) }
      true
    end
  end
end
