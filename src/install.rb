#!/usr/bin/env ruby
# frozen_string_literal: true

# The setup steps that Nix does not manage. install.sh runs them after the first switch;
# the Taskfile runs one at a time (task tools, task setup, task bb, task cortex).

require_relative 'install/cli'

$VERBOSE = false

# Parse CLI args before loading installer dependencies so `--help` remains
# available even when local Ruby user gems are stale or broken.
options = Installer::CLI.parse_args(ARGV)
$VERBOSE = options[:verbose]

require_relative 'install/main'

Installer::Runner.new(options).run
