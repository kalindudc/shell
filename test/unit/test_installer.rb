#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'yaml'
require 'fileutils'
require 'open3'
require 'tempfile'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/cli'
require_relative '../../src/install/platform'
require_relative '../../src/install/packages'
require_relative '../../src/install/tools'
require_relative '../../src/install/setup'

class TestInstaller < Minitest::Test
  def setup
    @shell_dir = File.expand_path('../..', __dir__)
    @packages_file = File.join(@shell_dir, 'packages.yml')
  end

  # file_structure

  def test_packages_yml_exists
    assert File.exist?(@packages_file), "packages.yml should exist"
  end

  def test_packages_yml_is_valid_yaml
    content = YAML.load_file(@packages_file)
    refute_nil content, "packages.yml should parse as YAML"
    assert content.is_a?(Hash), "packages.yml should be a Hash"
  end

  def test_packages_yml_has_expected_backends
    content = YAML.load_file(@packages_file)
    expected_backends = %w[pacman yay apt brew brew_cask snap flatpak npm pi pipx]

    expected_backends.each do |backend|
      assert content.key?(backend), "packages.yml should have #{backend} key"
    end
  end

  def test_packages_yml_pacman_packages
    content = YAML.load_file(@packages_file)
    packages = content['pacman']

    assert packages.is_a?(Array), "pacman packages should be an array"
    assert_includes packages, 'git', "pacman should include git"
    assert_includes packages, 'curl', "pacman should include curl"
    assert_includes packages, 'ruby', "pacman should include ruby"
    assert_includes packages, 'zsh', "pacman should include zsh"
    assert_includes packages, 'atuin', "pacman should include atuin"
  end

  def test_packages_yml_apt_packages
    content = YAML.load_file(@packages_file)
    packages = content['apt']

    assert packages.is_a?(Array), "apt packages should be an array"
    assert_includes packages, 'git', "apt should include git"
    assert_includes packages, 'curl', "apt should include curl"
    assert_includes packages, 'ruby', "apt should include ruby"
    assert_includes packages, 'fd-find', "apt should include fd-find (mapped name)"
  end

  def test_packages_yml_brew_packages
    content = YAML.load_file(@packages_file)
    packages = content['brew']

    assert packages.is_a?(Array), "brew packages should be an array"
    assert_includes packages, 'git', "brew should include git"
    assert_includes packages, 'starship', "brew should include starship"
    assert_includes packages, 'atuin', "brew should include atuin"
    assert_includes packages, 'herdr', "brew should include herdr"
  end

  def test_packages_yml_snap_packages
    content = YAML.load_file(@packages_file)
    packages = content['snap']

    assert packages.is_a?(Array), "snap packages should be an array"

    # Check for hash format with classic flag
    code_entry = packages.find { |p| p.is_a?(Hash) && p['name'] == 'code' }
    refute_nil code_entry, "snap should include code with classic flag"
    assert_equal true, code_entry['classic'], "code should have classic: true"
  end

  def test_packages_yml_npm_packages
    content = YAML.load_file(@packages_file)
    packages = content['npm']

    assert packages.is_a?(Array), "npm packages should be an array"
    assert_includes packages, '@earendil-works/pi-coding-agent', "npm should include pi-coding-agent"
  end

  def test_packages_yml_pi_packages
    content = YAML.load_file(@packages_file)
    packages = content['pi']

    assert packages.is_a?(Array), "pi packages should be an array"
    assert_includes packages, 'https://github.com/kalindudc/minions', "pi should include pi-minions"
    assert_includes packages, 'https://github.com/kalindudc/quests', "pi should include pi-quests"
  end

  def test_tools_lists_only_tools_methods
    Installer::Tools::ALL.each do |name|
      assert_respond_to Installer::Tools, name
    end
    assert_includes Installer::Tools::ALL, :install_herdr
    assert_includes Installer::Tools::ALL, :install_bb_appimage
    refute_includes Installer::Tools::ALL, :install_nvm_curl
    refute_includes Installer::Tools::ALL, :install_nerd_fonts_brew
  end

  def test_herdr_pi_integration_installs_unless_current
    statuses = {
      'pi: not installed (/h/.pi/agent/extensions/herdr-agent-state.ts)' => true,
      'pi: outdated (v8) (/h/.pi/agent/extensions/herdr-agent-state.ts)' => true,
      'pi: current (v9) (/h/.pi/agent/extensions/herdr-agent-state.ts)' => false
    }

    statuses.each do |pi_line, expect_install|
      calls = []
      status = "codex: current (v8) (/h/.codex/herdr-agent-state.sh)\n#{pi_line}\n"

      Installer::Utils.stub(:command?, ->(name) { name == 'herdr' }) do
        Installer::Setup.stub(:herdr_integration_status, status) do
          Installer::Utils.stub(:run!, ->(*cmd) { calls << cmd }) do
            capture_io { Installer::Setup.install_herdr_pi_integration }
          end
        end
      end

      expected = expect_install ? [%w[herdr integration install pi]] : []
      assert_equal expected, calls, "for status line: #{pi_line}"
    end
  end

  def test_herdr_pi_integration_skips_without_herdr
    Installer::Utils.stub(:command?, false) do
      Installer::Utils.stub(:run!, ->(*cmd) { flunk "must not run #{cmd.join(' ')}" }) do
        Installer::Setup.install_herdr_pi_integration
      end
    end
  end

  # docker

  def test_install_docker_post_skips_usermod_when_already_member
    calls = []
    Installer::Utils.stub(:command?, ->(name) { name == 'systemctl' }) do
      Installer::Utils.stub(:root?, false) do
        Installer::Setup.stub(:docker_group_member?, true) do
          Installer::Utils.stub(:sudo!, ->(*cmd) { calls << cmd }) do
            Installer::Utils.stub(:login_required, ->(_reason) { flunk 'must not require a new login' }) do
              Installer::Setup.install_docker_post
            end
          end
        end
      end
    end

    assert_equal [%w[systemctl enable --now docker]], calls
  end

  def test_install_docker_post_requires_new_login_when_not_member
    calls = []
    login_calls = []
    Installer::Utils.stub(:command?, ->(name) { name == 'systemctl' }) do
      Installer::Utils.stub(:root?, false) do
        Installer::Setup.stub(:docker_group_member?, false) do
          Installer::Utils.stub(:sudo!, ->(*cmd) { calls << cmd }) do
            Installer::Utils.stub(:login_required, ->(reason) { login_calls << reason }) do
              Installer::Setup.install_docker_post
            end
          end
        end
      end
    end

    assert_equal [%w[systemctl enable --now docker], ['usermod', '-aG', 'docker', ENV['USER']]], calls
    assert_equal ['Docker group membership requires a new login session'], login_calls
  end

  def test_docker_group_member_returns_false_when_group_missing
    Etc.stub(:getgrnam, ->(_name) { raise ArgumentError, 'not found' }) do
      assert_equal false, Installer::Setup.docker_group_member?
    end
  end

  # pi packages

  def test_install_pi_installs_only_missing_packages
    calls = []
    list_output = <<~LIST
      User packages:
        https://github.com/kalindudc/minions
          /h/.pi/agent/git/github.com/kalindudc/minions
    LIST
    success = Struct.new(:success?).new(true)
    sources = %w[https://github.com/kalindudc/minions https://github.com/kalindudc/quests]

    Installer::Utils.stub(:command?, ->(name) { name == 'pi' }) do
      Open3.stub(:capture3, [list_output, '', success]) do
        Installer::Utils.stub(:run!, ->(*cmd) { calls << cmd }) do
          capture_io { Installer::Packages.install('pi', sources) }
        end
      end
    end

    assert_equal [%w[pi install https://github.com/kalindudc/quests --no-approve]], calls
  end

  def test_install_pi_skips_without_pi
    Installer::Utils.stub(:command?, false) do
      Installer::Utils.stub(:run!, ->(*cmd) { flunk "must not run #{cmd.join(' ')}" }) do
        out, = capture_io { Installer::Packages.install('pi', ['https://github.com/kalindudc/quests']) }
        assert_includes out, 'skipping pi packages'
      end
    end
  end

  def test_install_pi_fails_when_pi_list_fails
    failure = Struct.new(:success?).new(false)

    Installer::Utils.stub(:command?, true) do
      Open3.stub(:capture3, ['', 'boom', failure]) do
        error = assert_raises(Installer::CommandFailed) do
          capture_io { Installer::Packages.install('pi', ['https://github.com/kalindudc/quests']) }
        end
        assert_includes error.message, 'pi list'
      end
    end
  end

  def test_atuin_config_tracks_only_non_secret_settings
    config_file = File.join(@shell_dir, 'home', '.config', 'atuin', 'config.toml')

    assert File.exist?(config_file), "Atuin config should be tracked"

    config = File.read(config_file)
    assert_includes config, 'secrets_filter = true', "Atuin config should filter secrets"
    refute_includes config, 'key_path', "Atuin config should not track key_path"
    refute_includes config, 'session_path', "Atuin config should not track session_path"
    refute_includes config, 'db_path', "Atuin config should not track db_path"
  end

  def test_install_rb_exists
    install_rb = File.join(@shell_dir, 'src', 'install.rb')
    assert File.exist?(install_rb), "src/install.rb should exist"
  end

  def test_install_rb_syntax
    install_rb = File.join(@shell_dir, 'src', 'install.rb')
    result = system("ruby -c #{install_rb} > /dev/null 2>&1")
    assert result, "src/install.rb should have valid Ruby syntax"
  end

  def test_extract_signing_fingerprint_from_primary_secret_key
    fingerprint = '1234567890ABCDEF1234567890ABCDEF12345678'
    gpg_output = <<~GPG
      sec:u:4096:1:90ABCDEF12345678:1720000000:0:::::scSC
      fpr:::::::::#{fingerprint}
    GPG

    assert_equal fingerprint, Installer::Setup.extract_signing_fingerprint(gpg_output)
  end

  def test_extract_signing_fingerprint_from_signing_subkey
    fingerprint = 'ABCDEF1234567890ABCDEF1234567890ABCDEF12'
    gpg_output = <<~GPG
      sec:u:4096:1:1111111111111111:1720000000:0:::::cC
      fpr:::::::::1111111111111111111111111111111111111111
      ssb:u:4096:1:90ABCDEF12345678:1720000000:0:::::s
      fpr:::::::::#{fingerprint}
    GPG

    assert_equal fingerprint, Installer::Setup.extract_signing_fingerprint(gpg_output)
  end

  def test_gpg_user_id_uses_git_name_when_present
    old_name = ENV['GIT_NAME']
    ENV['GIT_NAME'] = 'Example User'

    assert_equal 'Example User <user@example.com>', Installer::Setup.gpg_user_id('user@example.com')
  ensure
    ENV['GIT_NAME'] = old_name
  end

  def test_signing_key_available_requires_secret_key
    success = Struct.new(:success?).new(true)
    failure = Struct.new(:success?).new(false)

    Installer::Setup.stub(:ensure_gpg_home_permissions!, nil) do
      Installer::Setup.stub(:capture_command, ['', '', success]) do
        assert Installer::Setup.signing_key_available?('ABC123')
      end

      Installer::Setup.stub(:capture_command, ['', 'No secret key', failure]) do
        refute Installer::Setup.signing_key_available?('ABC123')
      end
    end
  end

  def test_ensure_gpg_home_permissions_repairs_private_key_directories
    Dir.mktmpdir do |dir|
      private_dir = File.join(dir, 'private-keys-v1.d')
      revocation_dir = File.join(dir, 'openpgp-revocs.d')
      FileUtils.mkdir_p(private_dir)
      FileUtils.mkdir_p(revocation_dir)
      FileUtils.chmod(0o600, private_dir)
      FileUtils.chmod(0o600, revocation_dir)

      Installer::Setup.stub(:gpg_home, dir) do
        Installer::Setup.ensure_gpg_home_permissions!
      end

      assert_equal 0o700, File.stat(dir).mode & 0o777
      assert_equal 0o700, File.stat(private_dir).mode & 0o777
      assert_equal 0o700, File.stat(revocation_dir).mode & 0o777
    end
  end

  def test_setup_gpg_key_ignores_stale_configured_key
    old_email = ENV['GIT_EMAIL']
    old_name = ENV['GIT_NAME']
    old_signing_key = ENV['GIT_SIGNING_KEY']
    ENV['GIT_EMAIL'] = 'user@example.com'
    ENV['GIT_NAME'] = 'Example User'
    ENV['GIT_SIGNING_KEY'] = 'STALEKEY'
    configured = []

    Installer::Utils.stub(:command?, true) do
      Installer::Setup.stub(:signing_key_available?, ->(key) { key == 'VALIDKEY' }) do
        Installer::Setup.stub(:find_gpg_signing_key, 'VALIDKEY') do
          Installer::Setup.stub(:configure_git_signing, ->(key) { configured << key }) do
            Installer::Setup.stub(:upload_gpg_key_to_github, nil) do
              _out, err = capture_io { Installer::Setup.setup_gpg_key }
              assert_empty err
            end
          end
        end
      end
    end

    assert_equal ['VALIDKEY'], configured
    assert_equal 'VALIDKEY', ENV['GIT_SIGNING_KEY']
  ensure
    ENV['GIT_EMAIL'] = old_email
    ENV['GIT_NAME'] = old_name
    ENV['GIT_SIGNING_KEY'] = old_signing_key
  end

  # platform

  def detect_with(os_release)
    Tempfile.create('os-release') do |f|
      f.write(os_release)
      f.flush
      Installer::Platform.detect(ruby_platform: 'x86_64-linux', os_release: f.path)
    end
  end

  def test_platform_detects_debian_family
    assert_equal 'debian', detect_with("ID=ubuntu\nID_LIKE=debian\n")
    assert_equal 'debian', detect_with("ID=debian\n")
    assert_equal 'debian', detect_with("ID=linuxmint\nID_LIKE=\"ubuntu debian\"\n")
  end

  def test_platform_detects_arch_family
    assert_equal 'arch', detect_with("ID=arch\n")
    assert_equal 'arch', detect_with("ID=manjaro\nID_LIKE=arch\n")
    assert_equal 'arch', detect_with("ID=endeavouros\nID_LIKE=arch\n")
  end

  def test_platform_does_not_support_other_distributions
    assert_nil detect_with("ID=fedora\n")
    assert_nil Installer::Platform.detect(ruby_platform: 'x86_64-linux', os_release: '/nonexistent/os-release')
  end

  def test_platform_detects_macos
    assert_equal 'macos', Installer::Platform.detect(ruby_platform: 'arm64-darwin25')
  end

  # npm installs the pi CLI, which the pi backend then uses
  def test_platform_backends_end_with_npm_pi_and_pipx
    assert_equal %w[apt snap flatpak npm pi pipx], Installer::Platform.backends('debian')
    assert_equal %w[brew brew_cask npm pi pipx], Installer::Platform.backends('macos')
    assert_equal %w[pacman yay flatpak npm pi pipx], Installer::Platform.backends('arch')
  end

  def test_platform_backends_reject_an_unknown_platform
    error = assert_raises(Installer::Error) { Installer::Platform.backends('fedora') }
    assert_includes error.message, 'Unsupported operating system'
  end

  # missing package managers

  def test_an_optional_backend_without_its_command_is_skipped
    Installer::Utils.stub(:command?, false) do
      Installer::Utils.stub(:run!, ->(*cmd) { flunk "must not run #{cmd.join(' ')}" }) do
        out, = capture_io { Installer::Packages.install('yay', ['x']) }
        assert_includes out, 'skipping yay packages'
      end
    end
  end

  def test_a_system_backend_without_its_command_fails
    Installer::Utils.stub(:command?, false) do
      error = assert_raises(Installer::CommandFailed) { Installer::Packages.install('apt', ['x']) }
      assert_includes error.message, 'apt-get is required'
    end
  end

  # bash_bootstrap

  def test_install_sh_exists
    install_sh = File.join(@shell_dir, 'install.sh')
    assert File.exist?(install_sh), "install.sh should exist"
  end

  def test_install_sh_syntax
    install_sh = File.join(@shell_dir, 'install.sh')
    result = system("bash -n #{install_sh} 2>/dev/null")
    assert result, "install.sh should have valid bash syntax"
  end

  def test_install_sh_is_executable
    install_sh = File.join(@shell_dir, 'install.sh')
    assert File.executable?(install_sh), "install.sh should be executable"
  end

  def test_install_sh_does_not_use_bundler_for_runtime
    install_sh = File.join(@shell_dir, 'install.sh')

    refute_includes File.read(install_sh), 'bundle exec ruby'
  end

  # env_vars

  def test_skip_backends_env_parsing
    # Simulate parsing SKIP_BACKENDS=snap,npm
    skip_backends = 'snap,npm'.split(',').map(&:strip)

    assert_includes skip_backends, 'snap'
    assert_includes skip_backends, 'npm'
    refute_includes skip_backends, 'apt'
  end

  def test_skip_backends_env_with_whitespace
    skip_backends = 'snap, npm , flatpak'.split(',').map(&:strip)

    assert_includes skip_backends, 'snap'
    assert_includes skip_backends, 'npm'
    assert_includes skip_backends, 'flatpak'
  end

  def test_skip_backends_empty_env
    skip_backends = ''.split(',').map(&:strip)
    assert_empty skip_backends
  end

  def test_run_bang_raises_when_command_fails
    error = assert_raises(Installer::CommandFailed) do
      Installer::Utils.run!('ruby', '-e', 'exit false')
    end

    assert_includes error.message, 'ruby -e'
  end

  def test_try_run_records_optional_failure_without_raising
    output, = capture_io do
      result = Installer::Utils.try_run('ruby', '-e', 'exit false')
      assert_equal false, result
    end

    assert_includes output, 'Optional command failed'
  end

  def test_login_required_keeps_one_copy_of_each_reason
    Installer::Utils.login_reasons.clear
    2.times { Installer::Utils.login_required('Docker group membership requires a new login session') }

    assert_equal ['Docker group membership requires a new login session'], Installer::Utils.login_reasons
  ensure
    Installer::Utils.login_reasons.clear
  end

  # cli

  def test_no_steps_runs_every_step
    options = Installer::CLI.parse_args([])

    assert_equal Installer::CLI::STEPS, options[:steps]
    assert options[:all]
  end

  def test_steps_run_in_install_order
    options = Installer::CLI.parse_args(%w[bb stow])

    assert_equal %w[stow bb], options[:steps]
    refute options[:all]
  end

  def test_generate_takes_targets
    options = Installer::CLI.parse_args(%w[generate zsh])

    assert_equal ['generate'], options[:steps]
    assert_equal ['zsh'], options[:targets]
    assert_equal Installer::CLI::GENERATE_TARGETS, Installer::CLI.parse_args(['generate'])[:targets]
  end

  def test_unknown_arguments_and_targets_without_generate_exit_2
    [['zsh'], ['nope']].each do |args|
      error = assert_raises(SystemExit) { capture_io { Installer::CLI.parse_args(args) } }
      assert_equal 2, error.status, "for #{args.inspect}"
    end
  end

  # smoke_tests

  def test_install_sh_help_flag
    install_sh = File.join(@shell_dir, 'install.sh')
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e(install_sh, '--help')
    end

    assert status.success?, "install.sh --help should exit successfully: #{output}"
    %w[packages stow generate --trace].each do |word|
      assert_includes output, word, "Help should mention #{word}"
    end
    refute_includes output, '--stow', 'Help should not mention the old --stow flag'
  end

  def test_all_expected_packages_present
    content = YAML.load_file(@packages_file)

    # Core packages that should exist across all package managers
    core_packages = %w[git curl wget stow ruby zsh]

    # At least one of the system package managers should have each core package
    system_backends = %w[pacman apt brew]

    core_packages.each do |pkg|
      found = system_backends.any? do |backend|
        content[backend]&.include?(pkg)
      end

      assert found, "Core package #{pkg} should be in at least one system backend"
    end
  end

  def test_no_duplicate_packages_in_same_backend
    content = YAML.load_file(@packages_file)

    content.each do |backend, packages|
      next unless packages.is_a?(Array)

      # Filter to just string packages (not hashes for snap)
      string_packages = packages.select { |p| p.is_a?(String) }
      duplicates = string_packages.group_by(&:itself)
                                  .select { |_, v| v.length > 1 }
                                  .keys

      assert_empty duplicates, "#{backend} should not have duplicate packages: #{duplicates.join(', ')}"
    end
  end
end

# Tests run automatically via Minitest.autorun
# No explicit execution needed here
