# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "shellwords"
require "socket"
require "tempfile"

module Installer
  module PostSetup
    SHELL_DIR = File.expand_path("../..", __dir__)
    HOME = ENV["HOME"]

    module_function

    def load_env_file
      env_file = File.join(SHELL_DIR, ".env")
      return unless File.exist?(env_file)

      File.readlines(env_file).each do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        if line =~ /^(\w+)=(.*)$/
          key = Regexp.last_match(1)
          value = Regexp.last_match(2).delete('"').delete("'")
          ENV[key] = value
        end
      end
    end

    def load_git_config_fallbacks
      ENV["GIT_EMAIL"] = `git config --global user.email 2>/dev/null`.strip if ENV["GIT_EMAIL"].to_s.strip.empty?
      ENV["GIT_NAME"] = `git config --global user.name 2>/dev/null`.strip if ENV["GIT_NAME"].to_s.strip.empty?
      if ENV["GIT_SIGNING_KEY"].to_s.strip.empty?
        ENV["GIT_SIGNING_KEY"] = `git config --global user.signingkey 2>/dev/null`.strip
      end
    end

    def setup_go_task_symlink!
      return unless Installer::Utils.command?("go-task") && !Installer::Utils.command?("task")

      go_task_path = `command -v go-task`.strip
      return if go_task_path.empty?

      Installer::Utils.sudo!("ln", "-sf", go_task_path, "/usr/local/bin/task")
    end

    def setup_gpg_key
      email = ENV["GIT_EMAIL"].to_s.strip
      if email.empty?
        Installer::Utils.warn("GPG key setup skipped: GIT_EMAIL is not set")
        return
      end

      ensure_gpg_home_permissions!

      signing_key = ENV["GIT_SIGNING_KEY"].to_s.strip
      unless signing_key.empty? || signing_key_available?(signing_key)
        Installer::Utils.warn("Configured Git signing key #{short_key(signing_key)} is not available locally; finding or creating a usable key")
        signing_key = ""
      end

      signing_key = ensure_gpg_signing_key(email) if signing_key.empty?
      return if signing_key.empty?

      ENV["GIT_SIGNING_KEY"] = signing_key
      configure_git_signing(signing_key)
      upload_gpg_key_to_github(signing_key)
    end

    def stow_dotfiles!
      raise Installer::CommandFailed, "stow is required to install dotfiles" unless Installer::Utils.command?("stow")

      Installer::Utils.log("Stowing dotfiles...")
      Installer::Utils.run!("stow", "home", "-d", SHELL_DIR, "-t", HOME, "--adopt")
    end

    def bootstrap_pi_extensions!
      ext_pattern = File.join(HOME, ".pi", "agent", "extensions", "*", "package.json")
      Dir.glob(ext_pattern).each do |package_json|
        ext_dir = File.dirname(package_json)
        next if File.exist?(File.join(ext_dir, "node_modules"))

        json = JSON.parse(File.read(package_json))
        next unless json["dependencies"] || json["devDependencies"]

        Installer::Utils.log("Installing dependencies for #{File.basename(ext_dir)}...")
        Installer::Utils.run!("npm", "install", chdir: ext_dir)
      end
    end

    def bootstrap_skill_notes!
      script = File.join(SHELL_DIR, "src", "scripts", "bootstrap-skill-notes.sh")
      return unless File.exist?(script)

      Installer::Utils.log("Bootstrapping skill notes...")
      Installer::Utils.run!("bash", script)
    end

    def set_default_shell!
      return if ENV["SHELL"] && ENV["SHELL"].end_with?("zsh")

      zsh_path = `command -v zsh`.strip
      return if zsh_path.empty?

      unless File.readlines("/etc/shells").any? { |line| line.strip == zsh_path }
        Installer::Utils.sudo!("sh", "-c", "printf '%s\\n' #{Shellwords.escape(zsh_path)} >> /etc/shells")
      end

      Installer::Utils.sudo!("chsh", "-s", zsh_path, ENV.fetch("USER"))
      Installer::Utils.reboot_required!("Default shell change requires a new login session")
    end

    def generate_configs!
      Installer::Utils.log("Generating configuration files...")

      zshrc_script = File.join(SHELL_DIR, "src", "generate_zshrc.rb")
      Installer::Utils.run!("ruby", zshrc_script) if File.exist?(zshrc_script)

      generate_git_config

      ghostty_script = File.join(SHELL_DIR, "src", "generate_ghostty_config.rb")
      Installer::Utils.run!("ruby", ghostty_script) if File.exist?(ghostty_script)
    end

    def generate_git_config
      gitconfig_template = File.join(SHELL_DIR, "src", "templates", ".gitconfig.erb")
      gitconfig_output = File.join(SHELL_DIR, "home", ".gitconfig")
      return unless File.exist?(gitconfig_template)

      Installer::Utils.run!("ruby", File.join(SHELL_DIR, "src", "generate_tempate.rb"),
                            "-i", gitconfig_template, "-o", gitconfig_output)
    end

    def ensure_gpg_signing_key(email)
      unless Installer::Utils.command?("gpg")
        Installer::Utils.warn("GPG key setup skipped: gpg is not installed")
        return ""
      end

      ensure_gpg_home_permissions!

      signing_key = find_gpg_signing_key(email)
      return signing_key unless signing_key.empty?

      user_id = gpg_user_id(email)
      Installer::Utils.log("Generating RSA4096 GPG signing key for #{user_id}...")
      Installer::Utils.run!("gpg", "--batch", "--pinentry-mode", "loopback",
                             "--passphrase", "", "--quick-generate-key",
                             user_id, "rsa4096", "sign", "0")

      signing_key = find_gpg_signing_key(email)
      Installer::Utils.warn("GPG key generation did not produce a signing key for #{email}") if signing_key.empty?
      signing_key
    end

    def find_gpg_signing_key(email)
      stdout, _stderr, status = capture_command("gpg", "--batch", "--with-colons",
                                                "--list-secret-keys", email)
      return "" unless status.success?

      extract_signing_fingerprint(stdout)
    end

    def signing_key_available?(signing_key)
      ensure_gpg_home_permissions!

      _stdout, _stderr, status = capture_command("gpg", "--batch", "--list-secret-keys", signing_key)
      status.success?
    end

    def ensure_gpg_home_permissions!
      [
        gpg_home,
        File.join(gpg_home, "private-keys-v1.d"),
        File.join(gpg_home, "openpgp-revocs.d")
      ].each do |path|
        next unless File.directory?(path)

        FileUtils.chmod(0o700, path)
      end
    end

    def gpg_home
      configured_home = ENV["GNUPGHOME"].to_s.strip
      return File.expand_path(configured_home) unless configured_home.empty?

      File.expand_path("~/.gnupg")
    end

    def extract_signing_fingerprint(gpg_colon_output)
      signing_key = false

      gpg_colon_output.each_line do |line|
        fields = line.chomp.split(":")
        case fields[0]
        when "sec", "ssb"
          signing_key = fields[11].to_s.downcase.include?("s")
        when "fpr"
          return fields[9].to_s if signing_key && !fields[9].to_s.empty?
        end
      end

      ""
    end

    def gpg_user_id(email)
      name = ENV["GIT_NAME"].to_s.strip
      return email if name.empty?

      "#{name} <#{email}>"
    end

    def configure_git_signing(signing_key)
      return unless Installer::Utils.command?("git")

      Installer::Utils.run!("git", "config", "--global", "user.signingkey", signing_key)
      Installer::Utils.run!("git", "config", "--global", "commit.gpgsign", "true")
    end

    def upload_gpg_key_to_github(signing_key)
      return unless Installer::Utils.command?("gh")

      unless Installer::Utils.command?("gpg")
        Installer::Utils.warn("GitHub GPG key upload skipped: gpg is not installed")
        return
      end

      _stdout, _stderr, auth_status = capture_command("gh", "auth", "status", "--hostname", "github.com")
      unless auth_status.success?
        Installer::Utils.warn("GitHub GPG key upload skipped: run `gh auth login` first")
        return
      end

      armored_key, stderr, export_status = capture_command("gpg", "--armor", "--export", signing_key)
      unless export_status.success? && !armored_key.empty?
        Installer::Utils.warn("GitHub GPG key upload skipped: could not export public key #{short_key(signing_key)}#{format_error(stderr)}")
        return
      end

      if github_has_gpg_key?(signing_key, armored_key)
        Installer::Utils.log("GitHub already has GPG key #{short_key(signing_key)}")
        return
      end

      Tempfile.create(["github-gpg-key", ".asc"]) do |file|
        file.write(armored_key)
        file.flush

        title = "Git signing key for #{Socket.gethostname}"
        _add_stdout, add_stderr, add_status = capture_command("gh", "gpg-key", "add", file.path, "--title", title)
        if add_status.success?
          Installer::Utils.success("Uploaded GPG signing key #{short_key(signing_key)} to GitHub")
        else
          Installer::Utils.warn("GitHub GPG key upload failed for #{short_key(signing_key)}#{format_error(add_stderr)}")
        end
      end
    end

    def github_has_gpg_key?(signing_key, armored_key)
      stdout, _stderr, status = capture_command("gh", "api", "user/gpg_keys")
      return false unless status.success?

      normalized_key = normalize_armored_key(armored_key)
      normalized_signing_key = signing_key.upcase.delete(" ")

      JSON.parse(stdout).any? do |key|
        raw_key = normalize_armored_key(key["raw_key"].to_s)
        key_id = key["key_id"].to_s.upcase.delete(" ")

        (!raw_key.empty? && raw_key == normalized_key) ||
          (!key_id.empty? && normalized_signing_key.end_with?(key_id))
      end
    rescue JSON::ParserError
      false
    end

    def normalize_armored_key(key)
      key.lines.map(&:strip).reject(&:empty?).join("\n")
    end

    def short_key(signing_key)
      key = signing_key.to_s.delete(" ")
      return key if key.length <= 16

      key[-16, 16]
    end

    def format_error(message)
      message = message.to_s.strip
      return "" if message.empty?

      ": #{message}"
    end

    def capture_command(*cmd)
      Open3.capture3(*cmd)
    end
  end
end
