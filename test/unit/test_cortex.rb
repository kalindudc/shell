# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'tmpdir'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/cli'
require_relative '../../src/install/cortex'

class TestCortex < Minitest::Test
  OK = Struct.new(:success?).new(true)
  FAILED = Struct.new(:success?).new(false)

  def setup
    @home = Dir.mktmpdir
    @checkout = File.join(@home, 'src', 'cortex')
    @binary = File.join(@home, 'bin', 'cortex')
    @database = File.join(@home, '.config', 'cortex', 'cortex.db')
    @calls = []
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def install(commands:, gh: OK)
    result = nil
    Installer::Utils.stub(:command?, ->(name) { commands.include?(name) }) do
      Open3.stub(:capture3, ['', '', gh]) do
        Installer::Utils.stub(:run!, ->(*cmd, **opts) { @calls << [cmd, opts] }) do
          @out, = capture_io { result = Installer::Cortex.install!(checkout: @checkout, binary: @binary, database: @database) }
        end
      end
    end
    result
  end

  def commands
    @calls.map(&:first)
  end

  def test_an_installed_cortex_is_not_rebuilt
    FileUtils.mkdir_p(File.dirname(@database))
    File.write(@database, '')

    assert install(commands: %w[cortex gh pnpm])
    assert_equal [%w[cortex agents install]], commands
  end

  def test_a_new_database_is_initialized_first
    assert install(commands: %w[cortex])
    assert_equal [%w[cortex init], %w[cortex agents install]], commands
  end

  def test_cortex_is_built_from_an_existing_checkout_without_pulling
    FileUtils.mkdir_p(File.join(@checkout, '.git'))

    assert install(commands: %w[pnpm])
    assert_equal [[%w[pnpm run deploy], { chdir: @checkout }], [[@binary, 'init'], {}], [[@binary, 'agents', 'install'], {}]], @calls
    assert File.directory?(File.dirname(@binary)), 'pnpm run deploy copies into ~/bin, so it must exist'
  end

  def test_cortex_is_cloned_with_gh_when_there_is_no_checkout
    assert install(commands: %w[gh pnpm])
    assert_equal ['gh', 'repo', 'clone', 'kalindudc/cortex', @checkout], commands.first
    assert_equal %w[pnpm run deploy], commands[1]
  end

  def test_cortex_is_skipped_until_gh_is_signed_in
    refute install(commands: %w[gh pnpm], gh: FAILED)
    assert_empty commands
    assert_includes @out, 'gh auth login'
  end

  def test_cortex_is_skipped_without_pnpm
    FileUtils.mkdir_p(File.join(@checkout, '.git'))

    refute install(commands: %w[gh])
    assert_empty commands
    assert_includes @out, 'pnpm'
  end

  def test_cli_cortex_flag_runs_only_the_cortex_step
    assert Installer::CLI.parse_args(['--cortex'])[:cortex_only]
    refute Installer::CLI.parse_args([])[:cortex_only]
  end
end
