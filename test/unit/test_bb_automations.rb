# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'yaml'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/cli'
require_relative '../../src/install/bb_automations'

class TestBbAutomations < Minitest::Test
  SHELL_DIR = File.expand_path('../..', __dir__)
  HOME = Dir.home
  Format = Installer::BbAutomationFormat
  Automations = Installer::BbAutomations

  PROJECTS = { 'proj_shell12345' => 'shell', 'proj_personal' => 'Personal' }.freeze
  CONTEXT = {
    projects: PROJECTS,
    environment_path: ->(id) { id == 'env_shell12345' ? "#{HOME}/src/shell" : flunk("unexpected environment #{id}") },
    script_body: ->(path) { path.end_with?('/unstick.sh') ? "#!/bin/bash\necho unstick\n" : flunk("unexpected script #{path}") }
  }.freeze

  def agent_record(execution: {}, **fields)
    {
      'id' => 'auto_disk12345', 'projectId' => 'proj_shell12345', 'name' => 'Weekly disk report', 'enabled' => true,
      'trigger' => { 'triggerType' => 'schedule', 'cron' => '0 14 * * 5', 'timezone' => 'America/Toronto' },
      'execution' => {
        'mode' => 'agent', 'prompt' => "Measure the disk.\n", 'providerId' => 'pi', 'model' => 'anthropic/claude-opus-5-5',
        'reasoningLevel' => 'high', 'permissionMode' => 'full', 'environment' => { 'type' => 'project-default' }
      }.merge(execution),
      'origin' => 'agent', 'createdByThreadId' => 'thr_creator123', 'nextRunAt' => 1, 'lastRunAt' => nil, 'runCount' => 3,
      'lastRunStatus' => 'succeeded', 'lastRunThreadId' => 'thr_lastrun123', 'lastError' => nil, 'createdAt' => 1, 'updatedAt' => 2
    }.merge(fields)
  end

  def script_record(execution: {}, **fields)
    agent_record(
      'id' => 'auto_unstick123', 'name' => 'Pool unstick', 'enabled' => false,
      'execution' => {
        'mode' => 'script', 'scriptFile' => 'unstick.sh', 'interpreter' => 'bash', 'timeoutMs' => 90_000,
        'workingDirectory' => { 'type' => 'automation-storage' },
        'storedScriptPath' => "#{HOME}/.bb/plugins/automations/scripts/auto_unstick123/unstick.sh"
      }.merge(execution),
      **fields
    )
  end

  def normalize(record)
    Format.normalize(record, **CONTEXT)
  end

  def with_roots
    Dir.mktmpdir do |dir|
      public_root = File.join(dir, 'shell/bb/automations')
      private_root = File.join(dir, 'shell-private/bb/automations')
      FileUtils.mkdir_p([public_root, private_root])
      yield public_root, private_root
    end
  end

  # Format

  def test_normalize_keeps_only_the_portable_fields_of_an_agent_automation
    entry = normalize(agent_record)

    assert_equal 'weekly-disk-report', entry.slug
    assert_equal(
      {
        'name' => 'Weekly disk report', 'project' => 'shell', 'enabled' => true,
        'schedule' => { 'cron' => '0 14 * * 5', 'timezone' => 'America/Toronto' },
        'agent' => { 'provider' => 'pi', 'model' => 'anthropic/claude-opus-5-5', 'reasoning' => 'high', 'permission_mode' => 'full' }
      },
      entry.config
    )
    assert_equal 'prompt.md', entry.body_file
    assert_equal "Measure the disk.\n", entry.body
  end

  def test_normalize_turns_a_reused_environment_into_a_home_relative_path
    entry = normalize(agent_record(execution: { 'environment' => { 'type' => 'reuse', 'environmentId' => 'env_shell12345' } }))

    assert_equal '~/src/shell', entry.config.dig('agent', 'environment')
  end

  def test_normalize_reads_the_path_of_an_unmanaged_workspace
    environment = { 'type' => 'host', 'hostId' => 'host_abc12345', 'workspace' => { 'type' => 'unmanaged', 'path' => "#{HOME}/src/shell" } }
    entry = normalize(agent_record(execution: { 'environment' => environment }))

    assert_equal '~/src/shell', entry.config.dig('agent', 'environment')
  end

  def test_normalize_keeps_a_new_worktree_for_each_run
    named = { 'type' => 'managed-worktree', 'baseBranch' => { 'kind' => 'named', 'name' => 'main' } }
    default = { 'type' => 'managed-worktree', 'baseBranch' => { 'kind' => 'default' } }
    host = ->(workspace) { { 'type' => 'host', 'hostId' => 'host_abc12345', 'workspace' => workspace } }

    assert_equal({ 'new_environment' => 'worktree', 'base_branch' => 'main' },
                 normalize(agent_record(execution: { 'environment' => host.call(named) })).config['agent'].slice('new_environment', 'base_branch'))
    assert_equal({ 'new_environment' => 'worktree' },
                 normalize(agent_record(execution: { 'environment' => host.call(default) })).config['agent'].slice('new_environment', 'base_branch'))
  end

  def test_normalize_keeps_a_script_and_the_body_bb_stored_for_it
    entry = normalize(script_record)

    assert_equal(
      { 'file' => 'unstick.sh', 'interpreter' => 'bash', 'timeout_ms' => 90_000, 'working_directory' => 'automation-storage' },
      entry.config['script']
    )
    refute entry.config['enabled']
    assert_equal 'unstick.sh', entry.body_file
    assert_equal "#!/bin/bash\necho unstick\n", entry.body
  end

  def test_normalize_writes_a_script_working_directory_relative_to_home
    entry = normalize(script_record(execution: { 'workingDirectory' => { 'type' => 'path', 'path' => "#{HOME}/src/shell" } }))

    assert_equal '~/src/shell', entry.config.dig('script', 'working_directory')
  end

  def test_normalize_refuses_automations_that_cannot_move_to_another_machine
    once = agent_record('trigger' => { 'triggerType' => 'once', 'runAt' => 1 })
    targeted = agent_record(execution: { 'targetThreadId' => 'thr_target1234' })

    assert_raises(Installer::BbAutomationFormat::Unportable) { normalize(once) }
    assert_raises(Installer::BbAutomationFormat::Unportable) { normalize(targeted) }
  end

  def test_normalize_fails_on_execution_fields_it_does_not_know
    error = assert_raises(Installer::Error) { normalize(agent_record(execution: { 'futureField' => 1 })) }

    assert_match(/futureField/, error.message)
  end

  def test_slug_is_the_name_in_lower_case_with_dashes
    assert_equal 'inbox-sweep-daily', Format.slug('Inbox sweep: daily')
    assert_equal 'pool-cleanup-keep-slots-free', Format.slug('Pool cleanup: keep slots free!')
  end

  def test_written_automations_load_back_unchanged
    with_roots do |_public_root, private_root|
      [normalize(agent_record), normalize(script_record)].each do |entry|
        Format.write_entry(File.join(private_root, entry.slug), entry)
      end
      loaded = Format.load_root(private_root).to_h { |entry| [entry.slug, entry] }

      assert_equal normalize(agent_record).config, loaded['weekly-disk-report'].config
      assert_equal "Measure the disk.\n", loaded['weekly-disk-report'].body
      assert_equal normalize(script_record).config, loaded['pool-unstick'].config
      assert_equal File.join(private_root, 'pool-unstick'), loaded['pool-unstick'].dir
    end
  end

  def test_write_entry_ends_the_body_with_a_newline_and_removes_a_stale_body
    with_roots do |_public_root, private_root|
      dir = File.join(private_root, 'weekly-disk-report')
      Format.write_entry(dir, normalize(agent_record(execution: { 'prompt' => 'No newline' })))

      assert_equal "No newline\n", File.read(File.join(dir, 'prompt.md'))

      script = normalize(script_record('name' => 'Weekly disk report'))
      Format.write_entry(dir, script)

      assert_equal %w[automation.yml unstick.sh], Dir.children(dir).sort
    end
  end

  def test_load_root_fails_on_unknown_keys
    with_roots do |_public_root, private_root|
      dir = File.join(private_root, 'typo')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'automation.yml'), "name: Typo\nproject: shell\nenabled: true\nschedul: {}\n")

      error = assert_raises(Installer::Error) { Format.load_root(private_root) }
      assert_match(/schedul/, error.message)
    end
  end

  # Export

  def test_export_sends_automations_to_the_private_root_by_default
    with_roots do |public_root, private_root|
      targets = Automations.export_targets([normalize(agent_record)], public_root: public_root, private_root: private_root, denylist: [])

      assert_equal [File.join(private_root, 'weekly-disk-report')], targets.map(&:first)
    end
  end

  def test_export_refreshes_an_automation_already_tracked_publicly
    with_roots do |public_root, private_root|
      Format.write_entry(File.join(public_root, 'weekly-disk-report'), normalize(agent_record))
      targets = Automations.export_targets([normalize(agent_record)], public_root: public_root, private_root: private_root, denylist: [])

      assert_equal [File.join(public_root, 'weekly-disk-report')], targets.map(&:first)
    end
  end

  def test_export_refuses_a_public_automation_with_a_leak
    with_roots do |public_root, private_root|
      Format.write_entry(File.join(public_root, 'weekly-disk-report'), normalize(agent_record))
      leaky = normalize(agent_record(execution: { 'prompt' => "Measure the disk.\nAlso check the Acme monorepo.\n" }))

      error = assert_raises(Installer::Error) do
        Automations.export_targets([leaky], public_root: public_root, private_root: private_root, denylist: [/acme/i])
      end
      assert_match(%r{weekly-disk-report/prompt.md:2}, error.message)
    end
  end

  def test_export_refuses_an_automation_in_both_roots
    with_roots do |public_root, private_root|
      Format.write_entry(File.join(public_root, 'weekly-disk-report'), normalize(agent_record))
      Format.write_entry(File.join(private_root, 'weekly-disk-report'), normalize(agent_record))

      assert_raises(Installer::Error) do
        Automations.export_targets([normalize(agent_record)], public_root: public_root, private_root: private_root, denylist: [])
      end
    end
  end

  def test_export_refuses_two_automations_with_the_same_slug
    with_roots do |public_root, private_root|
      twins = [normalize(agent_record), normalize(agent_record('projectId' => 'proj_personal'))]

      assert_raises(Installer::Error) do
        Automations.export_targets(twins, public_root: public_root, private_root: private_root, denylist: [])
      end
    end
  end

  # Apply

  def loaded(record, root)
    entry = normalize(record)
    Format.write_entry(File.join(root, entry.slug), entry)
    Format.load_root(root).find { |candidate| candidate.slug == entry.slug }
  end

  def plan(desired, live, update: false)
    Automations.plan(desired, live, project_ids: PROJECTS.invert, update: update)
  end

  def test_plan_creates_a_missing_agent_automation
    with_roots do |_public_root, private_root|
      desired = loaded(agent_record(execution: { 'environment' => { 'type' => 'reuse', 'environmentId' => 'env_shell12345' } }), private_root)
      result = plan([desired], {})

      assert_equal [[
        'bb', 'automation', 'create', '--project', 'proj_shell12345', '--name', 'Weekly disk report',
        '--cron', '0 14 * * 5', '--timezone', 'America/Toronto',
        '--prompt', "Measure the disk.\n", '--provider', 'pi', '--model', 'anthropic/claude-opus-5-5',
        '--reasoning', 'high', '--permission-mode', 'full', '--environment', "#{HOME}/src/shell"
      ]], result[:commands]
    end
  end

  def test_plan_creates_a_script_automation_from_its_file
    with_roots do |_public_root, private_root|
      desired = loaded(script_record, private_root)
      result = plan([desired], {})

      assert_equal [[
        'bb', 'automation', 'create', '--project', 'proj_shell12345', '--name', 'Pool unstick', '--disabled',
        '--cron', '0 14 * * 5', '--timezone', 'America/Toronto',
        '--script-file', File.join(private_root, 'pool-unstick/unstick.sh'), '--interpreter', 'bash',
        '--timeout', '90000', '--working-directory', 'automation-storage'
      ]], result[:commands]
    end
  end

  def test_plan_leaves_an_automation_that_matches_alone
    with_roots do |_public_root, private_root|
      desired = loaded(agent_record, private_root)
      live = { ['shell', 'Weekly disk report'] => ['auto_disk12345', normalize(agent_record(execution: { 'prompt' => 'Measure the disk.' }))] }

      assert_empty plan([desired], live)[:commands]
      assert_empty plan([desired], live)[:drift]
    end
  end

  def test_plan_reports_drift_and_replaces_the_automation_only_when_asked
    with_roots do |_public_root, private_root|
      desired = loaded(agent_record, private_root)
      live = { ['shell', 'Weekly disk report'] => ['auto_disk12345', normalize(agent_record(execution: { 'model' => 'other/model' }))] }

      assert_empty plan([desired], live)[:commands]
      assert_equal ['weekly-disk-report'], plan([desired], live)[:drift]
      assert_equal [
        'bb', 'automation', 'update', 'auto_disk12345', '--project', 'proj_shell12345', '--name', 'Weekly disk report',
        '--cron', '0 14 * * 5', '--timezone', 'America/Toronto',
        '--prompt', "Measure the disk.\n", '--provider', 'pi', '--model', 'anthropic/claude-opus-5-5',
        '--reasoning', 'high', '--permission-mode', 'full'
      ], plan([desired], live, update: true)[:commands].first
    end
  end

  def test_plan_pauses_or_resumes_to_match_the_file
    with_roots do |_public_root, private_root|
      desired = loaded(agent_record('enabled' => false), private_root)
      live = { ['shell', 'Weekly disk report'] => ['auto_disk12345', normalize(agent_record)] }

      assert_equal [%w[bb automation pause auto_disk12345 --project proj_shell12345]], plan([desired], live, update: true)[:commands]
    end
  end

  def test_plan_skips_automations_of_a_project_this_machine_does_not_have
    with_roots do |_public_root, private_root|
      desired = loaded(agent_record, private_root)
      result = Automations.plan([desired], {}, project_ids: {}, update: false)

      assert_empty result[:commands]
      assert_equal ['shell'], result[:missing_projects]
    end
  end

  def test_report_does_not_claim_a_match_when_it_left_drift_alone
    out, = capture_io { Automations.report({ commands: [], drift: ['weekly-disk-report'], missing_projects: [] }, false) }

    assert_match(/Differs from bb: weekly-disk-report/, out)
    refute_match(/already match/, out)
  end

  def test_cli_flags_select_the_automation_steps
    assert Installer::CLI.parse_args(['--bb-automations'])[:bb_automations]
    assert Installer::CLI.parse_args(['--bb-automations', '--update'])[:update]
    assert Installer::CLI.parse_args(['--bb-automations-export'])[:bb_automations_export]
    refute Installer::CLI.parse_args([])[:bb_automations]
  end
end
