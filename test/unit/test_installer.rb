# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'yaml'
require 'fileutils'
require 'open3'
require 'tmpdir'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/cli'
require_relative '../../src/install/main'

# The installer only runs what Nix does not manage: tools, setup, bb and cortex.
class TestInstaller < Minitest::Test
  def setup
    @shell_dir = File.expand_path('../..', __dir__)
    @packages_file = File.join(@shell_dir, 'packages.yml')
  end

  # packages.yml

  def test_packages_yml_holds_only_what_nix_does_not_install
    assert_equal %w[npm pi pipx], YAML.load_file(@packages_file).keys.sort
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

  # cli

  def test_cli_runs_every_step_by_default
    assert_empty Installer::CLI.parse_args([])[:steps]
  end

  def test_cli_collects_step_names
    assert_equal %w[cortex bb], Installer::CLI.parse_args(%w[cortex bb])[:steps]
  end

  def test_cli_rejects_unknown_arguments
    _out, err = capture_io do
      error = assert_raises(SystemExit) { Installer::CLI.parse_args(['--stow']) }
      assert_equal 2, error.status
    end
    assert_includes err, 'Unknown argument: --stow'
  end

  # runner

  def run_steps(args, calls, bb: -> { calls << 'bb' })
    runner = Installer::Runner.new(Installer::CLI.parse_args(args))
    Installer::Setup.stub(:load_env_file, nil) do
      Installer::Tools.stub(:install!, -> { calls << 'tools' }) do
        Installer::Setup.stub(:run!, -> { calls << 'setup' }) do
          Installer::Bb.stub(:apply!, ->(**) { bb.call }) do
            Installer::Cortex.stub(:install!, -> { calls << 'cortex' }) do
              capture_io { runner.run }
            end
          end
        end
      end
    end
  end

  def test_runner_runs_steps_in_order_whatever_order_they_are_given_in
    calls = []
    run_steps(%w[cortex tools], calls)
    assert_equal %w[tools cortex], calls
  end

  def test_runner_full_install_goes_on_when_bb_fails
    calls = []
    run_steps([], calls, bb: -> { raise Installer::CommandFailed, 'bb is not running' })
    assert_equal %w[tools setup cortex], calls
  end

  def test_runner_single_bb_step_fails_when_bb_fails
    calls = []
    error = assert_raises(SystemExit) do
      run_steps(['bb'], calls, bb: -> { raise Installer::CommandFailed, 'bb is not running' })
    end
    assert_equal 1, error.status
  end

  # tools

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
        Installer::Tools.stub(:herdr_integration_status, status) do
          Installer::Utils.stub(:run!, ->(*cmd) { calls << cmd }) do
            capture_io { Installer::Tools.install_herdr_pi_integration }
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
        Installer::Tools.install_herdr_pi_integration
      end
    end
  end

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
          capture_io { Installer::Tools.install_pi(sources) }
        end
      end
    end

    assert_equal [%w[pi install https://github.com/kalindudc/quests --no-approve]], calls
  end

  def test_install_pi_requires_pi
    Installer::Utils.stub(:command?, false) do
      error = assert_raises(Installer::CommandFailed) do
        capture_io { Installer::Tools.install_pi(['https://github.com/kalindudc/quests']) }
      end
      assert_includes error.message, 'pi is required'
    end
  end

  def test_install_pi_fails_when_pi_list_fails
    failure = Struct.new(:success?).new(false)

    Installer::Utils.stub(:command?, true) do
      Open3.stub(:capture3, ['', 'boom', failure]) do
        error = assert_raises(Installer::CommandFailed) do
          capture_io { Installer::Tools.install_pi(['https://github.com/kalindudc/quests']) }
        end
        assert_includes error.message, 'pi list'
      end
    end
  end

  # setup

  def test_configure_git_signing_writes_the_machine_signing_config
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'git', 'signing')
      Installer::Utils.stub(:command?, true) do
        stub_const(Installer::Setup, :SIGNING_CONFIG, path) do
          Installer::Setup.configure_git_signing('ABC123')
        end
      end

      assert_equal 'ABC123', `git config --file #{path} user.signingkey`.strip
      assert_equal 'true', `git config --file #{path} commit.gpgsign`.strip
    end
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

  # files

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

  private

  def stub_const(mod, name, value)
    old = mod.const_get(name)
    mod.send(:remove_const, name)
    mod.const_set(name, value)
    yield
  ensure
    mod.send(:remove_const, name)
    mod.const_set(name, old)
  end
end
