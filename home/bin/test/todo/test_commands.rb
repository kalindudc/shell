#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'fileutils'
require 'tmpdir'
require 'stringio'
require_relative '../../lib/todo/cli'

class TodoTest < Minitest::Test
  def setup
    @conf_dir = Dir.mktmpdir('todo_test')
    ENV['TODO_CONF_DIR'] = @conf_dir
    ENV['NO_COLOR'] = '1'
  end

  def teardown
    FileUtils.rm_rf(@conf_dir)
    ENV.delete('TODO_CONF_DIR')
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  # Run Todo::CLI in-process, capturing stdout/stderr and catching SystemExit.
  # Returns [stdout_string, stderr_string, exit_code]
  def run_todo(*args)
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new

    begin
      Todo::CLI.run(args.dup)
      [$stdout.string, $stderr.string, 0]
    rescue SystemExit => e
      [$stdout.string, $stderr.string, e.status]
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
    end
  end

  # Run and assert success, return stdout
  def run_todo!(*args)
    stdout, stderr, code = run_todo(*args)

    assert_equal 0, code, "Expected success for: todo #{args.join(' ')}\nstderr: #{stderr}"
    stdout
  end

  def read_category_tasks(cat)
    path = File.join(@conf_dir, cat, 'todos.json')
    return [] unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def read_category_meta(cat)
    path = File.join(@conf_dir, cat, '.category.json')
    return {} unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def category_exists?(cat)
    Dir.exist?(File.join(@conf_dir, cat))
  end

  def read_meta
    JSON.parse(File.read(File.join(@conf_dir, '.meta.json')))
  end

  def init! = run_todo!('init')

  # ── Initialization ──────────────────────────────────────────────────

  def test_init_creates_directory_structure
    run_todo!('init')

    assert_path_exists File.join(@conf_dir, '.meta.json')
    assert_path_exists File.join(@conf_dir, 'config.json')
    assert category_exists?('general')
    assert_path_exists File.join(@conf_dir, 'general', '.category.json')
    assert_path_exists File.join(@conf_dir, 'general', 'todos.json')
    assert_equal [], read_category_tasks('general')
    meta = read_category_meta('general')

    assert_equal 'General tasks', meta['description']
  end

  def test_init_creates_config_with_defaults
    run_todo!('init')
    config = JSON.parse(File.read(File.join(@conf_dir, 'config.json')))

    assert_equal 32, config['desc_max']
  end

  def test_init_is_idempotent
    init!
    run_todo!('add', 'Existing task')
    run_todo!('init')

    assert_equal 1, read_category_tasks('general').length
  end

  # ── Adding tasks ────────────────────────────────────────────────────

  def test_add_creates_task_in_default_category
    init!
    out = run_todo!('add', 'Buy groceries')

    assert_match(/Added task #1/, out)
    t = read_category_tasks('general').first

    assert_equal 'Buy groceries', t['description']
    assert_equal 1, t['id']
    assert_equal 'pending', t['status']
    assert_equal 'general', t['category']
  end

  def test_add_with_category_and_priority
    init!
    run_todo!('add', 'Fix bug', '--category', 'work', '--priority', '0')

    assert category_exists?('work')
    t = read_category_tasks('work').first

    assert_equal 'work', t['category']
    assert_equal 0, t['priority']
  end

  def test_add_auto_creates_category
    init!
    run_todo!('add', 'Task', '--category', 'newcat')

    assert category_exists?('newcat')
    assert_equal 'newcat', read_category_tasks('newcat').first['category']
  end

  def test_add_with_alias
    init!
    out = run_todo!('a', 'Quick task')

    assert_match(/Added/, out)
    assert_equal 'Quick task', read_category_tasks('general').first['description']
  end

  def test_add_with_tags
    init!
    run_todo!('add', 'Deploy app', '--tag', 'deploy', '--tag', 'prod')
    t = read_category_tasks('general').first

    assert_equal %w[deploy prod], t['tags']
  end

  def test_add_auto_increments_ids
    init!
    run_todo!('add', 'Task 1')
    run_todo!('add', 'Task 2')
    run_todo!('add', 'Task 3')
    ids = read_category_tasks('general').map { |t| t['id'] }

    assert_equal [1, 2, 3], ids
  end

  # ── Listing tasks ───────────────────────────────────────────────────

  def test_list_shows_all_tasks_across_categories
    init!
    run_todo!('add', 'Task one')
    run_todo!('add', 'Task two', '-c', 'work')
    run_todo!('add', 'Task three', '-c', 'personal')
    out = run_todo!('list')

    assert_match(/Task one/, out)
    assert_match(/Task two/, out)
    assert_match(/Task three/, out)
  end

  def test_list_filters_by_category
    init!
    run_todo!('add', 'Work task', '-c', 'work')
    run_todo!('add', 'Home task', '-c', 'home')
    out = run_todo!('list', '--category', 'work')

    assert_match(/Work task/, out)
    refute_match(/Home task/, out)
  end

  def test_list_filters_by_priority
    init!
    run_todo!('add', 'High pri', '-p', '0')
    run_todo!('add', 'Low pri', '-p', '500')
    out = run_todo!('list', '--priority', '0')

    assert_match(/High pri/, out)
    refute_match(/Low pri/, out)
  end

  def test_list_alias_l
    init!
    _out, _err, code = run_todo('l')

    assert_equal 0, code
  end

  def test_list_alias_ls
    init!
    _out, _err, code = run_todo('ls')

    assert_equal 0, code
  end

  def test_list_shows_count_footer
    init!
    run_todo!('add', 'One')
    run_todo!('add', 'Two')
    out = run_todo!('list')

    assert_match(/2 tasks/, out)
  end

  def test_list_shows_priority_badge
    init!
    run_todo!('add', 'High', '-p', '0')
    out = run_todo!('list')

    assert_match(/\[\s*0\]/, out)
  end

  def test_list_all_includes_done
    init!
    run_todo!('add', 'Active task')
    run_todo!('add', 'Done task')
    run_todo!('done', '2')
    out = run_todo!('list', '--all')

    assert_match(/Active task/, out)
    assert_match(/Done task/, out)
    assert_match(/\[ \]/, out)
    assert_match(/\[x\]/, out)
  end

  def test_list_without_all_excludes_done
    init!
    run_todo!('add', 'Active task')
    run_todo!('add', 'Done task')
    run_todo!('done', '2')
    out = run_todo!('list')

    assert_match(/Active task/, out)
    refute_match(/Done task/, out)
  end

  def test_list_has_header
    init!
    run_todo!('add', 'Task')
    out = run_todo!('list')

    assert_match(/ID/, out)
    assert_match(/Pri/, out)
    assert_match(/Description/, out)
  end

  # ── Completing tasks ────────────────────────────────────────────────

  def test_done_marks_task_in_same_category
    init!
    run_todo!('add', 'Finish report', '-c', 'work')
    run_todo!('done', '1')
    t = read_category_tasks('work').first

    assert_equal 'done', t['status']
    assert_match(/\d{4}-\d{2}-\d{2}/, t['completed'])
    assert_equal 1, read_category_tasks('work').length
  end

  def test_done_rejects_invalid_id
    init!
    _out, _err, code = run_todo('done', '999')

    refute_equal 0, code
  end

  def test_done_alias_d
    init!
    run_todo!('add', 'Quick task')
    run_todo!('d', '1')
    t = read_category_tasks('general').first

    assert_equal 'done', t['status']
  end

  # ── Editing tasks ───────────────────────────────────────────────────

  def test_edit_updates_description
    init!
    run_todo!('add', 'Old description')
    run_todo!('edit', '1', '--description', 'New description')

    assert_equal 'New description', read_category_tasks('general').first['description']
  end

  def test_edit_changes_category_moves_task
    init!
    run_todo!('add', 'Task', '-c', 'work')
    run_todo!('edit', '1', '--category', 'personal')

    assert_equal [], read_category_tasks('work')
    assert_equal 1, read_category_tasks('personal').length
    assert_equal 'personal', read_category_tasks('personal').first['category']
  end

  def test_edit_updates_modified_date
    init!
    run_todo!('add', 'Task to edit')
    run_todo!('edit', '1', '--description', 'Edited task')

    assert_match(/\d{4}-\d{2}-\d{2}/, read_category_tasks('general').first['modified'])
  end

  def test_edit_removes_tag
    init!
    run_todo!('add', 'Tagged task', '--tag', 'keep', '--tag', 'remove', '--tag', 'also-keep')
    run_todo!('edit', '1', '--remove-tag', 'remove')
    t = read_category_tasks('general').first

    assert_equal %w[keep also-keep], t['tags']
  end

  def test_edit_removes_multiple_tags
    init!
    run_todo!('add', 'Tagged task', '-t', 'a', '-t', 'b', '-t', 'c')
    run_todo!('edit', '1', '-rt', 'a', '-rt', 'c')
    t = read_category_tasks('general').first

    assert_equal %w[b], t['tags']
  end

  def test_edit_add_and_remove_tags_together
    init!
    run_todo!('add', 'Task', '-t', 'old')
    run_todo!('edit', '1', '-t', 'new', '-rt', 'old')
    t = read_category_tasks('general').first

    assert_equal %w[new], t['tags']
  end

  # ── Deleting tasks ──────────────────────────────────────────────────

  def test_delete_removes_permanently
    init!
    run_todo!('add', 'Temp task')
    run_todo!('delete', '1')

    assert_equal 0, read_category_tasks('general').length
  end

  def test_delete_alias_rm
    init!
    run_todo!('add', 'Remove me')
    run_todo!('rm', '1')

    assert_equal 0, read_category_tasks('general').length
  end

  # ── Searching ───────────────────────────────────────────────────────

  def test_search_finds_matching_across_categories
    init!
    run_todo!('add', 'Buy milk')
    run_todo!('add', 'Buy bread', '-c', 'work')
    run_todo!('add', 'Fix car')
    out = run_todo!('search', 'Buy')

    assert_match(/milk/, out)
    assert_match(/bread/, out)
    refute_match(/car/, out)
  end

  def test_search_case_insensitive
    init!
    run_todo!('add', 'Buy MILK')
    out = run_todo!('search', 'milk')

    assert_match(/MILK/, out)
  end

  def test_search_all_includes_done
    init!
    run_todo!('add', 'Completed task')
    run_todo!('done', '1')
    out = run_todo!('search', 'Completed', '--all')

    assert_match(/Completed/, out)
  end

  def test_search_alias_f
    init!
    run_todo!('add', 'Searchable')
    _out, _err, code = run_todo('f', 'Searchable')

    assert_equal 0, code
  end

  def test_search_shows_result_count
    init!
    run_todo!('add', 'Find me')
    out = run_todo!('search', 'Find')

    assert_match(/1 result/, out)
  end

  # ── Categories ──────────────────────────────────────────────────────

  def test_category_list_shows_directories
    init!
    run_todo!('category', 'add', 'work', '--description', 'Work tasks')
    out = run_todo!('category', 'list')

    assert_match(/general/, out)
    assert_match(/work/, out)
  end

  def test_category_add_creates_directory
    init!
    run_todo!('category', 'add', 'work', '--description', 'Work tasks')

    assert category_exists?('work')
    meta = read_category_meta('work')

    assert_equal 'Work tasks', meta['description']
  end

  def test_category_delete_removes_directory
    init!
    run_todo!('category', 'add', 'temp')
    run_todo!('category', 'delete', 'temp')

    refute category_exists?('temp')
  end

  def test_category_delete_refuses_with_tasks
    init!
    run_todo!('add', 'Task', '-c', 'work')
    _out, stderr, code = run_todo('category', 'delete', 'work')

    refute_equal 0, code
    assert_match(/--force/, stderr)
  end

  def test_category_delete_force_with_tasks
    init!
    run_todo!('add', 'Task', '-c', 'work')
    run_todo!('category', 'delete', 'work', '--force')

    refute category_exists?('work')
  end

  def test_category_aliases
    init!
    _out, _err, s1 = run_todo('cat', 'l')

    assert_equal 0, s1
    _out, _err, s2 = run_todo('cat', 'a', 'test')

    assert_equal 0, s2
    _out, _err, s3 = run_todo('cat', 'rm', 'test')

    assert_equal 0, s3
  end

  # ── History ─────────────────────────────────────────────────────────

  def test_history_shows_completed_across_categories
    init!
    run_todo!('add', 'Done one')
    run_todo!('add', 'Done two', '-c', 'work')
    run_todo!('done', '1')
    run_todo!('done', '2')
    out = run_todo!('history')

    assert_match(/Done one/, out)
    assert_match(/Done two/, out)
  end

  def test_history_filters_by_category
    init!
    run_todo!('add', 'Work done', '-c', 'work')
    run_todo!('add', 'Home done', '-c', 'home')
    run_todo!('done', '1')
    run_todo!('done', '2')
    out = run_todo!('history', '--category', 'work')

    assert_match(/Work done/, out)
    refute_match(/Home done/, out)
  end

  def test_history_alias_h
    init!
    _out, _err, code = run_todo('h')

    assert_equal 0, code
  end

  # ── Show ────────────────────────────────────────────────────────────

  def test_show_displays_detail
    init!
    run_todo!('add', 'Detailed task', '-c', 'work', '-p', '5', '-t', 'urgent')
    out = run_todo!('show', '1')

    assert_match(/Detailed task/, out)
    assert_match(/work/, out)
    assert_match(/5/, out)
    assert_match(/urgent/, out)
  end

  def test_show_finds_completed_task
    init!
    run_todo!('add', 'Historical task')
    run_todo!('done', '1')
    out = run_todo!('show', '1')

    assert_match(/Historical task/, out)
    assert_match(/done/, out)
    assert_match(/Completed/, out)
  end

  def test_show_alias_v
    init!
    run_todo!('add', 'View me')
    _out, _err, code = run_todo('v', '1')

    assert_equal 0, code
  end

  def test_show_alias_s
    init!
    run_todo!('add', 'View me')
    _out, _err, code = run_todo('s', '1')

    assert_equal 0, code
  end

  # ── Help ────────────────────────────────────────────────────────────

  def test_help_displays_usage
    out = run_todo!('help')

    assert_match(/usage/, out)
  end

  def test_help_flag
    out, _err, code = run_todo('--help')

    assert_equal 0, code
    assert_match(/usage/, out)
  end

  def test_no_args_shows_help
    out, _err, code = run_todo

    assert_equal 0, code
    assert_match(/usage/, out)
  end

  # ── Subcommand help ─────────────────────────────────────────────────

  def test_add_help_flag
    init!
    out = run_todo!('add', '-h')

    assert_match(/--category/, out)
    assert_match(/--priority/, out)
    assert_match(/--tag/, out)
  end

  def test_list_help_flag
    init!
    out = run_todo!('list', '-h')

    assert_match(/--category/, out)
    assert_match(/--priority/, out)
    assert_match(/--all/, out)
  end

  def test_done_help_flag
    init!
    out = run_todo!('done', '-h')

    assert_match(/complete/, out)
  end

  def test_edit_help_flag
    init!
    out = run_todo!('edit', '-h')

    assert_match(/--description/, out)
    assert_match(/--remove-tag/, out)
  end

  def test_delete_help_flag
    init!
    out = run_todo!('delete', '-h')

    assert_match(/delete/i, out)
  end

  def test_search_help_flag
    init!
    out = run_todo!('search', '-h')

    assert_match(/--all/, out)
    assert_match(/find/, out)
  end

  def test_category_help_flag
    init!
    out = run_todo!('category', '-h')

    assert_match(/list/, out)
    assert_match(/add/, out)
    assert_match(/delete/, out)
  end

  def test_history_help_flag
    init!
    out = run_todo!('history', '-h')

    assert_match(/--from/, out)
    assert_match(/--to/, out)
  end

  def test_show_help_flag
    init!
    out = run_todo!('show', '-h')

    assert_match(/detailed/i, out)
  end

  # ── Configuration ──────────────────────────────────────────────────

  def test_desc_max_config_truncates_list
    init!
    File.write(File.join(@conf_dir, 'config.json'), JSON.generate({ 'desc_max' => 10 }))
    run_todo!('add', 'This is a long description')
    out = run_todo!('list')

    assert_match(/This is\.\.\./, out)
    refute_match(/This is a long description/, out)
  end

  def test_desc_max_default_preserves_short
    init!
    run_todo!('add', 'Short')
    out = run_todo!('list')

    assert_match(/Short/, out)
    refute_match(/\.\.\./, out)
  end

  # ── Auto-discovery ─────────────────────────────────────────────────

  def test_auto_discover_external_json
    init!
    run_todo!('add', 'Canonical task', '-c', 'work')
    external = [{ 'id' => 999, 'description' => 'External task', 'category' => 'work',
                  'priority' => 50, 'status' => 'pending', 'created' => '2026-01-01',
                  'modified' => '2026-01-01', 'tags' => ['external'] }]
    File.write(File.join(@conf_dir, 'work', 'backlog.json'), JSON.generate(external))
    out = run_todo!('list')

    assert_match(/Canonical task/, out)
    assert_match(/External task/, out)
    assert_match(/2 tasks/, out)
  end

  # ── Error handling ──────────────────────────────────────────────────

  def test_commands_require_init
    FileUtils.rm_rf(@conf_dir)
    _out, stderr, code = run_todo('list')

    refute_equal 0, code
    assert_match(/init/, stderr)
  end
end
