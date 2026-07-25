# frozen_string_literal: true

require "shellwords"
require_relative "errors"

module Installer
  module Utils
    COLORS = {
      blue: "\e[0;34m",
      bold: "\e[1m",
      green: "\e[0;32m",
      yellow: "\e[0;33m",
      red: "\e[0;31m",
      reset: "\e[0m"
    }.freeze

    module_function

    def log(msg)
      puts "#{COLORS[:blue]}==>#{COLORS[:bold]} #{msg}#{COLORS[:reset]}"
    end

    def success(msg)
      puts "#{COLORS[:green]}✓ #{msg}#{COLORS[:reset]}"
    end

    def warn(msg)
      puts "#{COLORS[:yellow]}! #{msg}#{COLORS[:reset]}"
    end

    def error(msg)
      puts "#{COLORS[:red]}✗ #{msg}#{COLORS[:reset]}"
    end

    def command?(name)
      system("command", "-v", name, out: File::NULL, err: File::NULL)
    end

    def root?
      Process.uid.zero?
    end

    def ci?
      ENV["CI"] || ENV["NONINTERACTIVE"]
    end

    def state=(state)
      @state = state
    end

    def run!(*cmd, **opts)
      puts "  $ #{command_line(cmd)}" if $VERBOSE
      return true if system(*cmd, **opts)

      raise Installer::CommandFailed, "Command failed: #{command_line(cmd)}"
    end

    def try_run(*cmd, **opts)
      puts "  $ #{command_line(cmd)}" if $VERBOSE
      return true if system(*cmd, **opts)

      warn("Optional command failed: #{command_line(cmd)}")
      false
    end

    def sudo!(*cmd)
      return run!(*cmd) if root?

      run!("sudo", *cmd)
    end

    def try_sudo(*cmd)
      return try_run(*cmd) if root?

      try_run("sudo", *cmd)
    end

    def reboot_required!(reason)
      @state&.require_reboot(reason)
      raise Installer::RebootRequired, reason
    end

    def command_line(cmd)
      Shellwords.join(Array(cmd).map(&:to_s))
    end

    def run(*cmd, **opts)
      try_run(*cmd, **opts)
    end

    def sudo(*cmd)
      return run(*cmd) if root?

      run("sudo", *cmd)
    end
  end
end
