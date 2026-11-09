# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'json'
require 'tmpdir'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/cli'
require_relative '../../src/install/bb_shuttle'

class TestBbShuttle < Minitest::Test
  Shuttle = Installer::BbShuttle

  TOML = <<~TOML
    [[server]]
    id = "github"
    name = "GitHub"
    kind = "github"
  TOML

  def plugin_config(values = { 'syncMinutes' => 2, 'reviewSection' => 'code-reviews', 'defaultProject' => 'proj_local' })
    {
      'ok' => true,
      'schema' => {
        'syncMinutes' => { 'type' => 'number' },
        'reviewSection' => { 'type' => 'string' },
        'defaultProject' => { 'type' => 'project' }
      },
      'values' => values
    }
  end

  # Runs the block with bb answering from the given texts and JSON, and records every command run.
  def with_bb(texts:, json: plugin_config, private_dir: nil)
    ran = []
    Dir.mktmpdir do |dir|
      repo = private_dir || dir
      Installer::BbApp.stub(:ensure_running!, true) do
        Installer::BbApp.stub(:install_cli_command!, nil) do
          Installer::PrivateRepo.stub(:present?, true) do
            Shuttle.stub(:bb_text, ->(*args) { texts.fetch(args.first(2)).call(args) }) do
              Installer::Bb.stub(:bb_json, json) do
                Installer::Utils.stub(:run!, ->(*command) { ran << command }) do
                  yield File.join(repo, 'bb', 'shuttle'), ran
                end
              end
            end
          end
        end
      end
    end
  end

  def test_portable_settings_keep_every_value_but_local_ids_sorted_by_name
    assert_equal({ 'reviewSection' => 'code-reviews', 'syncMinutes' => 2 }, Shuttle.portable_settings(plugin_config))
  end

  def test_portable_settings_refuse_a_secret_and_a_setting_without_a_schema
    secret = plugin_config({ 'token' => 'x' }).tap { |config| config['schema']['token'] = { 'type' => 'string', 'secret' => true } }
    assert_raises(Installer::Error) { Shuttle.portable_settings(secret) }
    assert_raises(Installer::Error) { Shuttle.portable_settings(plugin_config({ 'unknown' => 1 })) }
  end

  def test_setting_commands_set_only_what_differs_with_json_for_numbers_and_booleans
    commands = Shuttle.setting_commands({ 'syncMinutes' => 2, 'autoAgent' => false, 'reviewSection' => 'code-reviews' },
                                        { 'syncMinutes' => 5, 'autoAgent' => false, 'reviewSection' => 'reviews' })
    assert_equal [%w[bb plugin config shuttle set syncMinutes 2], %w[bb plugin config shuttle set reviewSection code-reviews]], commands
  end

  def test_export_saves_the_config_and_settings_once_the_saved_toml_restores_to_no_changes
    previews = []
    texts = {
      %w[shuttle config-export] => ->(_) { TOML },
      %w[shuttle config-import] => ->(args) { previews << File.read(args[2]); "No changes.\nNothing saved; run again with --apply to save.\n" }
    }
    with_bb(texts: texts) do |dir, _|
      out, = capture_io { assert Shuttle.export!(dir) }
      assert_equal TOML, File.read(File.join(dir, 'config.toml'))
      assert_equal({ 'reviewSection' => 'code-reviews', 'syncMinutes' => 2 }, JSON.parse(File.read(File.join(dir, 'settings.json'))))
      assert_equal [TOML], previews
      assert_equal %w[config.toml settings.json], Dir.children(dir).sort
      assert_match(/Saved Shuttle's config and 2 settings/, out)
    end
  end

  def test_export_keeps_the_saved_copy_when_the_new_one_would_not_restore_cleanly
    texts = {
      %w[shuttle config-export] => ->(_) { TOML },
      %w[shuttle config-import] => ->(_) { "preset thorough: prompt changes\n" }
    }
    with_bb(texts: texts) do |dir, _|
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'config.toml'), "saved\n")
      error = assert_raises(Installer::Error) { Shuttle.export!(dir) }
      assert_match(/would change Shuttle's config/, error.message)
      assert_equal "saved\n", File.read(File.join(dir, 'config.toml'))
      assert_equal %w[config.toml], Dir.children(dir)
    end
  end

  def test_export_refuses_an_export_without_servers
    with_bb(texts: { %w[shuttle config-export] => ->(_) { "" } }) do |dir, _|
      assert_raises(Installer::Error) { Shuttle.export!(dir) }
      refute File.exist?(dir)
    end
  end

  def test_restore_imports_a_changed_config_and_sets_the_settings_that_differ
    texts = { %w[shuttle config-import] => ->(_) { "server forge: added\n" } }
    json = plugin_config({ 'syncMinutes' => 10, 'reviewSection' => 'code-reviews' })
    with_bb(texts: texts, json: json) do |dir, ran|
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'config.toml'), TOML)
      File.write(File.join(dir, 'settings.json'), JSON.generate({ 'syncMinutes' => 2, 'reviewSection' => 'code-reviews' }))
      out, = capture_io { assert Shuttle.apply!(dir) }
      assert_equal [['bb', 'shuttle', 'config-import', File.join(dir, 'config.toml'), '--apply'], %w[bb plugin config shuttle set syncMinutes 2]], ran
      assert_match(/server forge: added/, out)
    end
  end

  def test_restore_preview_changes_nothing_and_a_match_says_so
    texts = { %w[shuttle config-import] => ->(_) { "No changes.\n" } }
    with_bb(texts: texts, json: plugin_config({ 'syncMinutes' => 2 })) do |dir, ran|
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'config.toml'), TOML)
      File.write(File.join(dir, 'settings.json'), JSON.generate({ 'syncMinutes' => 3 }))
      out, = capture_io { Shuttle.apply!(dir, dry_run: true) }
      assert_empty ran
      assert_match(/Preview only/, out)
      assert_match(/bb plugin config shuttle set syncMinutes 3/, out)

      File.write(File.join(dir, 'settings.json'), JSON.generate({ 'syncMinutes' => 2 }))
      out, = capture_io { Shuttle.apply!(dir) }
      assert_empty ran
      assert_match(/already matches/, out)
    end
  end

  def test_restore_refuses_when_nothing_is_saved
    with_bb(texts: {}) do |dir, _|
      assert_raises(Installer::Error) { Shuttle.apply!(dir) }
    end
  end

  def test_cli_flags_select_the_shuttle_steps
    assert Installer::CLI.parse_args(['--bb-shuttle'])[:bb_shuttle]
    assert Installer::CLI.parse_args(['--bb-shuttle', '--dry-run'])[:dry_run]
    assert Installer::CLI.parse_args(['--bb-shuttle-export'])[:bb_shuttle_export]
    assert_raises(ArgumentError) { Installer::CLI.parse_args(['--bb-shuttle-export', '--dry-run']) }
    assert_raises(ArgumentError) { Installer::CLI.parse_args(['--bb-shuttle', '--bb-automations']) }
  end
end
