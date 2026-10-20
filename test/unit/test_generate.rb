# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'

require_relative '../../src/install/utils'
require_relative '../../src/install/generate'

class TestGenerate < Minitest::Test
  SHELL_DIR = File.expand_path('../..', __dir__)

  def test_zshrc_matches_the_committed_file
    assert_equal File.read(File.join(SHELL_DIR, 'home', '.zshrc'), encoding: 'UTF-8'), Installer::Generate.zshrc
  end

  def test_ghostty_font_size_depends_on_the_platform
    assert_includes Installer::Generate.ghostty_config(ruby_platform: 'arm64-darwin25'), 'font-size = 13'
    assert_includes Installer::Generate.ghostty_config(ruby_platform: 'x86_64-linux'), 'font-size = 11'
  end

  def test_gitconfig_uses_git_values_from_the_environment
    saved = ENV.to_h.slice('GIT_NAME', 'GIT_EMAIL', 'GIT_SIGNING_KEY')
    ENV['GIT_NAME'] = 'Test User'
    ENV['GIT_EMAIL'] = 'test@example.com'
    ENV['GIT_SIGNING_KEY'] = ''

    gitconfig = Installer::Generate.gitconfig

    assert_includes gitconfig, 'name = Test User'
    refute_includes gitconfig, 'signingkey'
  ensure
    %w[GIT_NAME GIT_EMAIL GIT_SIGNING_KEY].each { |key| ENV[key] = saved[key] }
  end
end
