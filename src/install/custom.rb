# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Installer
  module Custom
    FZF_MIN_VERSION = "0.59.0"

    module_function

    def install_docker_post
      return unless Installer::Utils.command?("systemctl")

      Installer::Utils.sudo("systemctl", "enable", "--now", "docker")
      return if Installer::Utils.root?

      Installer::Utils.sudo("usermod", "-aG", "docker", ENV["USER"])
    end

    def install_pyenv
      return if Installer::Utils.command?("pyenv")

      Installer::Utils.log("Installing pyenv...")
      system("bash", "-c", "curl -fsSL https://pyenv.run | bash")
    end

    def install_gum
      return if Installer::Utils.command?("gum")

      Installer::Utils.log("Installing gum...")
      Installer::Utils.run("go", "install", "github.com/charmbracelet/gum@latest")
    end

    def install_zsh_plugins
      plugins_dir = File.join(
        ENV.fetch("XDG_DATA_HOME", File.join(ENV["HOME"], ".local/share")),
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
          Installer::Utils.run("git", "-C", target, "pull", "--quiet")
        else
          Installer::Utils.log("Cloning #{name}...")
          Installer::Utils.run("git", "clone", "--depth", "1", url, target)
        end
      end

      return unless Installer::Utils.command?("kubectl")

      completion_dir = File.join(plugins_dir, "kubectl")
      FileUtils.mkdir_p(completion_dir)
      completion_file = File.join(completion_dir, "_kubectl")
      system("kubectl completion zsh > #{completion_file}")
    end

    def install_fzf_latest
      return if fzf_version_ok?

      Installer::Utils.log("Installing latest fzf from GitHub...")

      latest = `curl -s https://api.github.com/repos/junegunn/fzf/releases/latest`.strip
      version = latest.match(/"tag_name":\s*"([^"]+)"/)&.[](1)
      return unless version

      platform = RUBY_PLATFORM.include?("darwin") ? "darwin" : "linux"
      arch = RUBY_PLATFORM.include?("arm") || RUBY_PLATFORM.include?("aarch64") ? "arm64" : "amd64"

      tarball = "fzf-#{version}-#{platform}_#{arch}.tar.gz"
      url = "https://github.com/junegunn/fzf/releases/download/#{version}/#{tarball}"

      Dir.mktmpdir do |tmpdir|
        system("curl -sL #{url} | tar xz -C #{tmpdir}")
        Installer::Utils.sudo("install", "-m", "755", File.join(tmpdir, "fzf"), "/usr/local/bin/fzf")
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
      return unless version

      deb = "git-delta_#{version}_amd64.deb"
      url = "https://github.com/dandavison/delta/releases/download/#{version}/#{deb}"

      Dir.mktmpdir do |tmpdir|
        deb_path = File.join(tmpdir, deb)
        system("curl -sL -o #{deb_path} #{url}")
        Installer::Utils.sudo("dpkg", "-i", deb_path)
      end
    end

    def install_zoxide_curl
      return if Installer::Utils.command?("zoxide")

      Installer::Utils.log("Installing zoxide...")
      system("bash", "-c", "curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash")
    end

    def install_starship_curl
      return if Installer::Utils.command?("starship")

      Installer::Utils.log("Installing starship...")
      system("bash", "-c", "curl -sS https://starship.rs/install.sh | sh -s -- -y")
    end

    def install_fnm_curl
      return if Installer::Utils.command?("fnm")

      Installer::Utils.log("Installing fnm...")
      system("bash", "-c", "curl -fsSL https://fnm.vercel.app/install | bash")
    end

    def install_nerd_fonts_brew
      return unless Installer::Utils.command?("brew")

      Installer::Utils.log("Installing nerd fonts...")
      fonts = `brew search nerd-font`.lines.map(&:strip).select { |f| f.include?("nerd-font") }
      fonts.each do |font|
        Installer::Utils.run("brew", "install", "--cask", font)
      end
    end

    def install_nvm_curl
      return if Installer::Utils.command?("nvm") || Installer::Utils.command?("fnm")

      Installer::Utils.log("Installing nvm...")
      system("bash", "-c", "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash")
    end
  end
end
