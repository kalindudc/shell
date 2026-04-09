# frozen_string_literal: true

module Installer
  module OS
    BACKENDS = {
      "arch" => %w[pacman yay flatpak],
      "ubuntu" => %w[apt snap flatpak],
      "debian" => %w[apt flatpak],
      "macos" => %w[brew brew_cask]
    }.freeze

    SHARED_BACKENDS = %w[npm pipx custom].freeze

    module_function

    def detect
      return "macos" if RUBY_PLATFORM.include?("darwin")

      os_release_file = "/etc/os-release"
      return nil unless File.exist?(os_release_file)

      id = parse_os_release(os_release_file, "ID")

      case id
      when "arch", "manjaro"
        "arch"
      when "ubuntu", "debian"
        id
      else
        detect_from_id_like(os_release_file) || id
      end
    end

    def backends_for(os)
      BACKENDS.fetch(os, []) + SHARED_BACKENDS
    end

    def parse_os_release(file, key)
      File.readlines(file)
          .find { |line| line.start_with?("#{key}=") }
          &.split("=", 2)
          &.[](1)
          &.strip
          &.delete('"')
    end

    def detect_from_id_like(os_release_file)
      id_like = parse_os_release(os_release_file, "ID_LIKE") || ""

      return "arch" if id_like.include?("arch")
      return "ubuntu" if id_like.include?("debian") || id_like.include?("ubuntu")

      nil
    end
  end
end
