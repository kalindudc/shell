# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "tempfile"
require "tmpdir"
require_relative "bb_app"

module Installer
  # Tools that no package list provides. Each installer skips when its command is already there.
  module Tools
    FZF_MIN_VERSION = "0.59.0"
    ALL = %i[
      install_pyenv install_gum install_zsh_plugins install_fzf_latest install_atuin
      install_delta_deb install_zoxide_curl install_starship_curl install_herdr install_bb_appimage
    ].freeze

    module_function

    def install!
      Installer::Utils.log("Installing tools...")
      ALL.each { |name| send(name) }
    end

    def install_pyenv
      return if Installer::Utils.command?("pyenv")

      Installer::Utils.log("Installing pyenv...")
      Installer::Utils.run!("bash", "-c", "curl -fsSL https://pyenv.run | bash")
    end

    # brew and pacman ship gum; apt has neither gum nor go
    def install_gum
      return if Installer::Utils.command?("gum")

      unless Installer::Utils.command?("go")
        Installer::Utils.warn("gum skipped: go is not installed")
        return
      end

      Installer::Utils.log("Installing gum...")
      Installer::Utils.run!("go", "install", "github.com/charmbracelet/gum@latest")
    end

    def install_zsh_plugins
      plugins_dir = File.join(
        ENV.fetch("XDG_DATA_HOME", File.join(ENV.fetch("HOME"), ".local/share")),
        "zsh", "plugins"
      )
      FileUtils.mkdir_p(plugins_dir)

      plugins = {
        "ohmyzsh" => "https://github.com/ohmyzsh/ohmyzsh.git",
        "zsh-autosuggestions" => "https://github.com/zsh-users/zsh-autosuggestions.git",
        "zsh-completions" => "https://github.com/zsh-users/zsh-completions.git",
        "evalcache" => "https://github.com/mroth/evalcache.git",
        "fast-syntax-highlighting" => "https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
      }

      plugins.each do |name, url|
        target = File.join(plugins_dir, name)
        if File.exist?(target)
          Installer::Utils.log("Updating #{name}...")
          Installer::Utils.run!("git", "-C", target, "pull", "--quiet")
        else
          Installer::Utils.log("Cloning #{name}...")
          Installer::Utils.run!("git", "clone", "--depth", "1", url, target)
        end
      end

      return unless Installer::Utils.command?("kubectl")

      completion_dir = File.join(plugins_dir, "kubectl")
      FileUtils.mkdir_p(completion_dir)
      completion_file = File.join(completion_dir, "_kubectl")
      Installer::Utils.try_run("bash", "-c", "kubectl completion zsh > #{Shellwords.escape(completion_file)}")
    end

    def install_atuin
      return if Installer::Utils.command?("atuin")

      Installer::Utils.log("Installing Atuin...")
      Installer::Utils.try_run("bash", "-c", "curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive")
    end

    def install_fzf_latest
      return if fzf_version_ok?

      Installer::Utils.log("Installing latest fzf from GitHub...")

      latest = `curl -s https://api.github.com/repos/junegunn/fzf/releases/latest`.strip
      version = latest.match(/"tag_name":\s*"([^"]+)"/)&.[](1)
      raise Installer::CommandFailed, "Could not determine latest fzf version" unless version

      platform = RUBY_PLATFORM.include?("darwin") ? "darwin" : "linux"
      arch = RUBY_PLATFORM.include?("arm") || RUBY_PLATFORM.include?("aarch64") ? "arm64" : "amd64"

      tarball = "fzf-#{version}-#{platform}_#{arch}.tar.gz"
      url = "https://github.com/junegunn/fzf/releases/download/#{version}/#{tarball}"

      Dir.mktmpdir do |tmpdir|
        Installer::Utils.run!("bash", "-c", "curl -fsSL #{Shellwords.escape(url)} | tar xz -C #{Shellwords.escape(tmpdir)}")
        Installer::Utils.sudo!("install", "-m", "755", File.join(tmpdir, "fzf"), "/usr/local/bin/fzf")
      end
    end

    def fzf_version_ok?
      return false unless Installer::Utils.command?("fzf")

      version = `fzf --version`.strip.split.first
      return false unless version

      Gem::Version.new(version) >= Gem::Version.new(FZF_MIN_VERSION)
    rescue StandardError
      false
    end

    def install_delta_deb
      return if Installer::Utils.command?("delta")
      return unless Installer::Utils.command?("dpkg")

      Installer::Utils.log("Installing git-delta from GitHub...")

      latest = `curl -s https://api.github.com/repos/dandavison/delta/releases/latest`.strip
      version = latest.match(/"tag_name":\s*"([^"]+)"/)&.[](1)&.delete_prefix("v")
      raise Installer::CommandFailed, "Could not determine latest git-delta version" unless version

      deb = "git-delta_#{version}_amd64.deb"
      url = "https://github.com/dandavison/delta/releases/download/#{version}/#{deb}"

      Dir.mktmpdir do |tmpdir|
        deb_path = File.join(tmpdir, deb)
        Installer::Utils.run!("curl", "-fsSL", "-o", deb_path, url)
        Installer::Utils.sudo!("dpkg", "-i", deb_path)
      end
    end

    def install_zoxide_curl
      return if Installer::Utils.command?("zoxide")

      Installer::Utils.log("Installing zoxide...")
      Installer::Utils.run!("bash", "-c", "curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash")
    end

    def install_starship_curl
      return if Installer::Utils.command?("starship")

      Installer::Utils.log("Installing starship...")
      Installer::Utils.run!("bash", "-c", "curl -sS https://starship.rs/install.sh | sh -s -- -y")
    end

    def install_herdr
      return if Installer::Utils.command?("herdr")

      Installer::Utils.log("Installing herdr...")
      Installer::Utils.run!("bash", "-c", "curl -fsSL https://herdr.dev/install.sh | sh")
    end

    # macOS gets bb from the `bb` cask
    def install_bb_appimage
      Installer::BbApp.install_appimage!
    end
  end
end
