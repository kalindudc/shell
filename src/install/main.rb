# frozen_string_literal: true

require_relative "utils"
require_relative "cli"
require_relative "errors"
require_relative "tools"
require_relative "setup"
require_relative "bb"
require_relative "bb_automations"
require_relative "cortex"

module Installer
  class Runner
    def initialize(options)
      @options = options
    end

    def run
      if @options[:bb_automations_export]
        BbAutomations.export!
        return
      end

      if @options[:bb_automations]
        BbAutomations.apply!(update: @options[:update])
        return
      end

      Setup.load_env_file
      steps.each { |step| run_step(step) }
      Utils.success("Setup complete")
    rescue Interrupt
      Utils.warn("Setup interrupted")
      exit 130
    rescue StandardError => e
      Utils.error("Setup failed: #{e.message}")
      puts e.backtrace if @options[:verbose]
      exit 1
    end

    private

    def steps
      requested = @options[:steps]
      requested.empty? ? CLI::STEPS : CLI::STEPS & requested
    end

    def full_install?
      @options[:steps].empty?
    end

    def run_step(step)
      case step
      when "tools" then Tools.install!
      when "setup" then Setup.run!
      when "bb" then optional("bb", "task bb") { Bb.apply!(profile: profile) }
      when "cortex" then optional("cortex", "task cortex") { Cortex.install! }
      end
    end

    # In a full install bb and cortex may fail softly: bb may not have started yet, and
    # cortex needs access to a private repo. Run on their own, their errors fail the command.
    def optional(name, retry_command)
      yield
    rescue Installer::CommandFailed => e
      raise unless full_install?

      Utils.warn("Skipped #{name} setup: #{e.message}")
      Utils.warn("Fix the error above, then run: #{retry_command}")
    end

    def profile
      requested = ENV["SHELL_MACHINE_PROFILE"].to_s.strip
      requested.empty? ? "default" : requested
    end
  end
end
