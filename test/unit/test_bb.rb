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
        'marketplaces' => [{ 'name' => 'example', 'source' => 'git:github.com/example/bb-marketplace@main' }],
        'plugins' => ['pr-desk@example'],
        'plugin_settings' => { 'pr-desk' => { 'refreshSeconds' => 60 } },
        'settings' => { 'managedBranchPrefix' => 'work/' },
        'theme' => 'default'
      }
    }
  }.freeze

  MATCHING_STATE = {
    marketplaces: %w[bb-official bb-community kalindudc],
    plugins: { 'follow-thinking' => true, 'workflows' => true },
    plugin_settings: {},
    settings: { 'defaultProviderId' => 'pi', 'managedBranchPrefix' => 'kalindudc/', 'showGitChanges' => true },
    experiments: { 'changelogPreview' => false },
    ui: { 'sidebar.threadListProvider' => '__automatic__' },
    theme: 'gruvbox'
  }.freeze

  # bb.yml and packages.yml

  def bb_yml
    YAML.load_file(File.join(SHELL_DIR, 'bb.yml'))
  end

  def test_bb_yml_declares_every_personal_plugin
    desired = Installer::Bb.desired_state(bb_yml, 'default')
    ids = desired['plugins'].map { |entry| Installer::Bb.plugin_id(entry) }

    assert_includes desired['marketplaces'].map { |m| m['name'] }, 'kalindudc'
    %w[follow-thinking session-log switchboard agent-graph bb-autoresearch tokyo-night pi-minions pi-quests].each do |id|
      assert_includes ids, id
    end
  end

  def test_bb_yml_leaves_out_work_only_plugins_and_settings
    refute_match(/shopify/i, File.read(File.join(SHELL_DIR, 'bb.yml'), encoding: 'UTF-8'))
  end

  def test_bb_yml_makes_switchboard_the_thread_list
    assert_equal 'switchboard/switchboard', bb_yml.dig('ui', 'sidebar.threadListProvider')
  end

  def test_packages_yml_installs_the_bb_app_on_macos
    packages = YAML.load_file(File.join(SHELL_DIR, 'packages.yml'))

    assert_includes packages['brew_cask'], 'bb'
  end

  def test_cli_bb_step_runs_only_the_bb_step
    assert_equal ['bb'], Installer::CLI.parse_args(['bb'])[:steps]
  end

  # desired state

  def test_desired_state_adds_the_profile_to_the_shared_state
    desired = Installer::Bb.desired_state(CONFIG, 'work')

    assert_equal %w[kalindudc example], desired['marketplaces'].map { |m| m['name'] }
    assert_equal %w[follow-thinking@kalindudc pr-desk@example], desired['plugins']
    assert_equal({ 'defaultProviderId' => 'pi', 'managedBranchPrefix' => 'work/' }, desired['settings'])
    assert_equal({ 'pr-desk' => { 'refreshSeconds' => 60 } }, desired['plugin_settings'])
    assert_equal 'default', desired['theme']
  end

  def test_desired_state_for_a_profile_without_bb_entries_is_the_shared_state
    desired = Installer::Bb.desired_state(CONFIG, 'laptop')

    assert_equal ['follow-thinking@kalindudc'], desired['plugins']
    assert_equal 'gruvbox', desired['theme']
  end

  def test_desired_state_merges_plugin_settings_key_by_key
    config = {
      'plugin_settings' => { 'switchboard' => { 'snoozeHour' => 10, 'density' => 'compact' } },
      'profiles' => { 'work' => { 'plugin_settings' => { 'switchboard' => { 'density' => 'two-line' } } } }
    }

    assert_equal({ 'switchboard' => { 'snoozeHour' => 10, 'density' => 'two-line' } },
                 Installer::Bb.desired_state(config, 'work')['plugin_settings'])
  end

  def test_plugin_entries_name_a_marketplace_or_a_source
    assert_equal 'follow-thinking', Installer::Bb.plugin_id('follow-thinking@kalindudc')
    assert_equal 'pi-minions', Installer::Bb.plugin_id({ 'id' => 'pi-minions', 'source' => 'git:https://github.com/kalindudc/minions' })

    error = assert_raises(Installer::Error) { Installer::Bb.plugin_id('git:https://example.com/plugin.git') }
    assert_includes error.message, '<id>@<marketplace>'
    assert_raises(Installer::Error) { Installer::Bb.plugin_id({ 'id' => 'pi-minions' }) }
  end

  # plan

  def test_plan_is_empty_when_bb_already_matches
    desired = Installer::Bb.desired_state(CONFIG, 'default')

    assert_empty Installer::Bb.plan(desired, MATCHING_STATE)
  end

  def test_plan_adds_marketplaces_before_installing_their_plugins
    desired = Installer::Bb.desired_state(CONFIG, 'work')

    assert_equal [
      %w[bb marketplace add git:github.com/example/bb-marketplace@main],
      %w[bb plugin install pr-desk@example --yes],
      %w[bb plugin config pr-desk set refreshSeconds 60],
      %w[bb settings general managedBranchPrefix work/],
      %w[bb theme set default]
    ], Installer::Bb.plan(desired, MATCHING_STATE)
  end

  def test_plan_installs_a_plugin_without_a_marketplace_from_its_source
    plugin = { 'id' => 'pi-minions', 'source' => 'git:https://github.com/kalindudc/minions' }
    desired = Installer::Bb.desired_state(CONFIG.merge('plugins' => [plugin]), 'default')

    assert_equal [%w[bb plugin install git:https://github.com/kalindudc/minions --yes]],
                 Installer::Bb.plan(desired, MATCHING_STATE)
    assert_empty Installer::Bb.plan(desired, MATCHING_STATE.merge(plugins: { 'pi-minions' => true, 'workflows' => true }))
  end

  def test_plan_enables_disabled_plugins_but_not_ones_it_installs
    desired = Installer::Bb.desired_state(CONFIG.merge('enable' => %w[workflows follow-thinking]), 'default')
    current = MATCHING_STATE.merge(plugins: { 'workflows' => false })

    assert_equal [
      %w[bb plugin install follow-thinking@kalindudc --yes],
      %w[bb plugin enable workflows]
    ], Installer::Bb.plan(desired, current)
  end

  def test_plan_disables_only_plugins_that_are_on
    desired = Installer::Bb.desired_state(CONFIG.merge('disable' => %w[provider-codex provider-claude-code bb-ai]), 'default')
    current = MATCHING_STATE.merge(plugins: MATCHING_STATE[:plugins].merge('provider-codex' => true, 'provider-claude-code' => false))

    assert_equal [%w[bb plugin disable provider-codex]], Installer::Bb.plan(desired, current)
  end

  def test_bb_yml_turns_off_the_codex_and_claude_code_providers
    assert_equal %w[provider-claude-code provider-codex], bb_yml['disable'].sort
  end

  def test_plan_passes_setting_values_as_text
    desired = Installer::Bb.desired_state(CONFIG.merge('settings' => { 'showGitChanges' => false }), 'default')

    assert_equal [%w[bb settings general showGitChanges false]], Installer::Bb.plan(desired, MATCHING_STATE)
  end

  def test_plan_changes_only_plugin_settings_that_differ
    desired = Installer::Bb.desired_state(
      CONFIG.merge('plugin_settings' => { 'follow-thinking' => { 'lines' => 20, 'mode' => 'auto' } }), 'default'
    )
    current = MATCHING_STATE.merge(plugin_settings: { 'follow-thinking' => { 'lines' => 3, 'mode' => 'auto' } })

    assert_equal [%w[bb plugin config follow-thinking set lines 20]], Installer::Bb.plan(desired, current)
  end

  def test_plan_skips_settings_of_a_plugin_that_is_not_installed_or_listed
    desired = Installer::Bb.desired_state(CONFIG.merge('plugin_settings' => { 'cortex' => { 'memory' => 'read' } }), 'default')

    assert_empty Installer::Bb.plan(desired, MATCHING_STATE)
  end

  def test_plan_sets_completed_turns_experiments_and_ui_preferences
    config = CONFIG.merge(
      'completed_turns' => { 'pi' => 'flat' },
      'experiments' => { 'changelogPreview' => true },
      'ui' => {
        'sidebar.threadListProvider' => 'switchboard/switchboard',
        'sidebar.hiddenFooterItems' => ['builtin:mobile']
      }
    )
    current = MATCHING_STATE.merge(ui: MATCHING_STATE[:ui].merge('sidebar.hiddenFooterItems' => []))

    assert_equal [
      %w[bb settings completed-turns pi flat],
      %w[bb settings experiment changelogPreview true],
      %w[bb settings ui set sidebar.threadListProvider switchboard/switchboard],
      ['bb', 'settings', 'ui', 'set', 'sidebar.hiddenFooterItems', '["builtin:mobile"]']
    ], Installer::Bb.plan(Installer::Bb.desired_state(config, 'default'), current)

    matching = current.merge(
      settings: current[:settings].merge('providerCompletedTurnDisplay' => { 'pi' => 'flat' }),
      experiments: { 'changelogPreview' => true },
      ui: { 'sidebar.threadListProvider' => 'switchboard/switchboard', 'sidebar.hiddenFooterItems' => ['builtin:mobile'] }
    )
    assert_empty Installer::Bb.plan(Installer::Bb.desired_state(config, 'default'), matching)
  end

  # apply

  def with_running_bb(&block)
    Installer::BbApp.stub(:ensure_running!, true) do
      Installer::BbApp.stub(:install_cli_command!, nil, &block)
    end
  end

  def test_apply_warns_and_runs_nothing_when_bb_does_not_start
    Installer::BbApp.stub(:ensure_running!, false) do
      Installer::Utils.stub(:run!, ->(*cmd) { flunk "must not run #{cmd.join(' ')}" }) do
        out, = capture_io { refute Installer::Bb.apply!(config: CONFIG, profile: 'default') }
        assert_includes out, 'task install:bb'
      end
    end
  end

  def test_apply_reads_bb_state_and_runs_only_the_missing_steps
    config = CONFIG.merge('plugin_settings' => { 'workflows' => { 'maxActiveRuns' => 8 }, 'follow-thinking' => { 'lines' => 20 } })
    outputs = {
      %w[marketplace list] => [{ 'name' => 'bb-official' }, { 'name' => 'bb-community' }],
      %w[plugin list] => { 'plugins' => [{ 'id' => 'workflows', 'enabled' => true }] },
      %w[plugin config workflows] => { 'values' => { 'maxActiveRuns' => 4 } },
      %w[settings show] => {
        'generalSettings' => { 'defaultProviderId' => 'pi', 'managedBranchPrefix' => 'kalindudc/' },
        'experiments' => {},
        'appearance' => { 'themeId' => 'gruvbox' }
      },
      %w[settings ui list] => { 'preferences' => { 'sidebar.threadListProvider' => { 'revision' => 0, 'value' => '__automatic__' } } }
    }
    capture = lambda do |*cmd|
      assert_equal ['bb', '--json'], [cmd.first, cmd.last]
      [JSON.generate(outputs.fetch(cmd[1..-2])), '', OK]
    end
    calls = []

    with_running_bb do
      Open3.stub(:capture3, capture) do
        Installer::Utils.stub(:run!, ->(*cmd) { calls << cmd }) do
          capture_io { assert Installer::Bb.apply!(config: config, profile: 'default') }
        end
      end
    end

    assert_equal [
      %w[bb marketplace add git:github.com/kalindudc/bb-marketplace@main],
      %w[bb plugin install follow-thinking@kalindudc --yes],
      %w[bb plugin config workflows set maxActiveRuns 8],
      %w[bb plugin config follow-thinking set lines 20]
    ], calls
  end

  def test_bb_json_reads_utf8_whatever_the_locale_encoding
    output = JSON.generate({ 'label' => 'Settings → General' }).dup.force_encoding(Encoding::US_ASCII)

    Open3.stub(:capture3, [output, '', OK]) do
      assert_equal({ 'label' => 'Settings → General' }, Installer::Bb.bb_json('settings', 'show'))
    end
  end

  def test_apply_fails_when_bb_cannot_report_its_state
    with_running_bb do
      Open3.stub(:capture3, ['', 'connect ECONNREFUSED 127.0.0.1:38886', FAILED]) do
        error = assert_raises(Installer::CommandFailed) do
          capture_io { Installer::Bb.apply!(config: CONFIG, profile: 'default') }
        end
        assert_includes error.message, 'ECONNREFUSED'
      end
    end
  end
end
