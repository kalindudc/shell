#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'install/cli'

# constants
$VERBOSE = false

# Parse CLI args before loading installer dependencies so `--help` remains
# available even when local Ruby user gems are stale or broken.
options = Installer::CLI.parse_args(ARGV)
$VERBOSE = options[:verbose]

require 'yaml'
require_relative 'install/main'

# Run installer
Installer::Runner.new(options).run
