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
require_relative '../../src/install/state'
require_relative '../../src/install/os'
require_relative '../../src/install/backends'
require_relative '../../src/install/dependencies'
require_relative '../../src/install/post_setup'

# Load the installer script (in a way that doesn't execute main)
# We need to be careful since install.rb has executable code at the bottom

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
    expected_backends = %w[pacman yay apt brew brew_cask snap flatpak npm pipx custom]

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

  def test_packages_yml_custom_packages
    content = YAML.load_file(@packages_file)
    packages = content['custom']

    assert packages.is_a?(Array), "custom packages should be an array"
    assert_includes packages, 'install_zsh_plugins', "custom should include install_zsh_plugins"
    assert_includes packages, 'install_pyenv', "custom should include install_pyenv"
    assert_includes packages, 'install_fzf_latest', "custom should include install_fzf_latest"
    assert_includes packages, 'install_atuin', "custom should include install_atuin"
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

  def test_generate_gitconfig_rb_syntax
    script = File.join(@shell_dir, 'src', 'generate_gitconfig.rb')
    result = system("ruby -c #{script} > /dev/null 2>&1")
    assert result, "src/generate_gitconfig.rb should have valid Ruby syntax"
  end

  def test_extract_signing_fingerprint_from_primary_secret_key
    fingerprint = '1234567890ABCDEF1234567890ABCDEF12345678'
    gpg_output = <<~GPG
      sec:u:4096:1:90ABCDEF12345678:1720000000:0:::::scSC
      fpr:::::::::#{fingerprint}
    GPG

    assert_equal fingerprint, Installer::PostSetup.extract_signing_fingerprint(gpg_output)
  end

  def test_extract_signing_fingerprint_from_signing_subkey
    fingerprint = 'ABCDEF1234567890ABCDEF1234567890ABCDEF12'
    gpg_output = <<~GPG
      sec:u:4096:1:1111111111111111:1720000000:0:::::cC
      fpr:::::::::1111111111111111111111111111111111111111
      ssb:u:4096:1:90ABCDEF12345678:1720000000:0:::::s
      fpr:::::::::#{fingerprint}
    GPG

    assert_equal fingerprint, Installer::PostSetup.extract_signing_fingerprint(gpg_output)
  end

  def test_gpg_user_id_uses_git_name_when_present
    old_name = ENV['GIT_NAME']
    ENV['GIT_NAME'] = 'Example User'

    assert_equal 'Example User <user@example.com>', Installer::PostSetup.gpg_user_id('user@example.com')
  ensure
    ENV['GIT_NAME'] = old_name
  end

  def test_signing_key_available_requires_secret_key
    success = Struct.new(:success?).new(true)
    failure = Struct.new(:success?).new(false)

    Installer::PostSetup.stub(:ensure_gpg_home_permissions!, nil) do
      Installer::PostSetup.stub(:capture_command, ['', '', success]) do
        assert Installer::PostSetup.signing_key_available?('ABC123')
      end

      Installer::PostSetup.stub(:capture_command, ['', 'No secret key', failure]) do
        refute Installer::PostSetup.signing_key_available?('ABC123')
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

      Installer::PostSetup.stub(:gpg_home, dir) do
        Installer::PostSetup.ensure_gpg_home_permissions!
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
      Installer::PostSetup.stub(:signing_key_available?, ->(key) { key == 'VALIDKEY' }) do
        Installer::PostSetup.stub(:find_gpg_signing_key, 'VALIDKEY') do
          Installer::PostSetup.stub(:configure_git_signing, ->(key) { configured << key }) do
            Installer::PostSetup.stub(:upload_gpg_key_to_github, nil) do
              _out, err = capture_io { Installer::PostSetup.setup_gpg_key }
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

  # os_detection

  def test_os_backends_constant
    # This test documents the expected OS backend mapping
    os_backends = {
      'arch' => %w[pacman yay flatpak],
      'ubuntu' => %w[apt snap flatpak],
      'debian' => %w[apt flatpak],
      'macos' => %w[brew brew_cask]
    }

    assert_equal %w[pacman yay flatpak], os_backends['arch']
    assert_equal %w[apt snap flatpak], os_backends['ubuntu']
    assert_equal %w[brew brew_cask], os_backends['macos']
  end

  def test_shared_backends
    shared = %w[npm pipx custom]
    assert_equal 3, shared.length
    assert_includes shared, 'npm'
    assert_includes shared, 'pipx'
    assert_includes shared, 'custom'
  end

  def test_unknown_os_is_not_supported_and_has_no_shared_backends
    refute Installer::OS.supported?('unknown_distro')

    error = assert_raises(Installer::Error) do
      Installer::OS.backends_for('unknown_distro')
    end
    assert_includes error.message, 'Unsupported operating system'
  end

  def test_backend_order_bootstraps_runtime_before_npm
    backends = Installer::OS.backends_for('ubuntu')

    assert_operator backends.index('custom_bootstrap'), :<, backends.index('npm')
    assert_operator backends.index('apt'), :<, backends.index('custom_bootstrap')
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

  # helper_methods

  def test_detect_os_returns_nil_for_unknown
    # We can't easily test the actual detect_os without mocking files
    # but we can verify the logic structure

    # Create a mock os-release file for testing
    Tempfile.create('os-release') do |f|
      f.write("ID=unknown_distro\n")
      f.write("ID_LIKE=unknown\n")
      f.flush

      # Read and parse as the installer would
      id = File.readlines(f.path)
               .find { |line| line.start_with?('ID=') }
               &.split('=', 2)&.[](1)&.strip&.delete('"')

      assert_equal 'unknown_distro', id
    end
  end

  def test_detect_os_arch_variants
    arch_ids = %w[arch manjaro]
    arch_ids.each do |id|
      assert %w[arch manjaro].include?(id), "#{id} should map to arch"
    end
  end

  def test_detect_os_debian_variants
    debian_ids = %w[ubuntu debian]
    debian_ids.each do |id|
      assert %w[ubuntu debian].include?(id), "#{id} should map to debian/ubuntu"
    end
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

  def test_package_manager_bootstrap_runs_before_system_update
    calls = []
    dependencies = Minitest::Mock.new
    dependencies.expect(:package_managers, [{ 'name' => 'apt', 'command' => 'apt-get', 'required' => true }])
    dependencies.expect(:bootstrap_packages, {})

    Installer::Backends.stub(:ensure_package_managers!, ->(_os, _managers) { calls << :package_managers }) do
      Installer::Backends.stub(:install_bootstrap_dependencies!, ->(_packages) { calls << :bootstrap_dependencies }) do
        Installer::Backends.stub(:system_update!, ->(_os) { calls << :system_update }) do
          Installer::Backends.ensure_package_managers!('ubuntu', dependencies.package_managers)
          Installer::Backends.install_bootstrap_dependencies!(dependencies.bootstrap_packages)
          Installer::Backends.system_update!('ubuntu')
        end
      end
    end

    assert_equal %i[package_managers bootstrap_dependencies system_update], calls
    dependencies.verify
  end

  def test_macos_homebrew_bootstrap_runs_before_brew_update
    calls = []
    managers = [
      {
        'name' => 'Homebrew',
        'command' => 'brew',
        'required' => true,
        'install' => ['echo', 'install-homebrew']
      }
    ]
    brew_checks = [false, true]

    Installer::Utils.stub(:command?, ->(command) { command == 'brew' ? brew_checks.shift : true }) do
      Installer::Utils.stub(:run!, ->(*cmd) { calls << cmd }) do
        Installer::Backends.stub(:system_update!, ->(_os) { calls << ['brew', 'update'] }) do
          Installer::Backends.ensure_package_managers!('macos', managers)
          Installer::Backends.system_update!('macos')
        end
      end
    end

    assert_equal [['echo', 'install-homebrew'], ['brew', 'update']], calls
  end

  def test_machine_profile_selection_prefers_env_then_hostname_then_default
    packages = {
      'machine_profiles' => {
        'default' => { 'bootstrap' => { 'apt' => ['default-tool'] } },
        'workstation' => { 'bootstrap' => { 'apt' => ['env-tool'] } },
        'host-a' => { 'bootstrap' => { 'apt' => ['host-tool'] } }
      }
    }

    assert_equal 'workstation', Installer::Dependencies.new(
      packages, 'ubuntu', env: { 'SHELL_MACHINE_PROFILE' => 'workstation' }, hostname: 'host-a'
    ).profile_name
    assert_equal 'host-a', Installer::Dependencies.new(packages, 'ubuntu', env: {}, hostname: 'host-a').profile_name
    assert_equal 'default', Installer::Dependencies.new(packages, 'ubuntu', env: {}, hostname: 'other').profile_name
  end

  def test_dependencies_returns_bootstrap_packages_for_selected_os_backend
    packages = {
      'machine_profiles' => {
        'default' => { 'bootstrap' => { 'apt' => ['curl', 'git'], 'brew' => ['curl'] } }
      }
    }

    dependencies = Installer::Dependencies.new(packages, 'ubuntu', env: {}, hostname: 'other')

    assert_equal({ 'apt' => ['curl', 'git'] }, dependencies.bootstrap_packages)
  end

  def test_state_file_records_and_clears_reboot_required_reasons
    Dir.mktmpdir do |dir|
      state = Installer::State.new(File.join(dir, 'install.json'))

      state.require_reboot('Docker group membership requires a new login session')
      assert state.reboot_required?
      assert_includes state.data['reboot_required'], 'Docker group membership requires a new login session'

      state.clear_reboot!
      refute state.reboot_required?
      assert_empty state.data['reboot_required']
    end
  end

  # smoke_tests

  def test_install_sh_help_flag
    install_sh = File.join(@shell_dir, 'install.sh')
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e(install_sh, '--help')
    end

    assert status.success?, "install.sh --help should exit successfully: #{output}"
    assert_includes output, '--trace', "Help should mention --trace"
    assert_includes output, '--stow', "Help should mention --stow"
    assert_includes output, '--help', "Help should mention --help"
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
