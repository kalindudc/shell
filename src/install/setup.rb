# frozen_string_literal: true

require "etc"
require "fileutils"
require "json"
require "open3"
require "shellwords"
require "socket"
require "tempfile"
require_relative "errors"

module Installer
  # Sets up installed tools: docker, the GPG signing key, herdr plugins, pi extension
  # dependencies, skill notes and the default shell.
  module Setup
    SHELL_DIR = File.expand_path("../..", __dir__)

    module_function

    def run!
      install_docker_post
      setup_go_task_symlink!
      setup_gpg_key
      install_herdr_plus
      install_herdr_automatic_rename
      install_herdr_pi_integration
      install_extension_dependencies!
      bootstrap_skill_notes!
      set_default_shell!
    end

    def install_docker_post
      return unless Installer::Utils.command?("systemctl")

      Installer::Utils.sudo!("systemctl", "enable", "--now", "docker")
      return if Installer::Utils.root?

      # Checking membership first keeps a rerun after the new login from asking again.
      unless docker_group_member?
        Installer::Utils.sudo!("usermod", "-aG", "docker", ENV.fetch("USER"))
        Installer::Utils.login_required("Docker group membership requires a new login session")
      end
    end

    def docker_group_member?
      Etc.getgrnam("docker").mem.include?(ENV.fetch("USER"))
    rescue ArgumentError
      # The docker group does not exist yet, so the user cannot be a member.
      false
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

    def install_herdr_plus
      return unless Installer::Utils.command?("herdr")
      return if `herdr plugin list 2>/dev/null`.include?("cloudmanic.herdr-plus")

      Installer::Utils.log("Installing herdr-plus plugin...")
      Installer::Utils.run!("herdr", "plugin", "install", "cloudmanic/herdr-plus", "--yes")
    end

    def install_herdr_automatic_rename
      return unless Installer::Utils.command?("herdr")
      return if `herdr plugin list 2>/dev/null`.include?("herdr-automatic-rename")

      Installer::Utils.log("Installing herdr-automatic-rename plugin...")
      Installer::Utils.run!("herdr", "plugin", "install", "qu8n/herdr-automatic-rename", "--yes")
    end

    # Reports pi agent state (working, idle, waiting) to the herdr sidebar. herdr owns the
    # file it writes (~/.pi/agent/extensions/herdr-agent-state.ts) and overwrites it on reinstall,
    # so an outdated integration is reinstalled too.
    def install_herdr_pi_integration
      return unless Installer::Utils.command?("herdr")
      return if herdr_integration_status.lines.any? { |line| line.start_with?("pi: current") }

      Installer::Utils.log("Installing herdr pi integration...")
      Installer::Utils.run!("herdr", "integration", "install", "pi")
    end

    def herdr_integration_status
      `herdr integration status 2>/dev/null`
    end

    # The repo copy first, so extensions work before stow links them, then any in $HOME.
    def install_extension_dependencies!
      unless Installer::Utils.command?("npm")
        Installer::Utils.warn("pi extension dependencies skipped: npm is not installed")
        return
      end

      [File.join(SHELL_DIR, "home"), Dir.home].each do |root|
        Dir.glob(File.join(root, ".pi", "agent", "extensions", "*", "package.json")).each do |package_json|
          ext_dir = File.dirname(package_json)
          next if File.exist?(File.join(ext_dir, "node_modules"))

          json = JSON.parse(File.read(package_json))
          next unless json["dependencies"] || json["devDependencies"]

          Installer::Utils.log("Installing dependencies for #{File.basename(ext_dir)}...")
          Installer::Utils.run!("npm", "install", chdir: ext_dir)
        end
      end
    end

    # The script exits 0 for a skills directory that does not exist yet.
    def bootstrap_skill_notes!
      script = File.join(SHELL_DIR, "src", "scripts", "bootstrap-skill-notes.sh")
      Installer::Utils.log("Bootstrapping skill notes...")
      [File.join(SHELL_DIR, "home", ".agents", "skills"), File.join(Dir.home, ".agents", "skills")].each do |dir|
        Installer::Utils.run!("bash", script, dir)
      end
    end

    def set_default_shell!
      return if ENV["SHELL"] && ENV["SHELL"].end_with?("zsh")

      zsh_path = `command -v zsh`.strip
      return if zsh_path.empty?

      unless File.readlines("/etc/shells").any? { |line| line.strip == zsh_path }
        Installer::Utils.sudo!("sh", "-c", "printf '%s\\n' #{Shellwords.escape(zsh_path)} >> /etc/shells")
      end

      Installer::Utils.sudo!("chsh", "-s", zsh_path, ENV.fetch("USER"))
      Installer::Utils.login_required("Default shell change requires a new login session")
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
