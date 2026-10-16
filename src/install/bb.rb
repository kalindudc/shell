# frozen_string_literal: true

require "json"
require "open3"
require "yaml"
require_relative "errors"

module Installer
  # Brings a running bb in line with bb.yml through the bb CLI. bb keeps these
  # preferences in its own database, so they cannot be stowed like dotfiles.
  # The step only adds and changes: anything missing from bb.yml is left alone.
  module Bb
    CONFIG_FILE = File.expand_path("../../bb.yml", __dir__)
    PLUGIN_ENTRY = /\A(?<id>[a-z0-9][a-z0-9-]*)@[a-z0-9][a-z0-9-]*\z/
    CLI_HINT = "open bb, install its command line tool (Settings → General → Command line), then run: task bb"

    module_function

    def load_config(path = CONFIG_FILE)
      YAML.load_file(path)
    end

    # Lists from the profile are added to the shared lists; its settings and theme win.
    def desired_state(config, profile)
      extra = config.fetch("profiles", {}).fetch(profile, nil) || {}
      {
        "marketplaces" => Array(config["marketplaces"]) + Array(extra["marketplaces"]),
        "plugins" => Array(config["plugins"]) + Array(extra["plugins"]),
        "enable" => Array(config["enable"]) + Array(extra["enable"]),
        "settings" => (config["settings"] || {}).merge(extra["settings"] || {}),
        "theme" => extra.fetch("theme", config["theme"])
      }
    end

    def plugin_id(entry)
      match = PLUGIN_ENTRY.match(entry.to_s)
      raise Installer::Error, "bb.yml plugins must look like <id>@<marketplace>, got: #{entry}" unless match

      match[:id]
    end

    # Marketplaces come first so the plugin installs that follow can resolve <id>@<marketplace>.
    def plan(desired, current)
      installed = current.fetch(:plugins)
      to_install = desired["plugins"].reject { |entry| installed.key?(plugin_id(entry)) }

      marketplace_commands(desired["marketplaces"], current.fetch(:marketplaces)) +
        to_install.map { |entry| ["bb", "plugin", "install", entry, "--yes"] } +
        enable_commands(desired["enable"], installed, to_install.map { |entry| plugin_id(entry) }) +
        setting_commands(desired["settings"], current.fetch(:settings)) +
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

    def setting_commands(settings, current_settings)
      settings
        .reject { |key, value| current_settings[key] == value }
        .map { |key, value| ["bb", "settings", "general", key, value.to_s] }
    end

    def theme_commands(theme, current_theme)
      return [] if theme.nil? || theme == current_theme

      [["bb", "theme", "set", theme]]
    end

    def current_state
      settings = bb_json("settings", "show")
      {
        marketplaces: bb_json("marketplace", "list").map { |marketplace| marketplace.fetch("name") },
        plugins: bb_json("plugin", "list").fetch("plugins").to_h { |plugin| [plugin.fetch("id"), plugin.fetch("enabled")] },
        settings: settings.fetch("generalSettings"),
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
      unless Installer::Utils.command?("bb")
        Installer::Utils.warn("bb CLI not found, skipping bb setup: #{CLI_HINT}")
        return false
      end

      commands = plan(desired_state(config, profile), current_state)
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
