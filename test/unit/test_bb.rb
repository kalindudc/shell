# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'json'
require 'open3'
require 'yaml'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/cli'
require_relative '../../src/install/bb'

class TestBb < Minitest::Test
  SHELL_DIR = File.expand_path('../..', __dir__)
  OK = Struct.new(:success?).new(true)
  FAILED = Struct.new(:success?).new(false)

  CONFIG = {
    'marketplaces' => [{ 'name' => 'kalindudc', 'source' => 'git:github.com/kalindudc/bb-marketplace@main' }],
    'plugins' => ['follow-thinking@kalindudc'],
    'enable' => ['workflows'],
    'settings' => { 'defaultProviderId' => 'pi', 'managedBranchPrefix' => 'kalindudc/' },
    'theme' => 'gruvbox',
    'profiles' => {
      'work' => {
        'marketplaces' => [{ 'name' => 'shopify', 'source' => 'git:github.com/shopify-playground/bb-marketplace@main' }],
        'plugins' => ['pr-desk@shopify'],
        'settings' => { 'managedBranchPrefix' => 'work/' },
        'theme' => 'default'
      }
    }
  }.freeze

  MATCHING_STATE = {
    marketplaces: %w[bb-official bb-community kalindudc],
    plugins: { 'follow-thinking' => true, 'workflows' => true },
    settings: { 'defaultProviderId' => 'pi', 'managedBranchPrefix' => 'kalindudc/', 'showGitChanges' => true },
    theme: 'gruvbox'
  }.freeze

  # bb.yml and packages.yml

  def test_bb_yml_declares_the_kalindudc_marketplace_and_follow_thinking
    config = YAML.load_file(File.join(SHELL_DIR, 'bb.yml'))
    desired = Installer::Bb.desired_state(config, 'default')

    assert_includes desired['marketplaces'].map { |m| m['name'] }, 'kalindudc'
    assert_includes desired['plugins'], 'follow-thinking@kalindudc'
    desired['plugins'].each { |entry| Installer::Bb.plugin_id(entry) }
  end

  def test_packages_yml_installs_the_bb_app_on_macos
    packages = YAML.load_file(File.join(SHELL_DIR, 'packages.yml'))

    assert_includes packages['brew_cask'], 'bb'
  end

  def test_cli_bb_flag_runs_only_the_bb_step
    assert Installer::CLI.parse_args(['--bb'])[:bb_only]
    refute Installer::CLI.parse_args([])[:bb_only]
  end

  # desired state

  def test_desired_state_adds_the_profile_to_the_shared_state
    desired = Installer::Bb.desired_state(CONFIG, 'work')

    assert_equal %w[kalindudc shopify], desired['marketplaces'].map { |m| m['name'] }
    assert_equal %w[follow-thinking@kalindudc pr-desk@shopify], desired['plugins']
    assert_equal({ 'defaultProviderId' => 'pi', 'managedBranchPrefix' => 'work/' }, desired['settings'])
    assert_equal 'default', desired['theme']
  end

  def test_desired_state_for_a_profile_without_bb_entries_is_the_shared_state
    desired = Installer::Bb.desired_state(CONFIG, 'laptop')

    assert_equal ['follow-thinking@kalindudc'], desired['plugins']
    assert_equal 'gruvbox', desired['theme']
  end

  def test_plugin_entries_must_name_a_marketplace
    assert_equal 'follow-thinking', Installer::Bb.plugin_id('follow-thinking@kalindudc')

    error = assert_raises(Installer::Error) { Installer::Bb.plugin_id('git:https://example.com/plugin.git') }
    assert_includes error.message, '<id>@<marketplace>'
  end

  # plan

  def test_plan_is_empty_when_bb_already_matches
    desired = Installer::Bb.desired_state(CONFIG, 'default')

    assert_empty Installer::Bb.plan(desired, MATCHING_STATE)
  end

  def test_plan_adds_marketplaces_before_installing_their_plugins
    desired = Installer::Bb.desired_state(CONFIG, 'work')

    assert_equal [
      %w[bb marketplace add git:github.com/shopify-playground/bb-marketplace@main],
      %w[bb plugin install pr-desk@shopify --yes],
      %w[bb settings general managedBranchPrefix work/],
      %w[bb theme set default]
    ], Installer::Bb.plan(desired, MATCHING_STATE)
  end

  def test_plan_enables_disabled_plugins_but_not_ones_it_installs
    desired = Installer::Bb.desired_state(CONFIG.merge('enable' => %w[workflows follow-thinking]), 'default')
    current = MATCHING_STATE.merge(plugins: { 'workflows' => false })

    assert_equal [
      %w[bb plugin install follow-thinking@kalindudc --yes],
      %w[bb plugin enable workflows]
    ], Installer::Bb.plan(desired, current)
  end

  def test_plan_passes_setting_values_as_text
    desired = Installer::Bb.desired_state(CONFIG.merge('settings' => { 'showGitChanges' => false }), 'default')

    assert_equal [%w[bb settings general showGitChanges false]], Installer::Bb.plan(desired, MATCHING_STATE)
  end

  # apply

  def test_apply_warns_and_runs_nothing_without_the_bb_cli
    Installer::Utils.stub(:command?, false) do
      Installer::Utils.stub(:run!, ->(*cmd) { flunk "must not run #{cmd.join(' ')}" }) do
        out, = capture_io { refute Installer::Bb.apply!(config: CONFIG, profile: 'default') }
        assert_includes out, 'task bb'
      end
    end
  end

  def test_apply_reads_bb_state_and_runs_only_the_missing_steps
    outputs = {
      %w[marketplace list] => [{ 'name' => 'bb-official' }, { 'name' => 'bb-community' }],
      %w[plugin list] => { 'plugins' => [{ 'id' => 'workflows', 'enabled' => true }] },
      %w[settings show] => {
        'generalSettings' => { 'defaultProviderId' => 'pi', 'managedBranchPrefix' => 'kalindudc/' },
        'appearance' => { 'themeId' => 'gruvbox' }
      }
    }
    capture = lambda do |*cmd|
      assert_equal ['bb', '--json'], [cmd.first, cmd.last]
      [JSON.generate(outputs.fetch(cmd[1..-2])), '', OK]
    end
    calls = []

    Installer::Utils.stub(:command?, ->(name) { name == 'bb' }) do
      Open3.stub(:capture3, capture) do
        Installer::Utils.stub(:run!, ->(*cmd) { calls << cmd }) do
          capture_io { assert Installer::Bb.apply!(config: CONFIG, profile: 'default') }
        end
      end
    end

    assert_equal [
      %w[bb marketplace add git:github.com/kalindudc/bb-marketplace@main],
      %w[bb plugin install follow-thinking@kalindudc --yes]
    ], calls
  end

  def test_bb_json_reads_utf8_whatever_the_locale_encoding
    output = JSON.generate({ 'label' => 'Settings → General' }).dup.force_encoding(Encoding::US_ASCII)

    Open3.stub(:capture3, [output, '', OK]) do
      assert_equal({ 'label' => 'Settings → General' }, Installer::Bb.bb_json('settings', 'show'))
    end
  end

  def test_apply_fails_when_bb_cannot_report_its_state
    Installer::Utils.stub(:command?, true) do
      Open3.stub(:capture3, ['', 'connect ECONNREFUSED 127.0.0.1:38886', FAILED]) do
        error = assert_raises(Installer::CommandFailed) do
          capture_io { Installer::Bb.apply!(config: CONFIG, profile: 'default') }
        end
        assert_includes error.message, 'ECONNREFUSED'
      end
    end
  end
end
