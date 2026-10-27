# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'digest'
require 'json'
require 'open3'
require 'tmpdir'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/tools'
require_relative '../../src/install/bb_app'

class TestBbApp < Minitest::Test
  OK = Struct.new(:success?).new(true)
  FAILED = Struct.new(:success?).new(false)

  def stub_start(result, &block)
    Installer::BbApp.stub(:start!, lambda {
      @starts = (@starts || 0) + 1
      result
    }, &block)
  end

  # ensure_running!

  def test_a_running_bb_is_not_started_again
    Installer::BbApp.stub(:use_launcher!, nil) do
      Installer::BbApp.stub(:running?, true) do
        stub_start(true) { assert Installer::BbApp.ensure_running! }
      end
    end

    assert_nil @starts
  end

  def test_bb_is_started_and_waited_for
    answers = [false, false, true]
    Installer::BbApp.stub(:use_launcher!, nil) do
      Installer::BbApp.stub(:running?, -> { answers.shift }) do
        Installer::BbApp.stub(:sleep, nil) do
          stub_start(true) { capture_io { assert Installer::BbApp.ensure_running!(timeout: 60) } }
        end
      end
    end

    assert_equal 1, @starts
    assert_empty answers
  end

  def test_waiting_for_bb_gives_up_after_the_timeout
    now = 0
    Installer::BbApp.stub(:use_launcher!, nil) do
      Installer::BbApp.stub(:running?, false) do
        Installer::BbApp.stub(:clock, -> { now += 30 }) do
          Installer::BbApp.stub(:sleep, nil) do
            stub_start(true) { capture_io { refute Installer::BbApp.ensure_running!(timeout: 60) } }
          end
        end
      end
    end
  end

  def test_nothing_is_waited_for_when_bb_cannot_start
    Installer::BbApp.stub(:use_launcher!, nil) do
      Installer::BbApp.stub(:running?, false) do
        Installer::BbApp.stub(:sleep, ->(_) { flunk 'must not wait' }) do
          stub_start(false) { refute Installer::BbApp.ensure_running! }
        end
      end
    end
  end

  def test_the_launcher_bb_writes_is_used_when_bb_is_not_on_path
    Dir.mktmpdir do |data_dir|
      FileUtils.mkdir_p(File.join(data_dir, 'bin'))
      File.write(File.join(data_dir, 'bin', 'bb'), "#!/bin/sh\n")
      File.chmod(0o755, File.join(data_dir, 'bin', 'bb'))
      path = ENV.fetch('PATH', nil)
      bb_data_dir = ENV.fetch('BB_DATA_DIR', nil)
      ENV['BB_DATA_DIR'] = data_dir

      Installer::Utils.stub(:command?, false) { Installer::BbApp.use_launcher! }

      assert_equal File.join(data_dir, 'bin'), ENV.fetch('PATH').split(File::PATH_SEPARATOR).first
    ensure
      ENV['PATH'] = path
      ENV['BB_DATA_DIR'] = bb_data_dir
    end
  end

  def test_start_on_linux_needs_the_appimage_and_a_display
    File.stub(:executable?, true) do
      refute Installer::BbApp.start!(platform: 'x86_64-linux', env: {})
    end
    File.stub(:executable?, false) do
      refute Installer::BbApp.start!(platform: 'x86_64-linux', env: { 'DISPLAY' => ':0' })
    end
  end

  # command line tool

  def test_cli_command_is_installed_only_when_bb_is_not_on_path
    calls = []
    shows = [{ 'onPath' => false, 'supported' => true }, { 'onPath' => true, 'supported' => true }]

    Open3.stub(:capture3, ->(*_cmd) { [JSON.generate(shows.shift), '', OK] }) do
      Installer::Utils.stub(:try_run, ->(*cmd) { calls << cmd }) do
        Installer::BbApp.install_cli_command!
        Installer::BbApp.install_cli_command!
      end
    end

    assert_equal [%w[bb settings cli-command install]], calls
  end

  # Linux AppImage

  def test_appimage_is_installed_only_on_x86_64_linux
    Installer::Utils.stub(:run!, ->(*cmd) { flunk "must not run #{cmd.join(' ')}" }) do
      Installer::BbApp.install_appimage!(platform: 'arm64-darwin25')
      Installer::BbApp.install_appimage!(platform: 'aarch64-linux')
    end
  end

  def test_appimage_file_is_the_x86_64_entry_of_the_release_manifest
    release = { 'files' => [{ 'url' => 'bb-0.46.1-arm64.AppImage' }, { 'url' => 'bb-0.46.1-x86_64.AppImage', 'sha512' => 'abc' }] }

    assert_equal 'bb-0.46.1-x86_64.AppImage', Installer::BbApp.appimage_file(release)['url']
    assert_raises(Installer::CommandFailed) { Installer::BbApp.appimage_file({ 'files' => [] }) }
  end

  def test_download_must_match_the_manifest_checksum
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'bb.AppImage')
      File.write(path, 'appimage')

      Installer::BbApp.verify_sha512!(path, Digest::SHA512.base64digest('appimage'))
      error = assert_raises(Installer::CommandFailed) { Installer::BbApp.verify_sha512!(path, 'wrong') }
      assert_includes error.message, 'checksum mismatch'
    end
  end

  def test_tools_step_runs_the_appimage_installer
    calls = []
    Installer::Tools.stub(:install_npm, nil) do
      Installer::Tools.stub(:install_pi, nil) do
        Installer::Tools.stub(:install_pipx, nil) do
          Installer::Utils.stub(:command?, false) do
            Installer::BbApp.stub(:install_appimage!, -> { calls << :appimage }) do
              Installer::Tools.install!(packages: {})
            end
          end
        end
      end
    end

    assert_equal [:appimage], calls
  end
end
