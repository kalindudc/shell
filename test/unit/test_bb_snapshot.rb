# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require_relative '../../src/install/utils'
require_relative '../../src/install/bb_snapshot'

class TestBbSnapshot < Minitest::Test
  Snapshot = Installer::BbSnapshot

  def config
    {
      'marketplaces' => [{ 'name' => 'personal', 'source' => 'git:https://github.com/example/plugins' }],
      'plugins' => ['reader@personal'],
      'enable' => ['navigation'],
      'disable' => ['provider-codex'],
      'plugin_settings' => { 'reader' => { 'lines' => 3 } },
      'settings' => { 'showGitChanges' => false },
      'completed_turns' => { 'pi' => 'collapse' },
      'experiments' => { 'changelogPreview' => false },
      'ui' => { 'sidebar.visiblePluginPanels' => ['reader/sources'] },
      'keyboard' => [{ 'command' => 'panel.nextTab', 'shortcut' => 'Mod+J' }],
      'theme' => 'default'
    }
  end

  def current
    {
      plugins: { 'reader' => true, 'navigation' => true, 'provider-codex' => true, 'internal-tool' => true },
      plugin_settings: { 'reader' => { 'lines' => 20, 'internalUrl' => 'https://corp.example' } },
      plugin_schemas: { 'reader' => { 'lines' => { 'type' => 'number' } } },
      settings: { 'showGitChanges' => true, 'machineServerUrl' => 'https://corp.example',
                  'providerCompletedTurnDisplay' => { 'pi' => 'flat', 'internal-provider' => 'flat' } },
      experiments: { 'changelogPreview' => true, 'unknown' => true },
      ui: { 'sidebar.visiblePluginPanels' => ['internal-tool/secrets', 'reader/sources', '__bb__/skills'] },
      keyboard: [{ 'command' => 'panel.nextTab', 'shortcut' => { 'key' => 'k', 'mod' => true }, 'platform' => 'mac' },
                 { 'command' => 'plugin:internal-tool/run', 'shortcut' => nil }],
      theme: 'plugin:reader:paper'
    }
  end

  def snapshot(config = self.config, current = self.current)
    Snapshot.capture(config, current)
  end

  def test_capture_updates_only_approved_keys_and_never_copies_sources_or_runtime_state
    saved, notes = snapshot

    assert_equal config['marketplaces'], saved['marketplaces']
    assert_equal config['plugins'], saved['plugins']
    assert_equal({ 'showGitChanges' => true }, saved['settings'])
    assert_equal({ 'reader' => { 'lines' => 20 } }, saved['plugin_settings'])
    assert_equal({ 'pi' => 'flat' }, saved['completed_turns'])
    assert_equal({ 'changelogPreview' => true }, saved['experiments'])
    assert_equal ['reader/sources'], saved.dig('ui', 'sidebar.visiblePluginPanels')
    assert_equal 'plugin:reader:paper', saved['theme']
    assert_includes saved['enable'], 'provider-codex'
    assert_empty saved['disable']
    refute_match(/corp|internal-tool|internal-provider/, YAML.dump(saved))
    assert notes.any? { |note| note.include?('unlisted plugins') }
    assert_equal false, config.dig('settings', 'showGitChanges')
  end

  def test_capture_then_plan_is_a_noop_even_with_unlisted_local_state
    saved, = snapshot
    desired = Installer::Bb.desired_state(saved, 'default')

    assert_empty Installer::Bb.plan(desired, current.merge(marketplaces: ['personal']))
  end

  def test_capture_does_not_expand_the_ui_allowlist_or_copy_an_unapproved_theme
    saved, notes = snapshot(config, current.merge(theme: 'plugin:internal-tool:work'))

    assert_equal 'default', saved['theme']
    assert notes.any? { |note| note.include?('theme') }
  end

  def test_capture_keeps_panel_approvals_separate_from_current_visibility
    recipe = config.merge('ui' => { 'sidebar.visiblePluginPanels' => ['reader/sources', '__bb__/skills'] })
    missing = current.merge(ui: { 'sidebar.visiblePluginPanels' => [] })
    saved, notes = snapshot(recipe, missing)
    assert_equal({ 'sidebar.visiblePluginPanels' => [] }, saved['ui'])
    assert_equal recipe['ui'], saved['ui_capture_allowlist']
    restored, = snapshot(saved, current)
    assert_equal recipe['ui'], restored['ui']
    assert_equal recipe['ui'], restored['ui_capture_allowlist']
  end

  def test_capture_uses_explicit_panel_approvals_not_only_last_captured_visibility
    recipe = config.merge('ui' => { 'sidebar.visiblePluginPanels' => [] },
      'ui_capture_allowlist' => { 'sidebar.visiblePluginPanels' => ['reader/sources'] })
    saved, = snapshot(recipe, current)
    assert_equal ['reader/sources'], saved.dig('ui', 'sidebar.visiblePluginPanels')
    refute_includes saved.dig('ui_capture_allowlist', 'sidebar.visiblePluginPanels'), 'internal-tool/secrets'
    assert_raises(Installer::Error) { snapshot(config.merge('ui_capture_allowlist' => { 'sidebar.hiddenGroups' => [] })) }
    assert_raises(Installer::Error) { snapshot(config.merge('ui_capture_allowlist' => { 'sidebar.visiblePluginPanels' => 'all' })) }
  end

  def test_capture_preserves_unavailable_settings_and_reports_them
    state = current.merge(plugin_settings: {}, plugin_schemas: {})
    saved, notes = snapshot(config, state)

    assert_equal config['plugin_settings'], saved['plugin_settings']
    assert notes.any? { |note| note.include?('reader') }
    assert_raises(Installer::Error) { snapshot(config, current.merge(settings: {})) }
  end

  def test_capture_refuses_secret_fields_even_when_explicitly_listed
    state = current.merge(plugin_schemas: { 'reader' => { 'lines' => { 'type' => 'string', 'secret' => true } } })

    assert_raises(Installer::Error) { snapshot(config, state) }
  end

  def test_capture_does_not_publish_changed_free_text
    recipe = config.merge('settings' => { 'managedBranchPrefix' => 'personal/' },
      'plugin_settings' => { 'reader' => { 'label' => 'Public label' } })
    state = current.merge(settings: current[:settings].merge('managedBranchPrefix' => 'internal-team/'),
      plugin_settings: { 'reader' => { 'label' => 'Private project name' } },
      plugin_schemas: { 'reader' => { 'label' => { 'type' => 'string' } } })
    saved, notes = snapshot(recipe, state)
    assert_equal 'personal/', saved.dig('settings', 'managedBranchPrefix')
    assert_equal 'Public label', saved.dig('plugin_settings', 'reader', 'label')
    refute_match(/internal-team|Private project/, YAML.dump(saved))
    assert notes.any? { |note| note.include?('free-text') }
  end

  def test_capture_refuses_machine_and_unrecognised_general_settings
    %w[machineServerUrl machineGitCredentialsEnabled defaultMachineAccess onboardingCompletedAt newSetting].each do |key|
      assert_raises(Installer::Error) { snapshot(config.merge('settings' => { key => true })) }
    end
  end

  def test_capture_refuses_unknown_ui_keys_and_private_profiles
    assert_raises(Installer::Error) { snapshot(config.merge('ui' => { 'sidebar.hiddenGroups' => [] })) }
    assert_raises(Installer::Error) { snapshot(config.merge('profiles' => { 'work' => { 'settings' => {} } })) }
  end

  def test_capture_refreshes_only_listed_keyboard_commands_and_preserves_platforms
    saved, = snapshot

    assert_equal [{ 'command' => 'panel.nextTab', 'shortcut' => 'Mod+k', 'platform' => 'mac' }], saved['keyboard']
    state = current.merge(keyboard: [])
    saved, notes = snapshot(config, state)
    assert_equal config['keyboard'], saved['keyboard']
    assert notes.any? { |note| note.include?('keyboard') }
  end

  def test_capture_rejects_an_unapproved_plugin_setting_or_invalid_schema_type
    bad = config.merge('plugin_settings' => { 'internal-tool' => { 'name' => 'work' } })
    assert_raises(Installer::Error) { snapshot(bad) }
    assert_raises(Installer::Error) { snapshot(config, current.merge(plugin_schemas: { 'reader' => {} })) }
  end

  def test_export_checks_for_leaks_before_atomically_replacing_the_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'bb.yml')
      File.write(path, YAML.dump(config))
      before = File.read(path)
      secret = current.merge(plugin_settings: { 'reader' => { 'lines' => 'ghp_0123456789abcdefghijABCDEFGHIJ' } })
      Installer::Bb.stub(:current_state, secret) do
        assert_raises(Installer::Error) { Snapshot.export!(path: path, denylist: []) }
      end
      assert_equal before, File.read(path)
      Installer::Bb.stub(:current_state, current) do
        capture_io { assert Snapshot.export!(path: path, denylist: []) }
      end
      assert_equal true, YAML.safe_load_file(path).dig('settings', 'showGitChanges')
      first = File.read(path)
      Installer::Bb.stub(:current_state, current) do
        capture_io { Snapshot.export!(path: path, denylist: []) }
      end
      assert_equal first, File.read(path)
    end
  end

  def test_export_refuses_symlinks_without_touching_the_target
    Dir.mktmpdir do |dir|
      target = File.join(dir, 'target.yml')
      path = File.join(dir, 'bb.yml')
      File.write(target, YAML.dump(config))
      before = File.read(target)
      File.symlink(target, path)
      assert_raises(Installer::Error) { Snapshot.export!(path: path, denylist: []) }
      assert_equal before, File.read(target)
    end
  end

  def test_export_checks_private_denylist_and_never_prints_the_matching_value
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'bb.yml')
      File.write(path, YAML.dump(config.merge('theme' => 'private-example')))
      state = current.merge(theme: 'private-example')
      Installer::Bb.stub(:current_state, state) do
        error = assert_raises(Installer::Error) { Snapshot.export!(path: path, denylist: [/private-example/]) }
        refute_includes error.message, 'private-example'
      end
    end
  end
end
