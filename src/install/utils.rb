# frozen_string_literal: true

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

    def run(*cmd, **opts)
      puts "  $ #{cmd.join(" ")}" if $VERBOSE
      return true if system(*cmd, **opts)

      error("Command failed: #{cmd.join(" ")}")
      false
    end

    def sudo(*cmd)
      return run(*cmd) if root?

      run("sudo", *cmd)
    end
  end
end
