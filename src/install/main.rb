# frozen_string_literal: true

require_relative "utils"
require_relative "cli"
require_relative "errors"
require_relative "platform"
require_relative "packages"
require_relative "tools"
require_relative "setup"
require_relative "generate"
require_relative "stow"
require_relative "bb"
require_relative "cortex"

module Installer
  class Runner
    SUDO_STEPS = %w[packages tools setup].freeze
    # In a full install these warn and the install goes on; bb may not start, cortex needs gh sign-in.
    BEST_EFFORT_STEPS = %w[bb cortex].freeze

    def initialize(options)
      @options = options
      @sudo_pid = nil
    end

    def run
      Utils.load_env!
      # not Array#intersect?, which needs Ruby 3.1; Ubuntu 22.04 ships 3.0
      start_sudo_keepalive if (@options[:steps] & SUDO_STEPS).any? # rubocop:disable Style/ArrayIntersect
      @options[:steps].each { |step| run_step(step) }

      unless Utils.login_reasons.empty?
        Utils.warn("Log out and back in, or restart, for:")
        Utils.login_reasons.each { |reason| Utils.warn("- #{reason}") }
      end
      Utils.success("Done")
      Utils.log("Restart your shell or run: exec zsh") if @options[:all]
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

    def run_step(step)
      case step
      when "packages" then Packages.install!(Platform.detect!)
      when "tools" then Tools.install!
      when "setup" then Setup.run!
      when "generate" then Generate.run!(@options[:targets])
      when "stow" then Stow.run!
      when "bb" then Bb.apply!(profile: profile)
      when "cortex" then Cortex.install!
      end
    rescue Installer::CommandFailed => e
      raise unless @options[:all] && BEST_EFFORT_STEPS.include?(step)

      Utils.warn("Skipped #{step}: #{e.message}")
      Utils.warn("Fix the error above, then run: task install:#{step}")
    end

    def profile
      requested = ENV["SHELL_MACHINE_PROFILE"].to_s.strip
      requested.empty? ? "default" : requested
    end

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
  end
end
