# frozen_string_literal: true

module Installer
  module CLI
    module_function

    def parse_args(args)
      options = {
        verbose: false,
        stow_only: false,
        bb_only: false,
        bb_export: false,
        dry_run: false,
        bb_automations: false,
        bb_automations_export: false,
        update: false,
        cortex_only: false
      }

      args.each do |arg|
        case arg
        when "--trace"
          options[:verbose] = true
        when "--stow"
          options[:stow_only] = true
        when "--bb"
          options[:bb_only] = true
        when "--bb-export"
          options[:bb_export] = true
        when "--dry-run"
          options[:dry_run] = true
        when "--bb-automations"
          options[:bb_automations] = true
        when "--bb-automations-export"
          options[:bb_automations_export] = true
        when "--update"
          options[:update] = true
        when "--cortex"
          options[:cortex_only] = true
        when "--help", "-h"
          show_help
          exit 0
        end
      end

      raise ArgumentError, "--dry-run requires --bb; no installation was run" if options[:dry_run] && !options[:bb_only]
      actions = options.values_at(:stow_only, :bb_only, :bb_export, :bb_automations, :bb_automations_export, :cortex_only)
      raise ArgumentError, "Choose only one installer action" if actions.count(true) > 1

      options
    end

    def show_help
      puts "Usage: install.rb [OPTIONS]"
      puts ""
      puts "OPTIONS:"
      puts "  --trace    Enable verbose output"
      puts "  --stow     Run stow only and exit"
      puts "  --bb       Start bb if needed, apply bb.yml and exit"
      puts "  --bb --dry-run  Preview changes without starting or modifying bb"
      puts "  --bb-export    Capture only the settings and plugins approved in bb.yml"
      puts "  --bb-automations         Restore saved bb automations (create missing ones) and exit"
      puts "  --bb-automations --update  Also make changed automations match the saved files"
      puts "  --bb-automations-export  Save every bb automation to bb/automations or the private repo and exit"
      puts "  --cortex   Install cortex and its agent skills, pi extension and bb plugin, then exit"
      puts "  --help     Show this help message"
    end
  end
end
