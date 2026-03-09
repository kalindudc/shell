#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'
require_relative '../../lib/todo/interactive'

class TestInteractive < Minitest::Test
  I = Todo::Interactive

  def setup
    @dir = Dir.mktmpdir('todo_int_test')
    @store = Todo::Store.new(@dir)
    @store.init!
  end

  def teardown
    FileUtils.rm_rf(@dir)
    I.reset_cache!
  end

  # ── TTY guards (all methods return nil/[] when not TTY) ────────────

  def test_select_returns_nil_when_not_tty
    old_stdin = $stdin
    $stdin = StringIO.new

    assert_nil I.select(store: @store, source: :active, prompt: 'Select> ')
  ensure
    $stdin = old_stdin
  end

  def test_multi_toggle_returns_empty_when_not_tty
    old_stdin = $stdin
    $stdin = StringIO.new

    assert_equal [], I.multi_toggle(store: @store, prompt: 'Mark> ')
  ensure
    $stdin = old_stdin
  end

  def test_search_returns_nil_when_not_tty
    old_stdin = $stdin
    $stdin = StringIO.new

    assert_nil I.search(store: @store, prompt: 'Search> ')
  ensure
    $stdin = old_stdin
  end

  def test_input_returns_nil_when_not_tty
    old_stdin = $stdin
    $stdin = StringIO.new

    assert_nil I.input('Test')
  ensure
    $stdin = old_stdin
  end

  def test_filter_returns_nil_when_not_tty
    old_stdin = $stdin
    $stdin = StringIO.new

    assert_nil I.filter(%w[a b c], prompt: 'Pick> ')
  ensure
    $stdin = old_stdin
  end

  def test_confirm_returns_default_when_not_tty
    old_stdin = $stdin
    $stdin = StringIO.new

    refute I.confirm('Sure?', default: false)
    assert I.confirm('Sure?', default: true)
  ensure
    $stdin = old_stdin
  end

  # ── fallback_input ─────────────────────────────────────────────────

  def test_fallback_input_returns_user_input
    old_stdin = $stdin
    old_stdout = $stdout
    input = StringIO.new("hello\n")
    input.define_singleton_method(:tty?) { true }
    $stdin = input
    $stdout = StringIO.new

    assert_equal 'hello', I.fallback_input('Test')
  ensure
    $stdin = old_stdin
    $stdout = old_stdout
  end

  def test_fallback_input_returns_default_on_empty
    old_stdin = $stdin
    old_stdout = $stdout
    input = StringIO.new("\n")
    input.define_singleton_method(:tty?) { true }
    $stdin = input
    $stdout = StringIO.new

    assert_equal 'fallback', I.fallback_input('Test', default: 'fallback')
  ensure
    $stdin = old_stdin
    $stdout = old_stdout
  end

  def test_fallback_input_propagates_interrupt
    old_stdin = $stdin
    old_stdout = $stdout
    input = StringIO.new
    input.define_singleton_method(:tty?) { true }
    input.define_singleton_method(:gets) { raise Interrupt }
    $stdin = input
    $stdout = StringIO.new

    assert_raises(Interrupt) { I.fallback_input('Test') }
  ensure
    $stdin = old_stdin
    $stdout = old_stdout
  end

  # ── fallback_confirm ───────────────────────────────────────────────

  def test_fallback_confirm_yes
    old_stdin = $stdin
    old_stdout = $stdout
    input = StringIO.new("y\n")
    input.define_singleton_method(:tty?) { true }
    $stdin = input
    $stdout = StringIO.new

    assert I.fallback_confirm('Sure?')
  ensure
    $stdin = old_stdin
    $stdout = old_stdout
  end

  def test_fallback_confirm_no
    old_stdin = $stdin
    old_stdout = $stdout
    input = StringIO.new("n\n")
    input.define_singleton_method(:tty?) { true }
    $stdin = input
    $stdout = StringIO.new

    refute I.fallback_confirm('Sure?')
  ensure
    $stdin = old_stdin
    $stdout = old_stdout
  end

  def test_fallback_confirm_default_on_empty
    old_stdin = $stdin
    old_stdout = $stdout
    input = StringIO.new("\n")
    input.define_singleton_method(:tty?) { true }
    $stdin = input
    $stdout = StringIO.new

    assert I.fallback_confirm('Sure?', default: true)
  ensure
    $stdin = old_stdin
    $stdout = old_stdout
  end

  # ── build_toggled_display ──────────────────────────────────────────

  def test_build_toggled_display_flips_checkbox
    lines = "  [ ] 1    [   5]  Buy milk         general\tBuy milk\n  [x] 2    [   0]  Done task        work\tDone task"
    toggled = Set.new([1, 2])
    result = I.build_toggled_display(lines, toggled)

    result_lines = result.split("\n")

    assert_includes result_lines[0], '[x]'
    assert_includes result_lines[1], '[ ]'
  end

  def test_build_toggled_display_no_toggle
    lines = "  [ ] 1    [   5]  Buy milk         general\tBuy milk"
    toggled = Set.new
    result = I.build_toggled_display(lines, toggled)

    assert_includes result, '[ ]'
  end

  # ── fzf_task_lines ──────────────────────────────────────────────────

  def test_fzf_task_lines_generates_lines
    @store.save_task({
                       'id' => 1, 'description' => 'Test task', 'category' => 'general',
                       'priority' => 5, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store)

    assert_includes result, '1'
    assert_includes result, 'Test task'
    assert_includes result, '[ ]'
  end

  def test_fzf_task_lines_filters_by_category
    @store.ensure_category('work')
    @store.save_task({
                       'id' => 1, 'description' => 'General task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Work task', 'category' => 'work',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'work')

    result = I.fzf_task_lines(@store, filter_cat: 'work')

    refute_includes result, 'General task'
    assert_includes result, 'Work task'
  end

  def test_fzf_task_lines_sorted_by_task_sort_key
    @store.save_task({
                       'id' => 1, 'description' => 'Low pri', 'category' => 'general',
                       'priority' => 9, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'High pri', 'category' => 'general',
                       'priority' => 0, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store)
    lines = result.strip.split("\n")

    # High priority (0) should come before low priority (9)
    assert_match(/High pri/, lines[0])
    assert_match(/Low pri/, lines[1])
  end

  # ── require_task_id ────────────────────────────────────────────────

  def test_require_task_id_returns_explicit_id
    result = I.require_task_id(['5'], store: @store)

    assert_equal 5, result
  end

  def test_require_task_id_exits_on_empty_non_tty
    old_stdin = $stdin
    old_stderr = $stderr
    $stdin = StringIO.new
    $stderr = StringIO.new

    assert_raises(SystemExit) { I.require_task_id([], store: @store) }
  ensure
    $stdin = old_stdin
    $stderr = old_stderr
  end

  # ── fzf integration (requires fzf installed) ────────────────────────

  def test_fzf_search_finds_full_description
    skip 'fzf not available' unless system('command -v fzf > /dev/null 2>&1')

    long_desc = 'This is a very long description that would normally be truncated in a narrow view'
    @store.save_task({
                       'id' => 1, 'description' => long_desc, 'category' => 'general',
                       'priority' => 5, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => %w[important]
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Short task', 'category' => 'general',
                       'priority' => 3, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')

    input = I.fzf_task_lines(@store)

    # Use the same fzf flags as Interactive.search (minus --height/--layout/--preview)
    # This validates that our fzf data format + flags allow searching full descriptions
    selected, status = Open3.capture2(
      *I.fzf_base_args,
      '--filter=normally be truncated',
      stdin_data: input
    )

    assert_predicate status, :success?, 'fzf should find a match for text in the full description'
    assert_equal 1, I.extract_task_id(selected)
  end

  def test_fzf_search_finds_by_tag
    skip 'fzf not available' unless system('command -v fzf > /dev/null 2>&1')

    @store.save_task({
                       'id' => 1, 'description' => 'Tagged task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => %w[deploy]
                     }, 'general')

    input = I.fzf_task_lines(@store)

    selected, status = Open3.capture2(
      *I.fzf_base_args,
      '--filter=deploy',
      stdin_data: input
    )

    assert_predicate status, :success?, 'fzf should find a match for tag text'
    assert_equal 1, I.extract_task_id(selected)
  end

  def test_fzf_search_finds_by_category
    skip 'fzf not available' unless system('command -v fzf > /dev/null 2>&1')

    @store.ensure_category('work')
    @store.save_task({
                       'id' => 1, 'description' => 'Work task', 'category' => 'work',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'work')

    input = I.fzf_task_lines(@store)

    selected, status = Open3.capture2(
      *I.fzf_base_args,
      '--filter=work',
      stdin_data: input
    )

    assert_predicate status, :success?, 'fzf should find a match for category text'
    assert_equal 1, I.extract_task_id(selected)
  end

  def test_fzf_columns_aligned_across_rows
    skip 'fzf not available' unless system('command -v fzf > /dev/null 2>&1')

    @store.save_task({
                       'id' => 1, 'description' => 'Short', 'category' => 'general',
                       'priority' => 5, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'A much longer description here', 'category' => 'general',
                       'priority' => nil, 'status' => 'done', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => %w[tag1]
                     }, 'general')

    input = I.fzf_task_lines(@store, include_done: true)
    lines = input.split("\n")

    assert_equal 2, lines.length

    # The visible part (before tab) should have aligned columns
    # Description starts at the same position for all lines
    visible_parts = lines.map { |l| l.split("\t").first }
    desc_positions = visible_parts.map { |v| v.index(/\]\s{2}/) }

    # All descriptions should start at the same column
    assert_equal 1, desc_positions.uniq.length,
                 "Description columns should be aligned: #{desc_positions}"
  end

  # ── browse (TTY guard) ──────────────────────────────────────────────

  def test_browse_returns_nil_when_not_tty
    old_stdin = $stdin
    $stdin = StringIO.new

    assert_nil I.browse(store: @store)
  ensure
    $stdin = old_stdin
  end

  def test_fzf_task_lines_filters_by_priority
    @store.save_task({
                       'id' => 1, 'description' => 'High pri', 'category' => 'general',
                       'priority' => 0, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Low pri', 'category' => 'general',
                       'priority' => 500, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store, filter_pri: '0')

    assert_includes result, 'High pri'
    refute_includes result, 'Low pri'
  end

  def test_fzf_task_lines_filters_by_tag
    @store.save_task({
                       'id' => 1, 'description' => 'Tagged task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => %w[urgent]
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Untagged task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store, filter_tag: 'urgent')

    assert_includes result, 'Tagged task'
    refute_includes result, 'Untagged task'
  end

  def test_fzf_task_lines_excludes_done_by_default
    @store.save_task({
                       'id' => 1, 'description' => 'Active task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Done task', 'category' => 'general',
                       'priority' => nil, 'status' => 'done', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'completed' => '2026-01-02', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store)

    assert_includes result, 'Active task'
    refute_includes result, 'Done task'
  end

  def test_fzf_task_lines_includes_done_when_requested
    @store.save_task({
                       'id' => 1, 'description' => 'Active task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Done task', 'category' => 'general',
                       'priority' => nil, 'status' => 'done', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'completed' => '2026-01-02', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store, include_done: true)

    assert_includes result, 'Active task'
    assert_includes result, 'Done task'
  end

  def test_fzf_task_lines_done_only
    @store.save_task({
                       'id' => 1, 'description' => 'Active task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Done task', 'category' => 'general',
                       'priority' => nil, 'status' => 'done', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'completed' => '2026-01-02', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store, done_only: true)

    refute_includes result, 'Active task'
    assert_includes result, 'Done task'
  end

  def test_fzf_task_lines_date_filter
    @store.save_task({
                       'id' => 1, 'description' => 'Old task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2025-01-01',
                       'modified' => '2025-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'New task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-06-01',
                       'modified' => '2026-06-01', 'tags' => []
                     }, 'general')

    result = I.fzf_task_lines(@store, date_from: '2026-01-01')

    refute_includes result, 'Old task'
    assert_includes result, 'New task'
  end

  def test_fzf_task_lines_empty_when_no_tasks
    result = I.fzf_task_lines(@store)

    assert_empty result
  end

  # ── fzf integration for browse (requires fzf installed) ────────────

  def test_fzf_browse_lines_searchable_by_description
    skip 'fzf not available' unless system('command -v fzf > /dev/null 2>&1')

    long_desc = 'This is a very long description that gets truncated in browse view'
    @store.save_task({
                       'id' => 1, 'description' => long_desc, 'category' => 'general',
                       'priority' => 5, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Short task', 'category' => 'general',
                       'priority' => 3, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')

    input = I.fzf_task_lines(@store)

    selected, status = Open3.capture2(
      *I.fzf_base_args,
      '--filter=truncated in browse',
      stdin_data: input
    )

    assert_predicate status, :success?, 'fzf should find match in full description via browse lines'
    assert_equal 1, I.extract_task_id(selected)
  end

  def test_fzf_browse_lines_searchable_by_tag
    skip 'fzf not available' unless system('command -v fzf > /dev/null 2>&1')

    @store.save_task({
                       'id' => 1, 'description' => 'Deploy app', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => %w[production]
                     }, 'general')

    input = I.fzf_task_lines(@store)

    selected, status = Open3.capture2(
      *I.fzf_base_args,
      '--filter=production',
      stdin_data: input
    )

    assert_predicate status, :success?, 'fzf should find match by tag in browse lines'
    assert_equal 1, I.extract_task_id(selected)
  end

  # ── browse toggle: include_done changes task list ───────────────────

  def test_fzf_task_lines_toggle_includes_done_tasks
    @store.save_task({
                       'id' => 1, 'description' => 'Active task', 'category' => 'general',
                       'priority' => nil, 'status' => 'pending', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'tags' => []
                     }, 'general')
    @store.save_task({
                       'id' => 2, 'description' => 'Completed task', 'category' => 'general',
                       'priority' => nil, 'status' => 'done', 'created' => '2026-01-01',
                       'modified' => '2026-01-01', 'completed' => '2026-01-02', 'tags' => []
                     }, 'general')

    # Default: only active
    active_lines = I.fzf_task_lines(@store, include_done: false)

    assert_includes active_lines, 'Active task'
    refute_includes active_lines, 'Completed task'

    # After toggle: includes done
    all_lines = I.fzf_task_lines(@store, include_done: true)

    assert_includes all_lines, 'Active task'
    assert_includes all_lines, 'Completed task'
  end

  # ── Cache reset ────────────────────────────────────────────────────

  def test_reset_cache
    I.instance_variable_set(:@fzf_available, true)
    I.reset_cache!

    assert_nil I.instance_variable_get(:@fzf_available)
  end
end
