# frozen_string_literal: true

require_relative "utils"
require_relative "cli"
require_relative "errors"
require_relative "state"
require_relative "dependencies"
require_relative "os"
require_relative "backends"
require_relative "custom"
require_relative "post_setup"
require_relative "bb"
require_relative "bb_automations"
require_relative "cortex"

module Installer
  class Runner
    SHELL_DIR = File.expand_path("../..", __dir__)

    def initialize(options)
      @options = options
      @sudo_pid = nil
      @state = State.new
    end

    def run
      Utils.state = @state

      if @options[:stow_only]
        PostSetup.stow_dotfiles!
        return
      end

      if @options[:bb_only]
        PostSetup.load_env_file
        Bb.apply!(profile: Dependencies.new(load_packages, nil).profile_name)
        return
      end

      if @options[:bb_automations_export]
        BbAutomations.export!
        return
      end

      if @options[:bb_automations]
        BbAutomations.apply!(update: @options[:update])
        return
      end

      if @options[:cortex_only]
        Cortex.install!
        return
      end

      start_sudo_keepalive

      resume_after_reboot = @state.reboot_required?
      Utils.log("Continuing after reboot-required changes...") if resume_after_reboot

      os = detect_os
      packages = load_packages
      dependencies = Dependencies.new(packages, os)
      backends = OS.backends_for(os)

      Backends.ensure_package_managers!(os, dependencies.package_managers)
      Backends.install_bootstrap_dependencies!(dependencies.bootstrap_packages)
      Backends.system_update!(os)
      install_packages!(packages, backends)
      run_post_setup!
      apply_bb_state(dependencies.profile_name)
      # after bb, so `cortex agents install` finds bb running and installs its bb plugin
      setup_cortex
      @state.clear_reboot! if resume_after_reboot

      Utils.success("Installation complete!")
      Utils.log("Please restart your shell or run: source ~/.zshrc")
    rescue Installer::RebootRequired
      Utils.warn("A reboot or new login session is required before installation can continue:")
      @state.data.fetch("reboot_required", []).each { |reason| Utils.warn("- #{reason}") }
      Utils.warn("Reboot or log out/in, then run ./install.sh again.")
      exit 0
    rescue Interrupt
      Utils.warn("Installation interrupted")
      exit 130
    rescue StandardError => e
      Utils.error("Installation failed: #{e.message}")
      puts e.backtrace if @options[:verbose]
      exit 1
    ensure
      stop_sudo_keepalive
    end

    private

    def start_sudo_keepalive
      return if Utils.root? || Utils.ci?

      Utils.log("Requesting sudo access...")
      Utils.run!("sudo", "-v")

      @sudo_pid = spawn("bash", "-c", "while true; do sudo -n true; sleep 50; done")
    end

    def stop_sudo_keepalive
      return unless @sudo_pid

      Process.kill("TERM", @sudo_pid)
    rescue StandardError
      nil
    end

    def detect_os
      os = OS.detect
      raise Installer::Error, "Unsupported operating system" unless os && OS.supported?(os)

      Utils.log("Detected OS: #{os}")
      os
    end

    def load_packages
      packages_file = File.join(SHELL_DIR, "packages.yml")
      raise Installer::Error, "packages.yml not found" unless File.exist?(packages_file)

      YAML.load_file(packages_file)
    end

    def install_packages!(packages, backends)
      skip_backends = ENV.fetch("SKIP_BACKENDS", "").split(",").map(&:strip)

      backends.each do |backend|
        if skip_backends.include?(backend)
          Utils.log("Skipping #{backend} (SKIP_BACKENDS)")
          next
        end

        pkgs = packages[backend]
        Backends.install(backend, pkgs)
      end
    end

    # Optional during an install: bb may not have started, or may not answer yet.
    def apply_bb_state(profile)
      Bb.apply!(profile: profile)
    rescue Installer::CommandFailed => e
      Utils.warn("Skipped bb setup: #{e.message}")
      Utils.warn("Open bb, then run: task bb")
    end

    def setup_cortex
      Cortex.install!
    rescue Installer::CommandFailed => e
      Utils.warn("Skipped cortex setup: #{e.message}")
      Utils.warn("Fix the error above, then run: task cortex")
    end

    def run_post_setup!
      PostSetup.load_env_file
      PostSetup.load_git_config_fallbacks
      PostSetup.setup_go_task_symlink!
      PostSetup.setup_gpg_key
      PostSetup.generate_configs!
      PostSetup.stow_dotfiles!
      PostSetup.bootstrap_pi_extensions!
      PostSetup.bootstrap_skill_notes!
      PostSetup.set_default_shell!
    end
  end
end
