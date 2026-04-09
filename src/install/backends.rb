# frozen_string_literal: true

module Installer
  module Backends
    module_function

    def install(backend, packages)
      return if packages.nil? || packages.empty?

      Installer::Utils.log("Installing #{backend} packages...")

      case backend
      when "pacman" then install_pacman(packages)
      when "yay" then install_yay(packages)
      when "apt" then install_apt(packages)
      when "brew" then install_brew(packages)
      when "brew_cask" then install_brew_cask(packages)
      when "snap" then install_snap(packages)
      when "flatpak" then install_flatpak(packages)
      when "npm" then install_npm(packages)
      when "pipx" then install_pipx(packages)
      when "custom" then install_custom(packages)
      end
    end

    def system_update(os)
      Installer::Utils.log("Updating system packages...")

      case os
      when "arch"
        Installer::Utils.sudo("pacman", "-Syu", "--noconfirm")
      when "ubuntu", "debian"
        Installer::Utils.sudo("apt-get", "update")
        Installer::Utils.sudo("apt-get", "upgrade", "-y")
      when "macos"
        Installer::Utils.run("brew", "update")
        Installer::Utils.run("brew", "upgrade")
      end
    end

    def install_pacman(packages)
      Installer::Utils.sudo("pacman", "-S", "--needed", "--noconfirm", *packages)
    end

    def install_yay(packages)
      Installer::Utils.run("yay", "-S", "--needed", "--noconfirm", *packages)
    end

    def install_apt(packages)
      Installer::Utils.sudo("apt-get", "install", "-y", *packages)
    end

    def install_brew(packages)
      Installer::Utils.run("brew", "install", *packages)
    end

    def install_brew_cask(packages)
      Installer::Utils.run("brew", "install", "--cask", *packages)
    end

    def install_snap(packages)
      packages.each do |entry|
        if entry.is_a?(String)
          Installer::Utils.sudo("snap", "install", entry)
        elsif entry.is_a?(Hash)
          args = ["snap", "install", entry["name"]]
          args << "--classic" if entry["classic"]
          Installer::Utils.sudo(*args)
        end
      end
    end

    def install_flatpak(packages)
      return if packages.empty?

      unless Installer::Utils.command?("flatpak")
        Installer::Utils.warn("flatpak not found, skipping flatpak packages")
        return
      end

      Installer::Utils.run("flatpak", "remote-add", "--if-not-exists", "flathub",
                           "https://dl.flathub.org/repo/flathub.flatpakrepo")

      packages.each do |app_id|
        Installer::Utils.run("flatpak", "install", "-y", "flathub", app_id)
      end
    end

    def install_npm(packages)
      return unless ensure_npm_available

      Installer::Utils.run("npm", "install", "-g", *packages)
    end

    def install_pipx(packages)
      return unless Installer::Utils.command?("pipx")

      packages.each do |pkg|
        Installer::Utils.run("pipx", "install", pkg)
      end
    end

    def install_custom(packages)
      packages.each do |method_name|
        if Installer::Custom.respond_to?(method_name, true)
          Installer::Utils.log("Running custom installer: #{method_name}...")
          Installer::Custom.send(method_name)
        else
          Installer::Utils.warn("Unknown custom installer: #{method_name}")
        end
      end
    end

    def ensure_npm_available
      return true if Installer::Utils.command?("npm")
      return false unless Installer::Utils.command?("fnm")

      Installer::Utils.log("Installing Node.js via fnm...")
      Installer::Utils.run("fnm", "install", "--lts")

      env_output = `fnm env`.strip
      env_output.each_line do |line|
        if line =~ /export (\w+)="([^"]*)"/
          ENV[Regexp.last_match(1)] = Regexp.last_match(2)
        end
      end

      Installer::Utils.command?("npm")
    end
  end
end
