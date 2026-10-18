# frozen_string_literal: true

module Installer
  module CLI
    module_function

    def parse_args(args)
      options = {
        verbose: false,
        stow_only: false,
        bb_only: false,
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
        when "--cortex"
          options[:cortex_only] = true
        when "--help", "-h"
          show_help
          exit 0
        end
      end

      options
    end

    def show_help
      puts "Usage: install.rb [OPTIONS]"
      puts ""
      puts "OPTIONS:"
      puts "  --trace    Enable verbose output"
      puts "  --stow     Run stow only and exit"
      puts "  --bb       Start bb if needed, apply bb.yml and exit"
      puts "  --cortex   Install cortex and its agent skills, pi extension and bb plugin, then exit"
      puts "  --help     Show this help message"
    end
  end
end
