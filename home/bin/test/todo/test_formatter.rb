#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'
require_relative '../../lib/todo/formatter'

class TestFormatter < Minitest::Test
  F = Todo::Formatter

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

  # ── Color helpers ───────────────────────────────────────────────────

  def test_colorize_with_no_color
    # NO_COLOR is set in test env, so colors should be stripped
    if F::NO_COLOR
      assert_equal 'hello', F.colorize('0;31', 'hello')
    else
      assert_includes F.colorize('0;31', 'hello'), "\033["
    end
  end

  def test_c_bold_returns_string
    result = F.c_bold('test')

    assert_includes result, 'test'
  end

  def test_c_dim_returns_string
    result = F.c_dim('test')

    assert_includes result, 'test'
  end

  # ── Priority color ─────────────────────────────────────────────────

  def test_priority_color_critical
    assert_equal '1;31', F.priority_color(0)
    assert_equal '1;31', F.priority_color(9)
  end

  def test_priority_color_high
    assert_equal '1;33', F.priority_color(10)
    assert_equal '1;33', F.priority_color(99)
  end

  def test_priority_color_normal
    assert_equal '0;34', F.priority_color(100)
    assert_equal '0;34', F.priority_color(999)
  end

  def test_priority_color_low
    assert_nil F.priority_color(1000)
    assert_nil F.priority_color(9999)
  end

  def test_priority_color_nil
    assert_nil F.priority_color(nil)
  end

  # ── Truncation ─────────────────────────────────────────────────────

  def test_truncate_short_string
    assert_equal 'hello', F.truncate('hello', 10)
  end

  def test_truncate_exact_length
    assert_equal '1234567890', F.truncate('1234567890', 10)
  end

  def test_truncate_long_string
    assert_equal '1234567...', F.truncate('1234567890abc', 10)
  end

  def test_desc_max_from_config
    assert_equal 32, F.desc_max({ 'desc_max' => 32 })
    assert_equal 50, F.desc_max({ 'desc_max' => 50 })
  end

  def test_desc_max_default
    assert_equal 32, F.desc_max({})
  end

  # ── Output helpers ──────────────────────────────────────────────────

  def test_fmt_task_line_outputs_checkbox
    config = { 'desc_max' => 20 }
    out = capture_stdout { F.fmt_task_line(1, 0, 'Test', 'cat', [], status: 'pending', config: config) }

    assert_includes out, '[ ]'
  end

  def test_fmt_task_line_done_checkbox
    config = { 'desc_max' => 20 }
    out = capture_stdout { F.fmt_task_line(1, 0, 'Test', 'cat', [], status: 'done', config: config) }

    assert_includes out, '[x]'
  end

  def test_fmt_header_outputs_column_names
    config = { 'desc_max' => 20 }
    out = capture_stdout { F.fmt_header('Category', 'Tags', config: config) }

    assert_includes out, 'ID'
    assert_includes out, 'Pri'
    assert_includes out, 'Description'
    assert_includes out, 'Category'
  end

  def test_fmt_footer_singular
    out = capture_stdout { F.fmt_footer(1, 'tasks') }

    assert_includes out, '1 task'
    refute_includes out, '1 tasks'
  end

  def test_fmt_footer_plural
    # Need to print some lines first to set max_line_width
    config = { 'desc_max' => 20 }
    out = capture_stdout do
      F.fmt_task_line(1, 0, 'T', '', [], config: config)
      F.fmt_footer(2, 'tasks')
    end

    assert_includes out, '2 tasks'
  end

  def test_print_subcmd_help_outputs_usage
    out = capture_stdout do
      F.print_subcmd_help('test', 'todo test [opts]', 'A test command',
                          [['--flag', 'A flag']], ['todo test --flag'])
    end

    assert_includes out, 'todo test [opts]'
    assert_includes out, '--flag'
    assert_includes out, 'A flag'
    assert_includes out, 'todo test --flag'
  end
end
