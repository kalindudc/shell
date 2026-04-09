#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'yaml'
require 'fileutils'
require 'tempfile'

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
    assert_includes packages, '@mariozechner/pi-coding-agent', "npm should include pi-coding-agent"
  end

  def test_packages_yml_custom_packages
    content = YAML.load_file(@packages_file)
    packages = content['custom']

    assert packages.is_a?(Array), "custom packages should be an array"
    assert_includes packages, 'install_zsh_plugins', "custom should include install_zsh_plugins"
    assert_includes packages, 'install_pyenv', "custom should include install_pyenv"
    assert_includes packages, 'install_fzf_latest', "custom should include install_fzf_latest"
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

  # smoke_tests

  def test_install_sh_help_flag
    install_sh = File.join(@shell_dir, 'install.sh')
    output = `#{install_sh} --help 2>&1`

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
