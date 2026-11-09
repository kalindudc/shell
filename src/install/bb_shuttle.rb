# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require_relative "errors"
require_relative "utils"
require_relative "bb"
require_relative "bb_app"
require_relative "private_repo"

module Installer
  # Backs up the Shuttle plugin's configuration to the private repo: the servers, presets and automations
  # that `bb shuttle config-export` prints as TOML, and every plugin setting. They name work servers, their
  # commands and review prompts, so they never go to this public repo. Restoring imports the TOML and sets
  # each saved setting that differs; Shuttle's database (PRs, boards, drafts, history) is not part of it.
  module BbShuttle
    PLUGIN = "shuttle"
    CONFIG_FILE = "config.toml"
    SETTINGS_FILE = "settings.json"
    # Settings that hold an id of this machine's bb, which names nothing on another machine.
    LOCAL_TYPES = %w[project].freeze
    NO_CHANGES = "No changes."

    module_function

    def root(dir = PrivateRepo.dir)
      File.join(dir, "bb", "shuttle")
    end

    # The settings worth saving, sorted: every value except local ids. A secret stops the export.
    def portable_settings(config)
      schema = config.fetch("schema")
      config.fetch("values").sort.each_with_object({}) do |(key, value), out|
        field = schema.fetch(key) { raise Installer::Error, "Shuttle's setting #{key} has no schema; check it before backing it up" }
        raise Installer::Error, "Shuttle's setting #{key} is a secret; a Git repo is not a credential store" if field["secret"] || field["type"] == "secret"
        next if LOCAL_TYPES.include?(field["type"])

        out[key] = value
      end
    end

    def setting_commands(saved, live)
      saved.reject { |key, value| live[key] == value }.map do |key, value|
        ["bb", "plugin", "config", PLUGIN, "set", key, value.is_a?(String) ? value : JSON.generate(value)]
      end
    end

    def bb_text(*args)
      stdout, stderr, status = Open3.capture3("bb", *args)
      unless status.success?
        detail = stderr.strip.empty? ? "" : ": #{stderr.strip}"
        raise Installer::CommandFailed, "Command failed: bb #{args.join(" ")}#{detail}"
      end

      stdout.force_encoding(Encoding::UTF_8)
    end

    # The import's preview of a TOML file: what it would change in Shuttle's config, or "No changes."
    def import_preview(file)
      bb_text(PLUGIN, "config-import", file)
    end

    def unchanged?(preview)
      preview.lstrip.start_with?(NO_CHANGES)
    end

    def ready?
      unless Installer::BbApp.ensure_running!
        Installer::Utils.warn("bb is not installed or did not start; open bb and run the task again")
        return false
      end

      Installer::BbApp.install_cli_command!
      true
    end

    def require_private_repo!
      return if PrivateRepo.present?

      raise Installer::Error, "no private repo at #{PrivateRepo.dir}: clone #{PrivateRepo::REMOTE} there or set SHELL_PRIVATE_DIR"
    end

    def export!(dir = root)
      return false unless ready?

      require_private_repo!
      toml = bb_text(PLUGIN, "config-export")
      raise Installer::Error, "bb shuttle config-export printed no servers; kept the saved copy" unless toml.include?("[[server]]")

      settings = portable_settings(Installer::Bb.bb_json("plugin", "config", PLUGIN))
      FileUtils.mkdir_p(dir)
      config_path = File.join(dir, CONFIG_FILE)
      staged = "#{config_path}.new"
      File.write(staged, toml.end_with?("\n") ? toml : "#{toml}\n")
      begin
        # A backup that would not restore to what Shuttle has now is no backup, so it never replaces the saved one.
        preview = import_preview(staged)
        raise Installer::Error, "the exported #{CONFIG_FILE} would change Shuttle's config if restored; kept the saved copy:\n#{preview}" unless unchanged?(preview)

        File.rename(staged, config_path)
      ensure
        FileUtils.rm_f(staged)
      end
      File.write(File.join(dir, SETTINGS_FILE), "#{JSON.pretty_generate(settings)}\n")
      Installer::Utils.success("Saved Shuttle's config and #{settings.size} settings in #{dir}; review and commit the private repo")
      true
    end

    def apply!(dir = root, dry_run: false)
      return false unless ready?

      require_private_repo!
      config_path = File.join(dir, CONFIG_FILE)
      settings_path = File.join(dir, SETTINGS_FILE)
      [config_path, settings_path].each do |path|
        raise Installer::Error, "nothing saved at #{path}; run task bb:shuttle:export on the machine to keep" unless File.file?(path)
      end

      preview = import_preview(config_path)
      live = Installer::Bb.bb_json("plugin", "config", PLUGIN).fetch("values")
      commands = setting_commands(JSON.parse(File.read(settings_path)), live)
      Installer::Utils.log("Preview only: nothing changes") if dry_run
      report(preview, commands)
      return true if dry_run

      Installer::Utils.run!("bb", PLUGIN, "config-import", config_path, "--apply") unless unchanged?(preview)
      commands.each { |command| Installer::Utils.run!(*command) }
      true
    end

    def report(preview, commands)
      if unchanged?(preview) && commands.empty?
        Installer::Utils.log("Shuttle already matches the saved config and settings")
        return
      end

      puts(preview.strip) unless unchanged?(preview)
      commands.each { |command| puts(Installer::Utils.command_line(command)) }
    end
  end
end
