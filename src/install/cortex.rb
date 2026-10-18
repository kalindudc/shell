# frozen_string_literal: true

require "fileutils"
require "open3"
require_relative "errors"

module Installer
  # cortex builds from source in a private repository. `cortex agents install` then writes its
  # agent skills, its pi extension and, when bb is running, its bb plugin.
  module Cortex
    REPO = "kalindudc/cortex"
    # beside this checkout, as ~/src/github.com/kalindudc/cortex
    CHECKOUT = File.expand_path("../../../cortex", __dir__)
    # where `pnpm run deploy` copies the binary
    BINARY = File.join(Dir.home, "bin", "cortex")
    HINT = "then run: task cortex"

    module_function

    def database
      ENV.fetch("CORTEX_DB") do
        File.join(ENV.fetch("XDG_CONFIG_HOME", File.join(Dir.home, ".config")), "cortex", "cortex.db")
      end
    end

    # An installed cortex is never rebuilt, and an existing checkout is never pulled:
    # it may be a working copy with changes in progress.
    def install!(checkout: CHECKOUT, binary: BINARY, database: self.database)
      cortex = executable(binary) || build!(checkout, binary)
      return false unless cortex

      Installer::Utils.run!(cortex, "init") unless File.exist?(database)
      Installer::Utils.run!(cortex, "agents", "install")
      true
    end

    def executable(binary)
      return "cortex" if Installer::Utils.command?("cortex")

      binary if File.executable?(binary)
    end

    def build!(checkout, binary)
      return unless clone!(checkout)

      unless Installer::Utils.command?("pnpm")
        Installer::Utils.warn("cortex setup skipped: pnpm is not installed; install it, #{HINT}")
        return
      end

      Installer::Utils.log("Building cortex from #{checkout}...")
      FileUtils.mkdir_p(File.dirname(binary))
      Installer::Utils.run!("pnpm", "run", "deploy", chdir: checkout)
      binary
    end

    def clone!(checkout)
      return true if File.directory?(File.join(checkout, ".git"))

      unless gh_signed_in?
        Installer::Utils.warn("cortex setup skipped: #{REPO} is private; run `gh auth login`, #{HINT}")
        return false
      end

      FileUtils.mkdir_p(File.dirname(checkout))
      Installer::Utils.run!("gh", "repo", "clone", REPO, checkout)
      true
    end

    def gh_signed_in?
      return false unless Installer::Utils.command?("gh")

      _stdout, _stderr, status = Open3.capture3("gh", "auth", "status", "--hostname", "github.com")
      status.success?
    end
  end
end
