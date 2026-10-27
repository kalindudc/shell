# frozen_string_literal: true

module Installer
  module CLI
    # The order they always run in: pi comes from npm (tools) before its extensions get
    # their dependencies (setup), and bb runs before cortex so `cortex agents install`
    # finds bb running and installs its bb plugin.
    STEPS = %w[tools setup bb cortex].freeze

    module_function

    def parse_args(args)
      options = {
        verbose: false,
        steps: [],
        bb_automations: false,
        bb_automations_export: false,
        update: false
      }

      args.each do |arg|
        case arg
        when *STEPS
          options[:steps] << arg
        when "--trace"
          options[:verbose] = true
        when "--bb-automations"
          options[:bb_automations] = true
        when "--bb-automations-export"
          options[:bb_automations_export] = true
        when "--update"
          options[:update] = true
        when "--help", "-h"
          show_help
          exit 0
        else
          warn "Unknown argument: #{arg}"
          show_help
          exit 2
        end
      end

      options
    end

    def show_help
      puts "Usage: install.rb [STEP...] [OPTIONS]"
      puts ""
      puts "Runs the setup steps that Nix does not manage, in this order (all of them by default):"
      puts "  tools    npm, pi and pipx packages, herdr plugins, and the bb AppImage on Linux"
      puts "  setup    GPG signing key, pi extension dependencies, SKILL_NOTES.md templates"
      puts "  bb       Start bb if needed and apply bb.yml"
      puts "  cortex   Install cortex and its agent skills, pi extension and bb plugin"
      puts ""
      puts "OPTIONS:"
      puts "  --trace                    Enable verbose output"
      puts "  --bb-automations           Restore saved bb automations (create missing ones) and exit"
      puts "  --bb-automations --update  Also make changed automations match the saved files"
      puts "  --bb-automations-export    Save every bb automation to bb/automations or the private repo and exit"
      puts "  --help                     Show this help message"
    end
  end
end
