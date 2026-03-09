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
    old_stdin = $stdin
    $stdout = StringIO.new
    $stderr = StringIO.new
    # Ensure $stdin is non-TTY to prevent interactive prompts.
    # Only replace if it is the real STDIN (tests may set a custom mock beforehand).
    $stdin = StringIO.new if $stdin.equal?($stdin)

    begin
      Todo::CLI.run(args.dup)
      [$stdout.string, $stderr.string, 0]
    rescue SystemExit => e
      [$stdout.string, $stderr.string, e.status]
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
      $stdin = old_stdin
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

    assert_equal 64, config['desc_max']
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
    # Category is derived from directory name, not stored in task JSON
    assert_nil t['category']
  end

  def test_add_with_category_and_priority
    init!
    run_todo!('add', 'Fix bug', '--category', 'work', '--priority', '0')

    assert category_exists?('work')
    t = read_category_tasks('work').first

    # Category is derived from directory, not stored in JSON
    assert_equal 0, t['priority']
  end

  def test_add_auto_creates_category
    init!
    run_todo!('add', 'Task', '--category', 'newcat')

    assert category_exists?('newcat')
    assert_equal 1, read_category_tasks('newcat').length
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
    run_todo!('mark', '2')
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
    run_todo!('mark', '2')
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

  # ── List: --plain and --done-only ────────────────────────────────────

  def test_list_plain_outputs_tab_delimited
    init!
    run_todo!('add', 'Plain test', '-p', '5', '-t', 'work')
    out = run_todo!('list', '--plain')

    lines = out.strip.split("\n")

    assert_equal 1, lines.length
    fields = lines.first.split("\t")

    assert_equal '1', fields[0]
    assert_equal '[ ]', fields[1]
    assert_equal '5', fields[2]
    assert_equal 'Plain test', fields[3]
    assert_equal 'general', fields[4]
    assert_equal 'work', fields[5]
  end

  def test_list_plain_includes_id_first
    init!
    run_todo!('add', 'First task')
    run_todo!('add', 'Second task')
    out = run_todo!('list', '--plain')

    lines = out.strip.split("\n")

    assert_equal 2, lines.length
    assert_equal '1', lines[0].split("\t").first
    assert_equal '2', lines[1].split("\t").first
  end

  def test_list_plain_no_header_no_footer
    init!
    run_todo!('add', 'Task')
    out = run_todo!('list', '--plain')

    refute_match(/ID/, out)
    refute_match(/tasks/, out)
  end

  def test_list_done_only_shows_completed
    init!
    run_todo!('add', 'Active task')
    run_todo!('add', 'Done task')
    run_todo!('mark', '2')
    out = run_todo!('list', '--done-only')

    assert_match(/Done task/, out)
  end

  def test_list_done_only_excludes_active
    init!
    run_todo!('add', 'Active task')
    run_todo!('add', 'Done task')
    run_todo!('mark', '2')
    out = run_todo!('list', '--done-only')

    refute_match(/Active task/, out)
  end

  # ── JSON output ─────────────────────────────────────────────────────

  def parse_json(out)
    JSON.parse(out.strip)
  end

  # -- list --json --

  def test_list_json_outputs_valid_json
    init!
    run_todo!('add', 'Task one')
    run_todo!('add', 'Task two', '-p', '0', '-t', 'urgent')
    out = run_todo!('list', '--json')
    data = parse_json(out)

    assert_equal 2, data['count']
    assert_equal 2, data['tasks'].length
  end

  def test_list_json_task_shape
    init!
    run_todo!('add', 'JSON task', '-p', '5', '-t', 'work', '-c', 'dev')
    out = run_todo!('list', '--json')
    task = parse_json(out)['tasks'].first

    assert_equal 1, task['id']
    assert_equal 'JSON task', task['description']
    assert_equal 'pending', task['status']
    assert_equal 5, task['priority']
    assert_equal 'dev', task['category']
    assert_equal ['work'], task['tags']
    assert task.key?('created')
    assert task.key?('modified')
    refute task.key?('completed')
  end

  def test_list_json_includes_completed_field_for_done
    init!
    run_todo!('add', 'Done task')
    run_todo!('mark', '1')
    out = run_todo!('list', '--json', '--all')
    done = parse_json(out)['tasks'].find { |t| t['status'] == 'done' }

    assert done.key?('completed')
  end

  def test_list_json_respects_filters
    init!
    run_todo!('add', 'Work task', '-c', 'work')
    run_todo!('add', 'Home task', '-c', 'home')
    out = run_todo!('list', '--json', '-c', 'work')
    data = parse_json(out)

    assert_equal 1, data['count']
    assert_equal 'Work task', data['tasks'].first['description']
  end

  def test_list_json_empty
    init!
    out = run_todo!('list', '--json')
    data = parse_json(out)

    assert_equal 0, data['count']
    assert_equal [], data['tasks']
  end

  def test_list_json_no_ansi
    init!
    run_todo!('add', 'Clean output')
    out = run_todo!('list', '--json')

    refute_includes out, "\033["
  end

  def test_list_json_short_flag
    init!
    run_todo!('add', 'Short flag')
    out = run_todo!('list', '-J')
    data = parse_json(out)

    assert_equal 1, data['count']
  end

  # -- show --json --

  def test_show_json_outputs_valid_json
    init!
    run_todo!('add', 'Show me', '-p', '3', '-t', 'demo', '-c', 'work')
    out = run_todo!('show', '1', '--json')
    task = parse_json(out)

    assert_equal 1, task['id']
    assert_equal 'Show me', task['description']
    assert_equal 'pending', task['status']
    assert_equal 3, task['priority']
    assert_equal 'work', task['category']
    assert_equal ['demo'], task['tags']
  end

  def test_show_json_includes_completed
    init!
    run_todo!('add', 'Done task')
    run_todo!('mark', '1')
    out = run_todo!('show', '1', '--json')
    task = parse_json(out)

    assert_equal 'done', task['status']
    assert task.key?('completed')
  end

  def test_show_json_no_ansi
    init!
    run_todo!('add', 'Clean')
    out = run_todo!('show', '1', '--json')

    refute_includes out, "\033["
  end

  def test_show_json_short_flag
    init!
    run_todo!('add', 'Short flag')
    out = run_todo!('show', '1', '-J')
    task = parse_json(out)

    assert_equal 1, task['id']
  end

  # -- search --json --

  def test_search_json_outputs_valid_json
    init!
    run_todo!('add', 'Buy milk')
    run_todo!('add', 'Buy bread', '-c', 'work')
    run_todo!('add', 'Fix car')
    out = run_todo!('search', 'Buy', '--json')
    data = parse_json(out)

    assert_equal 'Buy', data['term']
    assert_equal 2, data['count']
    assert_equal 2, data['tasks'].length
  end

  def test_search_json_no_results
    init!
    run_todo!('add', 'Something')
    out = run_todo!('search', 'nonexistent', '--json')
    data = parse_json(out)

    assert_equal 0, data['count']
    assert_equal [], data['tasks']
  end

  def test_search_json_respects_all_flag
    init!
    run_todo!('add', 'Active findme')
    run_todo!('add', 'Done findme')
    run_todo!('mark', '2')

    out_without = run_todo!('search', 'findme', '--json')
    out_with = run_todo!('search', 'findme', '--json', '-a')

    assert_equal 1, parse_json(out_without)['count']
    assert_equal 2, parse_json(out_with)['count']
  end

  def test_search_json_no_ansi
    init!
    run_todo!('add', 'Clean output')
    out = run_todo!('search', 'Clean', '--json')

    refute_includes out, "\033["
  end

  def test_search_json_short_flag
    init!
    run_todo!('add', 'Short flag test')
    out = run_todo!('search', 'Short', '-J')
    data = parse_json(out)

    assert_equal 1, data['count']
  end

  # -- category list --json --

  def test_category_list_json_outputs_valid_json
    init!
    run_todo!('category', 'add', 'work', '--description', 'Work tasks')
    out = run_todo!('category', 'list', '--json')
    data = parse_json(out)

    assert data.key?('categories')
    names = data['categories'].map { |c| c['name'] }

    assert_includes names, 'general'
    assert_includes names, 'work'
  end

  def test_category_list_json_includes_description
    init!
    run_todo!('category', 'add', 'dev', '--description', 'Development')
    out = run_todo!('category', 'list', '--json')
    dev = parse_json(out)['categories'].find { |c| c['name'] == 'dev' }

    assert_equal 'Development', dev['description']
  end

  def test_category_list_json_empty
    init!
    # general is always created by init, so we test for at least that
    out = run_todo!('category', 'list', '--json')
    data = parse_json(out)

    assert_operator data['categories'].length, :>=, 1
  end

  def test_category_list_json_no_ansi
    init!
    out = run_todo!('category', 'list', '--json')

    refute_includes out, "\033["
  end

  def test_category_list_json_short_flag
    init!
    out = run_todo!('category', 'list', '-J')
    data = parse_json(out)

    assert data.key?('categories')
  end

  # ── List: interactive dispatch ────────────────────────────────────────
  # These tests call Todo::CLI.run directly with a TTY-like stdin to exercise
  # the interactive browse path (run_todo always sets non-TTY stdin).

  def run_todo_tty(*args)
    old_stdout = $stdout
    old_stderr = $stderr
    old_stdin = $stdin
    $stdout = StringIO.new
    $stderr = StringIO.new
    tty_stdin = StringIO.new
    tty_stdin.define_singleton_method(:tty?) { true }
    $stdin = tty_stdin

    begin
      Todo::CLI.run(args.dup)
      [$stdout.string, $stderr.string, 0]
    rescue SystemExit => e
      [$stdout.string, $stderr.string, e.status]
    ensure
      $stdout = old_stdout
      $stderr = old_stderr
      $stdin = old_stdin
    end
  end

  def with_browse_stub(return_value: nil, &block)
    browse_called_with = nil
    original_browse = Todo::Interactive.method(:browse)
    Todo::Interactive.define_singleton_method(:browse) do |**kwargs|
      browse_called_with = kwargs
      return_value
    end

    original_fzf = Todo::Interactive.method(:fzf_available?)
    Todo::Interactive.define_singleton_method(:fzf_available?) { true }

    block.call(-> { browse_called_with })
  ensure
    Todo::Interactive.define_singleton_method(:browse, original_browse)
    Todo::Interactive.define_singleton_method(:fzf_available?, original_fzf)
  end

  def test_list_calls_browse_when_tty_and_fzf
    init!
    run_todo!('add', 'Interactive task')

    with_browse_stub(return_value: nil) do |get_call|
      out, _err, code = run_todo_tty('list')

      assert_equal 0, code
      refute_nil get_call.call, 'Interactive.browse should have been called'
      # No formatted output since browse handled display
      refute_match(/ID/, out)
    end
  end

  def test_list_browse_shows_task_on_enter
    init!
    run_todo!('add', 'Show me this task')

    with_browse_stub(return_value: 1) do |_get_call|
      out, _err, code = run_todo_tty('list')

      assert_equal 0, code
      # Should have delegated to Show, which outputs the task detail
      assert_match(/Show me this task/, out)
    end
  end

  def test_list_falls_back_to_formatted_when_no_fzf
    init!
    run_todo!('add', 'Fallback task')

    original_fzf = Todo::Interactive.method(:fzf_available?)
    Todo::Interactive.define_singleton_method(:fzf_available?) { false }

    out, _err, code = run_todo_tty('list')

    assert_equal 0, code
    assert_match(/ID/, out)
    assert_match(/Fallback task/, out)
    assert_match(/1 task/, out)
  ensure
    Todo::Interactive.define_singleton_method(:fzf_available?, original_fzf)
  end

  def test_list_passes_filters_to_browse
    init!
    run_todo!('add', 'Work task', '-c', 'work')

    with_browse_stub(return_value: nil) do |get_call|
      run_todo_tty('list', '-c', 'work', '-p', '5', '-t', 'urgent', '--all',
                   '--from', '2026-01-01', '--to', '2026-12-31')

      browse_called_with = get_call.call

      refute_nil browse_called_with
      filters = browse_called_with[:filters]

      assert_equal 'work', filters[:filter_cat]
      assert_equal '5', filters[:filter_pri]
      assert_equal 'urgent', filters[:filter_tag]
      assert filters[:include_done]
      assert_equal '2026-01-01', filters[:date_from]
      assert_equal '2026-12-31', filters[:date_to]
    end
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
    run_todo!('mark', '1')
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

  # ── History (now list --done-only) ───────────────────────────────────

  def test_list_done_only_shows_completed_across_categories
    init!
    run_todo!('add', 'Done one')
    run_todo!('add', 'Done two', '-c', 'work')
    run_todo!('mark', '1')
    run_todo!('mark', '2')
    out = run_todo!('list', '--done-only')

    assert_match(/Done one/, out)
    assert_match(/Done two/, out)
  end

  def test_list_done_only_filters_by_category
    init!
    run_todo!('add', 'Work done', '-c', 'work')
    run_todo!('add', 'Home done', '-c', 'home')
    run_todo!('mark', '1')
    run_todo!('mark', '2')
    out = run_todo!('list', '--done-only', '--category', 'work')

    assert_match(/Work done/, out)
    refute_match(/Home done/, out)
  end

  def test_history_alias_h_maps_to_list
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
    run_todo!('mark', '1')
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

  # ── Mark (toggle) ────────────────────────────────────────────────────

  def test_mark_toggles_pending_to_done
    init!
    run_todo!('add', 'Toggle me')
    out = run_todo!('mark', '1')

    assert_match(/Completed task #1/, out)
    t = read_category_tasks('general').first

    assert_equal 'done', t['status']
    assert t['completed']
  end

  def test_mark_toggles_done_to_pending
    init!
    run_todo!('add', 'Toggle me')
    run_todo!('mark', '1')
    out = run_todo!('mark', '1')

    assert_match(/Reopened task #1/, out)
    t = read_category_tasks('general').first

    assert_equal 'pending', t['status']
    assert_nil t['completed']
  end

  def test_mark_multiple_tasks
    init!
    run_todo!('add', 'Task one')
    run_todo!('add', 'Task two')
    run_todo!('add', 'Task three')
    out = run_todo!('mark', '1', '2', '3')

    assert_match(/Completed task #1/, out)
    assert_match(/Completed task #2/, out)
    assert_match(/Completed task #3/, out)
    tasks = read_category_tasks('general')

    tasks.each { |t| assert_equal 'done', t['status'] }
  end

  def test_mark_mixed_toggle
    init!
    run_todo!('add', 'Active task')
    run_todo!('add', 'Done task')
    run_todo!('mark', '2')
    out = run_todo!('mark', '1', '2')

    assert_match(/Completed task #1/, out)
    assert_match(/Reopened task #2/, out)
    tasks = read_category_tasks('general')
    done_task = tasks.find { |t| t['id'] == 1 }
    reopened_task = tasks.find { |t| t['id'] == 2 }

    assert_equal 'done', done_task['status']
    assert_equal 'pending', reopened_task['status']
  end

  def test_mark_skips_invalid_id
    init!
    run_todo!('add', 'Valid task')
    out, stderr, code = run_todo('mark', '1', '999')

    assert_equal 0, code
    assert_match(/Completed task #1/, out)
    assert_match(/not found/, stderr)
  end

  def test_mark_alias_m
    init!
    run_todo!('add', 'Quick task')
    out = run_todo!('m', '1')

    assert_match(/Completed task #1/, out)
  end

  def test_mark_alias_d_removed
    init!
    run_todo!('add', 'Quick task')
    _out, stderr, code = run_todo('d', '1')

    refute_equal 0, code
    assert_match(/unknown command/i, stderr)
  end

  def test_mark_alias_u_removed
    init!
    run_todo!('add', 'Quick task')
    _out, stderr, code = run_todo('u', '1')

    refute_equal 0, code
    assert_match(/unknown command/i, stderr)
  end

  def test_mark_help_flag
    init!
    out = run_todo!('mark', '-h')

    assert_match(/toggle/i, out)
    assert_match(/--category/, out)
    assert_match(/--tag/, out)
  end

  def test_mark_no_args_errors_non_tty
    init!
    run_todo!('add', 'Task')
    _out, _stderr, code = run_todo('mark')

    refute_equal 0, code
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

  def test_list_help_shows_from_to
    init!
    out = run_todo!('list', '-h')

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

  # ── Interactive fallback (non-TTY) ───────────────────────────────────
  # In test env, $stdin is StringIO (not a TTY), so picker never activates.
  # These tests verify that commands without args produce correct errors.

  def test_edit_no_args_errors_non_tty
    init!
    run_todo!('add', 'Task')
    _out, stderr, code = run_todo('edit')

    refute_equal 0, code
    assert_match(/task ID required/, stderr)
  end

  def test_delete_no_args_errors_non_tty
    init!
    run_todo!('add', 'Task')
    _out, stderr, code = run_todo('delete')

    refute_equal 0, code
    assert_match(/task ID required/, stderr)
  end

  def test_show_no_args_errors_non_tty
    init!
    run_todo!('add', 'Task')
    _out, stderr, code = run_todo('show')

    refute_equal 0, code
    assert_match(/task ID required/, stderr)
  end

  def test_add_no_args_errors_non_tty
    init!
    _out, stderr, code = run_todo('add')

    refute_equal 0, code
    assert_match(/description is required/, stderr)
  end

  # ── Interrupt (Ctrl+C) handling ──────────────────────────────────────

  def test_interrupt_during_command_exits_cleanly
    init!
    # Stub the Add module's run to raise Interrupt (simulates Ctrl+C mid-prompt)
    original_run = Todo::Commands::Add.method(:run)
    Todo::Commands::Add.define_singleton_method(:run) { |*| raise Interrupt }

    _out, _stderr, code = run_todo('add', 'something')

    assert_equal 130, code
  ensure
    Todo::Commands::Add.define_singleton_method(:run, original_run)
  end

  def test_interrupt_during_add_does_not_save_task
    init!
    # Stub the Add module's run to raise Interrupt (simulates Ctrl+C mid-prompt).
    # This avoids gum/fzf subprocess issues entirely.
    original_run = Todo::Commands::Add.method(:run)
    Todo::Commands::Add.define_singleton_method(:run) { |*| raise Interrupt }

    _out, _stderr, code = run_todo('add', 'something')

    assert_equal 130, code
    assert_equal [], read_category_tasks('general'), 'No task should be saved on Ctrl+C'
  ensure
    Todo::Commands::Add.define_singleton_method(:run, original_run)
  end

  # ── Error handling ──────────────────────────────────────────────────

  def test_commands_require_init
    FileUtils.rm_rf(@conf_dir)
    _out, stderr, code = run_todo('list')

    refute_equal 0, code
    assert_match(/init/, stderr)
  end

  def test_unknown_command_shows_error
    init!
    _out, stderr, code = run_todo('nonexistent')

    refute_equal 0, code
    assert_match(/unknown command/i, stderr)
  end

  # ── Delete confirmation ────────────────────────────────────────────

  def test_delete_force_skips_confirmation
    init!
    run_todo!('add', 'Force delete me')
    out = run_todo!('delete', '1', '--force')

    assert_match(/Deleted task #1/, out)
    assert_equal 0, read_category_tasks('general').length
  end

  def test_delete_force_short_flag
    init!
    run_todo!('add', 'Force delete me')
    out = run_todo!('delete', '1', '-f')

    assert_match(/Deleted task #1/, out)
    assert_equal 0, read_category_tasks('general').length
  end

  # ── List date filters (absorbed from history) ──────────────────────

  def test_list_from_to_filters_by_date
    init!
    run_todo!('add', 'Old task')
    run_todo!('add', 'New task')
    run_todo!('mark', '1')
    run_todo!('mark', '2')
    # Both tasks completed today; filter with from=today should include them
    today = Date.today.to_s
    out = run_todo!('list', '--done-only', '--from', today)

    assert_match(/Old task/, out)
    assert_match(/New task/, out)
  end

  def test_list_from_excludes_earlier_tasks
    init!
    run_todo!('add', 'Old task')
    run_todo!('mark', '1')
    # Use a future date so current tasks are excluded
    out = run_todo!('list', '--done-only', '--from', '2099-01-01')

    refute_match(/Old task/, out)
  end

  # ── Search excludes done by default ────────────────────────────────

  def test_search_without_all_excludes_done
    init!
    run_todo!('add', 'Active findme')
    run_todo!('add', 'Done findme')
    run_todo!('mark', '2')
    out = run_todo!('search', 'findme')

    assert_match(/Active findme/, out)
    refute_match(/Done findme/, out)
  end

  # ── Saved task JSON does not contain category ──────────────────────

  def test_saved_task_json_has_no_category_key
    init!
    run_todo!('add', 'Test task', '-c', 'work')
    tasks = read_category_tasks('work')

    refute tasks.first.key?('category'), 'Task JSON should not contain category key'
  end
end
