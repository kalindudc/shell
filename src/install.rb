#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative 'install/main'

# constants
$VERBOSE = false

# Parse CLI args
options = Installer::CLI.parse_args(ARGV)
$VERBOSE = options[:verbose]

# Run installer
Installer::Runner.new(options).run
