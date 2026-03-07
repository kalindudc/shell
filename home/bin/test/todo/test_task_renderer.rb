#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'
require_relative '../../lib/todo/task_renderer'

class TestTaskRenderer < Minitest::Test
  TR = Todo::TaskRenderer

  def make_task(overrides = {})
    {
      'id' => 1,
      'description' => 'Buy groceries',
      'category' => 'general',
      'priority' => 5,
      'status' => 'pending',
      'created' => '2026-01-15',
      'modified' => '2026-01-15',
      'tags' => %w[food shopping]
    }.merge(overrides)
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  # ── render_line ────────────────────────────────────────────────────

  def test_render_line_includes_checkbox_pending
    line = TR.render_line(make_task, config: {})

    assert_includes line, '[ ]'
  end

  def test_render_line_includes_checkbox_done
    line = TR.render_line(make_task('status' => 'done'), config: {})

    assert_includes line, '[x]'
  end

  def test_render_line_includes_id
    line = TR.render_line(make_task, config: {})

    assert_includes line, '1'
  end

  def test_render_line_includes_priority_badge
    line = TR.render_line(make_task('priority' => 0), config: {})

    assert_includes line, '[   0]'
  end

  def test_render_line_nil_priority_no_badge
    line = TR.render_line(make_task('priority' => nil), config: {})
    # Badge area should be blank spaces, not [N] format
    # The line still has [ ] checkbox, but no [   N] priority badge

    refute_match(/\[\s*\d+\]/, line)
  end

  def test_render_line_includes_description
    line = TR.render_line(make_task, config: {})

    assert_includes line, 'Buy groceries'
  end

  def test_render_line_includes_category
    line = TR.render_line(make_task, config: {})

    assert_includes line, 'general'
  end

  def test_render_line_includes_tags
    line = TR.render_line(make_task, config: {})

    assert_includes line, '#food'
    assert_includes line, '#shopping'
  end

  def test_render_line_truncates_long_description
    long_desc = 'A' * 50
    line = TR.render_line(make_task('description' => long_desc), config: { 'desc_max' => 10 })

    assert_includes line, 'AAAAAAA...'
    refute_includes line, 'A' * 50
  end

  def test_render_line_respects_desc_max_config
    line_short = TR.render_line(make_task('description' => 'Short'), config: { 'desc_max' => 10 })

    assert_includes line_short, 'Short'
  end

  # ── render_plain ───────────────────────────────────────────────────

  def test_render_plain_tab_delimited
    line = TR.render_plain(make_task, config: {})
    fields = line.split("\t")

    assert_operator fields.length, :>=, 5
    assert_equal '1', fields[0]
    assert_equal '[ ]', fields[1]
    assert_equal '5', fields[2]
    assert_equal 'Buy groceries', fields[3]
    assert_equal 'general', fields[4]
  end

  def test_render_plain_done_checkbox
    line = TR.render_plain(make_task('status' => 'done'), config: {})
    fields = line.split("\t")

    assert_equal '[x]', fields[1]
  end

  def test_render_plain_nil_priority
    line = TR.render_plain(make_task('priority' => nil), config: {})
    fields = line.split("\t")

    assert_equal '', fields[2]
  end

  def test_render_plain_tags_comma_separated
    line = TR.render_plain(make_task, config: {})
    fields = line.split("\t")

    assert_equal 'food,shopping', fields[5]
  end

  def test_render_plain_no_ansi
    line = TR.render_plain(make_task, config: {})

    refute_includes line, "\033["
  end

  def test_render_plain_preserves_full_description
    long_desc = 'A' * 50
    line = TR.render_plain(make_task('description' => long_desc), config: { 'desc_max' => 10 })
    fields = line.split("\t")

    assert_equal long_desc, fields[3]
  end

  # ── render_fzf ─────────────────────────────────────────────────────

  def test_render_fzf_truncates_description_in_visible_part
    long_desc = 'A' * 50
    line = TR.render_fzf(make_task('description' => long_desc), config: { 'desc_max' => 10 })
    visible = line.split("\t").first

    assert_includes visible, 'AAAAAAA...'
    refute_includes visible, 'A' * 50
  end

  def test_render_fzf_appends_full_description_after_tab
    long_desc = 'A' * 50
    line = TR.render_fzf(make_task('description' => long_desc), config: { 'desc_max' => 10 })
    parts = line.split("\t")

    assert_equal 2, parts.length
    assert_equal long_desc, parts[1]
  end

  def test_render_fzf_includes_priority_badge
    line = TR.render_fzf(make_task('priority' => 5), config: {})

    assert_includes line, '[   5]'
  end

  def test_render_fzf_nil_priority_no_badge
    line = TR.render_fzf(make_task('priority' => nil), config: {})
    visible = line.split("\t").first

    refute_match(/\[\s*\d+\]/, visible)
  end

  def test_render_fzf_includes_category_and_tags
    line = TR.render_fzf(make_task, config: {})

    assert_includes line, 'general'
    assert_includes line, '#food'
    assert_includes line, '#shopping'
  end

  def test_render_fzf_no_ansi
    line = TR.render_fzf(make_task, config: {})

    refute_includes line, "\033["
  end

  def test_render_fzf_id_extractable
    line = TR.render_fzf(make_task('id' => 42), config: {})
    match = line.match(/\[.\]\s+(\d+)/)

    assert match
    assert_equal 42, match[1].to_i
  end

  # ── render_header ──────────────────────────────────────────────────

  def test_render_header_includes_column_names
    header = TR.render_header(config: {})

    assert_includes header, 'ID'
    assert_includes header, 'Pri'
    assert_includes header, 'Description'
    assert_includes header, 'Category'
    assert_includes header, 'Tags'
  end

  # ── render_footer ──────────────────────────────────────────────────

  def test_render_footer_singular
    footer = TR.render_footer(1, 'tasks')

    assert_includes footer, '1 task'
    refute_includes footer, '1 tasks'
  end

  def test_render_footer_plural
    footer = TR.render_footer(2, 'tasks')

    assert_includes footer, '2 tasks'
  end

  # ── task_sort_key ──────────────────────────────────────────────────

  def test_task_sort_key_pending_before_done
    pending_key = TR.task_sort_key(make_task('status' => 'pending'))
    done_key = TR.task_sort_key(make_task('status' => 'done'))

    assert_equal(-1, pending_key <=> done_key)
  end

  def test_task_sort_key_lower_priority_first
    low = TR.task_sort_key(make_task('priority' => 0))
    high = TR.task_sort_key(make_task('priority' => 9))

    assert_equal(-1, low <=> high)
  end

  def test_task_sort_key_nil_priority_after_numbered
    numbered = TR.task_sort_key(make_task('priority' => 9999))
    nil_pri = TR.task_sort_key(make_task('priority' => nil))

    assert_equal(-1, numbered <=> nil_pri)
  end

  def test_task_sort_key_earlier_date_first
    earlier = TR.task_sort_key(make_task('created' => '2026-01-01'))
    later = TR.task_sort_key(make_task('created' => '2026-06-01'))

    assert_equal(-1, earlier <=> later)
  end

  # ── NO_COLOR ───────────────────────────────────────────────────────

  def test_render_line_no_color_suppresses_ansi
    # NO_COLOR is set in test env, so ANSI should be stripped
    line = TR.render_line(make_task, config: {})

    refute_includes line, "\033[" if Todo::Formatter::NO_COLOR
  end
end
