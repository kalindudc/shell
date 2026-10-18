# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"
require_relative "errors"

module Installer
  # The bb desktop app: the AppImage install on Linux (macOS uses the `bb` cask), and starting
  # bb so the bb.yml step finds its server and command line tool.
  module BbApp
    APPIMAGE = File.join(Dir.home, "Applications", "bb.AppImage")
    DESKTOP_ENTRY = File.join(Dir.home, ".local", "share", "applications", "bb.desktop")
    RELEASES = "https://github.com/get-bb/bb/releases/latest/download"
    START_TIMEOUT = 120
    POLL_SECONDS = 2

    module_function

    # bb writes this launcher when it first starts; `bb settings cli-command install` links it onto PATH.
    def launcher
      File.join(ENV.fetch("BB_DATA_DIR", File.join(Dir.home, ".bb")), "bin", "bb")
    end

    def ensure_running!(timeout: START_TIMEOUT)
      use_launcher!
      return true if running?
      return false unless start!

      Installer::Utils.log("Started bb, waiting up to #{timeout}s for it to answer...")
      deadline = clock + timeout
      while clock < deadline
        sleep(POLL_SECONDS)
        use_launcher!
        return true if running?
      end
      false
    end

    def use_launcher!
      return if Installer::Utils.command?("bb") || !File.executable?(launcher)

      ENV["PATH"] = [File.dirname(launcher), ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR)
    end

    def running?
      return false unless Installer::Utils.command?("bb")

      _stdout, _stderr, status = Open3.capture3("bb", "settings", "cli-command", "show", "--json")
      status.success?
    end

    def start!(platform: RUBY_PLATFORM, env: ENV)
      if platform.include?("darwin")
        system("open", "-g", "-a", "bb", out: File::NULL, err: File::NULL)
      elsif File.executable?(APPIMAGE) && (env["DISPLAY"] || env["WAYLAND_DISPLAY"])
        pid = Process.spawn(APPIMAGE, in: File::NULL, out: File::NULL, err: File::NULL, pgroup: true)
        Process.detach(pid)
        true
      else
        false
      end
    end

    # Puts `bb` on PATH for new shells; bb refuses when another `bb` already comes first.
    def install_cli_command!
      stdout, _stderr, status = Open3.capture3("bb", "settings", "cli-command", "show", "--json")
      return unless status.success?

      info = JSON.parse(stdout.force_encoding(Encoding::UTF_8))
      return if info["onPath"] || !info["supported"]

      Installer::Utils.try_run("bb", "settings", "cli-command", "install")
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # bb publishes an x86_64 AppImage only. Once installed, bb updates the file itself.
    def install_appimage!(platform: RUBY_PLATFORM)
      return unless platform.start_with?("x86_64-linux")

      if File.exist?(APPIMAGE)
        Installer::Utils.log("bb already installed at #{APPIMAGE}")
        return
      end

      install_fuse!
      Dir.mktmpdir("bb-appimage") do |dir|
        manifest = File.join(dir, "latest-linux.yml")
        Installer::Utils.run!("curl", "-fsSL", "-o", manifest, "#{RELEASES}/latest-linux.yml")
        file = appimage_file(YAML.safe_load_file(manifest))

        download = File.join(dir, file.fetch("url"))
        Installer::Utils.run!("curl", "-fL", "--progress-bar", "-o", download, "#{RELEASES}/#{file.fetch("url")}")
        verify_sha512!(download, file.fetch("sha512"))

        FileUtils.mkdir_p(File.dirname(APPIMAGE))
        FileUtils.mv(download, APPIMAGE)
        File.chmod(0o755, APPIMAGE)
      end
      write_desktop_entry
      Installer::Utils.success("Installed bb at #{APPIMAGE}")
    end

    def appimage_file(release)
      file = Array(release["files"]).find { |entry| entry["url"].to_s.end_with?("x86_64.AppImage") }
      raise Installer::CommandFailed, "bb's latest-linux.yml lists no x86_64 AppImage" unless file

      file
    end

    # electron-builder manifests carry the base64 SHA-512 of each file.
    def verify_sha512!(path, expected)
      actual = Digest::SHA512.file(path).base64digest
      return if actual == expected

      raise Installer::CommandFailed, "bb AppImage checksum mismatch: expected #{expected}, got #{actual}"
    end

    # AppImages mount themselves with FUSE 2; Ubuntu 24.04 renamed its package to libfuse2t64.
    def install_fuse!
      if Installer::Utils.command?("pacman")
        Installer::Utils.sudo!("pacman", "-S", "--needed", "--noconfirm", "fuse2")
      elsif Installer::Utils.command?("apt-get")
        package = system("apt-cache", "show", "libfuse2t64", out: File::NULL, err: File::NULL) ? "libfuse2t64" : "libfuse2"
        Installer::Utils.sudo!("apt-get", "install", "-y", package)
      end
    end

    def write_desktop_entry
      FileUtils.mkdir_p(File.dirname(DESKTOP_ENTRY))
      File.write(DESKTOP_ENTRY, <<~ENTRY)
        [Desktop Entry]
        Type=Application
        Name=bb
        Comment=IDE for running and orchestrating coding agents
        Exec=#{APPIMAGE} %U
        Terminal=false
        Categories=Development;
      ENTRY
    end
  end
end
