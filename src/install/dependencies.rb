# frozen_string_literal: true

require "socket"

module Installer
  class Dependencies
    OS_PACKAGE_BACKENDS = {
      "arch" => "pacman",
      "ubuntu" => "apt",
      "debian" => "apt",
      "macos" => "brew"
    }.freeze

    def initialize(packages, os, env: ENV, hostname: Socket.gethostname)
      @packages = packages || {}
      @os = os
      @env = env
      @hostname = hostname
    end

    def profile_name
      requested = @env["SHELL_MACHINE_PROFILE"].to_s.strip
      return requested unless requested.empty?

      return @hostname if machine_profiles.key?(@hostname)

      "default"
    end

    def package_managers
      Array(@packages.dig("package_managers", @os))
    end

    def bootstrap_packages
      backend = OS_PACKAGE_BACKENDS.fetch(@os, @os)
      packages = Array(profile.fetch("bootstrap", {}).fetch(backend, []))
      return {} if packages.empty?

      { backend => packages }
    end

    private

    def machine_profiles
      @packages.fetch("machine_profiles", {}) || {}
    end

    def profile
      machine_profiles.fetch(profile_name, machine_profiles.fetch("default", {})) || {}
    end
  end
end
