# frozen_string_literal: true

require "open3"
require "yaml"
require_relative "errors"
require_relative "platform"

module Installer
  # Installs the packages.yml lists for this platform.
  module Packages
    FILE = File.expand_path("../../packages.yml", __dir__)
    COMMANDS = {
      "brew" => "brew", "brew_cask" => "brew", "pacman" => "pacman", "yay" => "yay",
      "apt" => "apt-get", "snap" => "snap", "flatpak" => "flatpak", "npm" => "npm", "pi" => "pi",
      "pipx" => "pipx"
    }.freeze
    # Without these the platform has no packages at all; any other backend is skipped when missing.
    REQUIRED = %w[brew pacman apt].freeze

    module_function

    def install!(platform, packages: YAML.load_file(FILE), skip: ENV.fetch("SKIP_BACKENDS", ""))
      skip_backends = skip.split(",").map(&:strip)
      system_update!(platform)

      Installer::Platform.backends(platform).each do |backend|
        if skip_backends.include?(backend)
          Installer::Utils.log("Skipping #{backend} (SKIP_BACKENDS)")
          next
        end

        install(backend, packages[backend])
      end
    end

    def install(backend, list)
      return if list.nil? || list.empty?

      ensure_node! if backend == "npm"
      command = COMMANDS.fetch(backend)
      unless Installer::Utils.command?(command)
        raise Installer::CommandFailed, "#{command} is required for #{backend} packages" if REQUIRED.include?(backend)

        Installer::Utils.warn("#{command} not found, skipping #{backend} packages")
        return
      end

      Installer::Utils.log("Installing #{backend} packages...")
      send("install_#{backend}", list)
    end

    def system_update!(platform)
      Installer::Utils.log("Updating system packages...")

      case platform
      when "arch"
        Installer::Utils.sudo!("pacman", "-Syu", "--noconfirm")
      when "debian"
        Installer::Utils.sudo!("apt-get", "update")
        Installer::Utils.sudo!("apt-get", "upgrade", "-y")
      when "macos"
        Installer::Utils.run!("brew", "update")
        Installer::Utils.run!("brew", "upgrade")
      else
        raise Installer::Error, "Unsupported operating system: #{platform}"
      end
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
      Installer::Utils.try_run("flatpak", "remote-add", "--if-not-exists", "flathub",
                               "https://dl.flathub.org/repo/flathub.flatpakrepo")

      packages.each do |app_id|
        Installer::Utils.try_run("flatpak", "install", "-y", "flathub", app_id)
      end
    end

    def install_npm(packages)
      Installer::Utils.run!("npm", "install", "-g", *packages)
    end

    # pi packages (extensions, skills, prompts) are declared in ~/.pi/agent/settings.json by
    # `pi install`. That file stays untracked because it also holds per-machine model choices.
    # --no-approve keeps a project .pi in the current directory out of a global install.
    def install_pi(packages)
      installed = installed_pi_packages
      packages.each do |source|
        if installed.include?(source)
          Installer::Utils.log("pi package already installed: #{source}")
          next
        end

        Installer::Utils.run!("pi", "install", source, "--no-approve")
      end
    end

    def installed_pi_packages
      stdout, stderr, status = Open3.capture3("pi", "list", "--no-approve")
      unless status.success?
        raise Installer::CommandFailed, "Command failed: pi list#{stderr.empty? ? "" : ": #{stderr.strip}"}"
      end

      stdout.lines.map(&:strip)
    end

    def install_pipx(packages)
      packages.each do |pkg|
        Installer::Utils.run!("pipx", "install", pkg)
      end
    end

    # brew and pacman install fnm; on Debian it comes from its install script, which needs unzip.
    def ensure_node!
      return true if Installer::Utils.command?("npm")

      unless Installer::Utils.command?("fnm")
        Installer::Utils.log("Installing fnm...")
        Installer::Utils.run!("bash", "-c", "curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell")
        ENV["PATH"] = [File.join(Dir.home, ".local/share/fnm"), ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR)
      end

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
