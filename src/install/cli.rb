# frozen_string_literal: true

module Installer
  module CLI
    STEPS = %w[packages tools setup generate stow bb cortex].freeze
    GENERATE_TARGETS = %w[zsh git ghostty].freeze

    module_function

    def parse_args(args)
      options = { verbose: false, steps: [], targets: [] }

      args.each do |arg|
        case arg
        when "--trace" then options[:verbose] = true
        when "--help", "-h"
          show_help
          exit 0
        when *STEPS then options[:steps] << arg
        when *GENERATE_TARGETS then options[:targets] << arg
        else usage_error("Unknown argument: #{arg}")
        end
      end

      unless options[:targets].empty? || options[:steps].include?("generate")
        usage_error("#{options[:targets].join(" ")} needs the generate step: ./install.sh generate #{options[:targets].join(" ")}")
      end

      options[:all] = options[:steps].empty?
      options[:steps] = options[:all] ? STEPS.dup : STEPS & options[:steps]
      options[:targets] = options[:targets].empty? ? GENERATE_TARGETS.dup : GENERATE_TARGETS & options[:targets]
      options
    end

    def usage_error(message)
      puts message
      puts ""
      show_help
      exit 2
    end

    def show_help
      puts <<~HELP
        Usage: ./install.sh [--trace] [STEP...]

        Runs the given steps in this order, or every step when none is given:
          packages   Install the packages.yml lists for this platform, plus npm, pi and pipx packages
          tools      Install tools no package manager provides (zsh plugins, starship, herdr, ...)
          setup      Set up installed tools: docker, GPG signing key, herdr plugins, pi extensions, default shell
          generate   Write home/.zshrc, home/.gitconfig and the ghostty font-size config;
                     add zsh, git or ghostty to write only those
          stow       Link home/ into $HOME
          bb         Start bb if needed and apply bb.yml
          cortex     Install cortex, then its agent skills, pi extension and bb plugin

        OPTIONS:
          --trace    Print each command before running it
          --help     Show this help message
      HELP
    end
  end
end
