# frozen_string_literal: true

require_relative "errors"

module Installer
  # macos, arch (Arch and its derivatives) or debian (Debian, Ubuntu and their derivatives).
  module Platform
    BACKENDS = {
      "macos" => %w[brew brew_cask],
      "arch" => %w[pacman yay flatpak],
      "debian" => %w[apt snap flatpak]
    }.freeze
    # pi runs after npm, which installs the pi CLI
    SHARED_BACKENDS = %w[npm pi pipx].freeze

    module_function

    def detect(ruby_platform: RUBY_PLATFORM, os_release: "/etc/os-release")
      return "macos" if ruby_platform.include?("darwin")
      return nil unless File.exist?(os_release)

      ids = [parse_os_release(os_release, "ID")] + parse_os_release(os_release, "ID_LIKE").to_s.split
      return "arch" if ids.include?("arch")

      "debian" if ids.include?("debian") || ids.include?("ubuntu")
    end

    def detect!
      platform = detect
      raise Installer::Error, "Unsupported operating system" unless platform

      Installer::Utils.log("Detected platform: #{platform}")
      platform
    end

    def backends(platform)
      raise Installer::Error, "Unsupported operating system: #{platform}" unless BACKENDS.key?(platform)

      BACKENDS.fetch(platform) + SHARED_BACKENDS
    end

    def parse_os_release(file, key)
      File.readlines(file)
          .find { |line| line.start_with?("#{key}=") }
          &.split("=", 2)
          &.[](1)
          &.strip
          &.delete('"')
    end
  end
end
