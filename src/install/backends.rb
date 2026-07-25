# frozen_string_literal: true

require "open3"
require_relative "errors"

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
      when "custom_bootstrap" then install_custom(packages)
      when "custom" then install_custom(packages)
      else raise Installer::Error, "Unknown package backend: #{backend}"
      end
    end

    def ensure_package_managers!(_os, managers)
      Array(managers).each do |manager|
        command = manager.fetch("command")
        next if Installer::Utils.command?(command)

        name = manager.fetch("name", command)
        install_command = manager["install"]
        if install_command
          Installer::Utils.log("Installing #{name} package manager...")
          Installer::Utils.run!(*Array(install_command))
          next if Installer::Utils.command?(command)
        end

        message = "#{name} package manager is required. Install it, then rerun ./install.sh"
        raise Installer::CommandFailed, message unless manager["required"] == false

        Installer::Utils.warn(message)
      end
    end

    def install_bootstrap_dependencies!(packages_by_backend)
      packages_by_backend.each do |backend, packages|
        install(backend, packages)
      end
    end

    def system_update!(os)
      Installer::Utils.log("Updating system packages...")

      case os
      when "arch"
        Installer::Utils.sudo!("pacman", "-Syu", "--noconfirm")
      when "ubuntu", "debian"
        Installer::Utils.sudo!("apt-get", "update")
        Installer::Utils.sudo!("apt-get", "upgrade", "-y")
      when "macos"
        Installer::Utils.run!("brew", "update")
        Installer::Utils.run!("brew", "upgrade")
      else
        raise Installer::Error, "Unsupported operating system: #{os}"
      end
    end

    def system_update(os)
      system_update!(os)
    end

    def install_pacman(packages)
      Installer::Utils.sudo!("pacman", "-S", "--needed", "--noconfirm", *packages)
    end

    def install_yay(packages)
      Installer::Utils.run!("yay", "-S", "--needed", "--noconfirm", *packages)
    end

    def install_apt(packages)
      Installer::Utils.sudo!("apt-get", "install", "-y", *packages)
    end

    def install_brew(packages)
      Installer::Utils.run!("brew", "install", *packages)
    end

    def install_brew_cask(packages)
      packages.each do |package|
        Installer::Utils.try_run("brew", "install", "--cask", package)
      end
    end

    def install_snap(packages)
      packages.each do |entry|
        if entry.is_a?(String)
          Installer::Utils.sudo!("snap", "install", entry)
        elsif entry.is_a?(Hash)
          args = ["snap", "install", entry.fetch("name")]
          args << "--classic" if entry["classic"]
          Installer::Utils.sudo!(*args)
        end
      end
    end

    def install_flatpak(packages)
      return if packages.empty?

      unless Installer::Utils.command?("flatpak")
        Installer::Utils.warn("flatpak not found, skipping optional GUI packages")
        return
      end

      Installer::Utils.try_run("flatpak", "remote-add", "--if-not-exists", "flathub",
                               "https://dl.flathub.org/repo/flathub.flatpakrepo")

      packages.each do |app_id|
        Installer::Utils.try_run("flatpak", "install", "-y", "flathub", app_id)
      end
    end

    def install_npm(packages)
      ensure_npm_available!
      Installer::Utils.run!("npm", "install", "-g", *packages)
    end

    def install_pipx(packages)
      unless Installer::Utils.command?("pipx")
        raise Installer::CommandFailed, "pipx is required before installing pipx packages"
      end

      packages.each do |pkg|
        Installer::Utils.run!("pipx", "install", pkg)
      end
    end

    def install_custom(packages)
      packages.each do |method_name|
        unless Installer::Custom.respond_to?(method_name, true)
          raise Installer::CommandFailed, "Unknown custom installer: #{method_name}"
        end

        Installer::Utils.log("Running custom installer: #{method_name}...")
        Installer::Custom.send(method_name)
      end
    end

    def ensure_npm_available!
      return true if Installer::Utils.command?("npm")

      unless Installer::Utils.command?("fnm")
        raise Installer::CommandFailed, "npm is required and fnm is not available to install Node.js"
      end

      Installer::Utils.log("Installing Node.js via fnm...")
      Installer::Utils.run!("fnm", "install", "--lts")

      env_output, stderr, status = Open3.capture3("fnm", "env")
      unless status.success?
        raise Installer::CommandFailed, "Command failed: fnm env#{stderr.empty? ? "" : ": #{stderr.strip}"}"
      end

      env_output.each_line do |line|
        next unless line =~ /export (\w+)="([^"]*)"/

        ENV[Regexp.last_match(1)] = Regexp.last_match(2)
      end

      return true if Installer::Utils.command?("npm")

      raise Installer::CommandFailed, "npm is still unavailable after fnm installed Node.js"
    end
  end
end
