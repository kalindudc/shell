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
      # `command` is a shell builtin, so the check must go through a shell;
      # passing it as an argv list makes Ruby exec a (nonexistent) `command` binary.
      system("command -v #{Shellwords.escape(name)} >/dev/null 2>&1", out: File::NULL, err: File::NULL)
    end

    def root?
      Process.uid.zero?
    end

    def ci?
      ENV["CI"] || ENV["NONINTERACTIVE"]
    end

    # A variable already set in the environment wins over .env.
    def load_env!(file = File.expand_path("../../.env", __dir__))
      if File.exist?(file)
        File.readlines(file).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          if line =~ /^(\w+)=(.*)$/
            key = Regexp.last_match(1)
            value = Regexp.last_match(2).delete('"').delete("'")
            ENV[key] = value if ENV[key].to_s.empty?
          end
        end
      end

      ENV["GIT_EMAIL"] = `git config --global user.email 2>/dev/null`.strip if ENV["GIT_EMAIL"].to_s.strip.empty?
      ENV["GIT_NAME"] = `git config --global user.name 2>/dev/null`.strip if ENV["GIT_NAME"].to_s.strip.empty?
      return unless ENV["GIT_SIGNING_KEY"].to_s.strip.empty?

      ENV["GIT_SIGNING_KEY"] = `git config --global user.signingkey 2>/dev/null`.strip
    end

    def login_required(reason)
      login_reasons << reason unless login_reasons.include?(reason)
    end

    def login_reasons
      @login_reasons ||= []
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

    def command_line(cmd)
      Shellwords.join(Array(cmd).map(&:to_s))
    end
  end
end
