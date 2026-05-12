# frozen_string_literal: true

require "json"

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
      ENV["GIT_EMAIL"] ||= `git config --global user.email 2>/dev/null`.strip
      ENV["GIT_NAME"] ||= `git config --global user.name 2>/dev/null`.strip
      ENV["GIT_SIGNING_KEY"] ||= `git config --global user.signingkey 2>/dev/null`.strip
    end

    def setup_go_task_symlink
      return unless Installer::Utils.command?("go-task") && !Installer::Utils.command?("task")

      go_task_path = `command -v go-task`.strip
      return if go_task_path.empty?

      Installer::Utils.sudo("ln", "-sf", go_task_path, "/usr/local/bin/task")
    end

    def setup_gpg_key
      return if ENV["GIT_EMAIL"].to_s.empty?
      return unless ENV["GIT_SIGNING_KEY"].to_s.empty?

      Installer::Utils.log("GPG key setup skipped (to be implemented in Plan 2)")
    end

    def stow_dotfiles
      return unless Installer::Utils.command?("stow")

      Installer::Utils.log("Stowing dotfiles...")
      Installer::Utils.run("stow", "home", "-d", SHELL_DIR, "-t", HOME, "--adopt")
    end

    def bootstrap_pi_extensions
      ext_pattern = File.join(HOME, ".pi", "agent", "extensions", "*", "package.json")
      Dir.glob(ext_pattern).each do |package_json|
        ext_dir = File.dirname(package_json)
        next if File.exist?(File.join(ext_dir, "node_modules"))

        json = JSON.parse(File.read(package_json))
        next unless json["dependencies"] || json["devDependencies"]

        Installer::Utils.log("Installing dependencies for #{File.basename(ext_dir)}...")
        Installer::Utils.run("npm", "install", chdir: ext_dir)
      end
    end

    def bootstrap_skill_notes
      script = File.join(SHELL_DIR, "src", "scripts", "bootstrap-skill-notes.sh")
      return unless File.exist?(script)

      Installer::Utils.log("Bootstrapping skill notes...")
      system("bash", script)
    end

    def set_default_shell
      return if ENV["SHELL"] && ENV["SHELL"].end_with?("zsh")

      zsh_path = `command -v zsh`.strip
      return if zsh_path.empty?

      unless File.readlines("/etc/shells").any? { |line| line.strip == zsh_path }
        system("echo '#{zsh_path}' | sudo tee -a /etc/shells")
      end

      Installer::Utils.sudo("chsh", "-s", zsh_path, ENV["USER"])
    end

    def generate_configs
      Installer::Utils.log("Generating configuration files...")

      zshrc_script = File.join(SHELL_DIR, "src", "generate_zshrc.rb")
      system("ruby", zshrc_script) if File.exist?(zshrc_script)

      gitconfig_template = File.join(SHELL_DIR, "src", "templates", ".gitconfig.erb")
      gitconfig_output = File.join(SHELL_DIR, "home", ".gitconfig")
      if File.exist?(gitconfig_template)
        system("ruby", File.join(SHELL_DIR, "src", "generate_tempate.rb"),
               "-i", gitconfig_template, "-o", gitconfig_output)
      end

      ghostty_script = File.join(SHELL_DIR, "src", "generate_ghostty_config.rb")
      system("ruby", ghostty_script) if File.exist?(ghostty_script)
    end
  end
end
