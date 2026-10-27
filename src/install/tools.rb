# frozen_string_literal: true

require "open3"
require "yaml"
require_relative "errors"
require_relative "bb_app"

module Installer
  # Tools that Nix does not install: npm, pi and pipx packages from packages.yml, herdr's
  # plugins and pi integration, and the bb AppImage on Linux.
  module Tools
    SHELL_DIR = File.expand_path("../..", __dir__)
    PACKAGES_FILE = File.join(SHELL_DIR, "packages.yml")

    module_function

    def install!(packages: YAML.load_file(PACKAGES_FILE))
      install_npm(Array(packages["npm"]))
      install_pi(Array(packages["pi"]))
      install_pipx(Array(packages["pipx"]))
      install_herdr_plus
      install_herdr_automatic_rename
      install_herdr_pi_integration
      # macOS gets bb from the `bb` cask (nix/darwin/default.nix)
      Installer::BbApp.install_appimage!
    end

    def install_npm(packages)
      return if packages.empty?

      Installer::Utils.log("Installing npm packages...")
      ensure_npm_available!
      Installer::Utils.run!("npm", "install", "-g", *packages)
    end

    # pi packages (extensions, skills, prompts) are declared in ~/.pi/agent/settings.json by
    # `pi install`. That file stays untracked because it also holds per-machine model choices.
    # --no-approve keeps a project .pi in the current directory out of a global install.
    def install_pi(packages)
      return if packages.empty?
      raise Installer::CommandFailed, "pi is required before installing pi packages" unless Installer::Utils.command?("pi")

      installed = installed_pi_packages
      packages.each do |source|
        if installed.include?(source)
          Installer::Utils.log("pi package already installed: #{source}")
          next
        end

        Installer::Utils.run!("pi", "install", source, "--no-approve")
      end
    end

    def installed_pi_packages
      stdout, stderr, status = Open3.capture3("pi", "list", "--no-approve")
      unless status.success?
        raise Installer::CommandFailed, "Command failed: pi list#{stderr.empty? ? "" : ": #{stderr.strip}"}"
      end

      stdout.lines.map(&:strip)
    end

    def install_pipx(packages)
      return if packages.empty?

      unless Installer::Utils.command?("pipx")
        raise Installer::CommandFailed, "pipx is required before installing pipx packages"
      end

      packages.each do |pkg|
        Installer::Utils.run!("pipx", "install", pkg)
      end
    end

    def install_herdr_plus
      return unless Installer::Utils.command?("herdr")
      return if `herdr plugin list 2>/dev/null`.include?("cloudmanic.herdr-plus")

      Installer::Utils.log("Installing herdr-plus plugin...")
      Installer::Utils.run!("herdr", "plugin", "install", "cloudmanic/herdr-plus", "--yes")
    end

    def install_herdr_automatic_rename
      return unless Installer::Utils.command?("herdr")
      return if `herdr plugin list 2>/dev/null`.include?("herdr-automatic-rename")

      Installer::Utils.log("Installing herdr-automatic-rename plugin...")
      Installer::Utils.run!("herdr", "plugin", "install", "qu8n/herdr-automatic-rename", "--yes")
    end

    # Reports pi agent state (working, idle, waiting) to the herdr sidebar. herdr owns the
    # file it writes (~/.pi/agent/extensions/herdr-agent-state.ts) and overwrites it on reinstall,
    # so an outdated integration is reinstalled too.
    def install_herdr_pi_integration
      return unless Installer::Utils.command?("herdr")
      return if herdr_integration_status.lines.any? { |line| line.start_with?("pi: current") }

      Installer::Utils.log("Installing herdr pi integration...")
      Installer::Utils.run!("herdr", "integration", "install", "pi")
    end

    def herdr_integration_status
      `herdr integration status 2>/dev/null`
    end

    # Node comes from fnm (or Tec on the work Mac), so global npm packages stay writable.
    def ensure_npm_available!
      return true if Installer::Utils.command?("npm")

      unless Installer::Utils.command?("fnm")
        raise Installer::CommandFailed, "npm is required and fnm is not available to install Node.js"
      end

      Installer::Utils.log("Installing Node.js via fnm...")
      Installer::Utils.run!("fnm", "install", "--lts")

      env_output, stderr, status = Open3.capture3("fnm", "env")
      unless status.success?
        raise Installer::CommandFailed, "Command failed: fnm env#{stderr.empty? ? "" : ": #{stderr.strip}"}"
      end

      env_output.each_line do |line|
        next unless line =~ /export (\w+)="([^"]*)"/

        ENV[Regexp.last_match(1)] = Regexp.last_match(2)
      end

      return true if Installer::Utils.command?("npm")

      raise Installer::CommandFailed, "npm is still unavailable after fnm installed Node.js"
    end
  end
end
