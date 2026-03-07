#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../lib/todo/arg_parser'

class TestArgParser < Minitest::Test
  # ── Simple definitions for testing ─────────────────────────────────

  ADD_DEF = {
    name: 'add', aliases: %w[a],
    description: 'Add a new task',
    positional: { name: :description, type: :text, required: true },
    options: [
      { long: '--category', short: '-c', arg: :category },
      { long: '--priority', short: '-p', arg: :integer, range: 0..9999 },
      { long: '--tag', short: '-t', arg: :text, repeat: true }
    ]
  }.freeze

  MARK_DEF = {
    name: 'mark', aliases: %w[m],
    description: 'Toggle task status',
    positional: { name: :task_ids, type: :integer, repeat: true },
    options: [
      { long: '--category', short: '-c', arg: :category },
      { long: '--tag', short: '-t', arg: :text }
    ]
  }.freeze

  LIST_DEF = {
    name: 'list', aliases: %w[l ls h],
    description: 'List tasks',
    options: [
      { long: '--category', short: '-c', arg: :category },
      { long: '--all', short: '-a' },
      { long: '--plain', short: '-P' },
      { long: '--done-only' }
    ]
  }.freeze

  INIT_DEF = {
    name: 'init',
    description: 'Initialize configuration'
  }.freeze

  # ── Positional arguments ───────────────────────────────────────────

  def test_parse_required_positional
    result = Todo::ArgParser.parse(ADD_DEF, ['Buy groceries'])

    assert_nil result[:error]
    assert_equal 'Buy groceries', result[:description]
  end

  def test_parse_missing_required_positional_returns_error
    result = Todo::ArgParser.parse(ADD_DEF, [])

    assert_match(/required/, result[:error])
  end

  def test_parse_optional_positional_no_error_when_missing
    optional_def = {
      name: 'search',
      description: 'Search tasks',
      positional: { name: :term, type: :text },
      options: [{ long: '--all', short: '-a' }]
    }
    result = Todo::ArgParser.parse(optional_def, [])

    assert_nil result[:error]
    assert_nil result[:term]
  end

  def test_parse_variadic_positional_collects_integers
    result = Todo::ArgParser.parse(MARK_DEF, %w[1 2 3])

    assert_nil result[:error]
    assert_equal [1, 2, 3], result[:task_ids]
  end

  def test_parse_variadic_positional_empty_array_when_none
    result = Todo::ArgParser.parse(MARK_DEF, [])

    assert_nil result[:error]
    assert_equal [], result[:task_ids]
  end

  def test_parse_variadic_integer_rejects_non_numeric
    result = Todo::ArgParser.parse(MARK_DEF, %w[1 abc 3])

    assert_match(/invalid.*integer/i, result[:error])
  end

  # ── Options ────────────────────────────────────────────────────────

  def test_parse_long_option
    result = Todo::ArgParser.parse(ADD_DEF, ['Task', '--category', 'work'])

    assert_nil result[:error]
    assert_equal 'work', result[:category]
  end

  def test_parse_short_option
    result = Todo::ArgParser.parse(ADD_DEF, ['Task', '-c', 'work'])

    assert_nil result[:error]
    assert_equal 'work', result[:category]
  end

  def test_parse_repeat_option_collects_values
    result = Todo::ArgParser.parse(ADD_DEF, ['Task', '-t', 'urgent', '-t', 'deploy'])

    assert_nil result[:error]
    assert_equal %w[urgent deploy], result[:tag]
  end

  def test_parse_flag_option_no_arg
    result = Todo::ArgParser.parse(LIST_DEF, ['--all'])

    assert_nil result[:error]
    assert result[:all]
  end

  def test_parse_flag_short
    result = Todo::ArgParser.parse(LIST_DEF, ['-a'])

    assert_nil result[:error]
    assert result[:all]
  end

  def test_parse_multiple_flags
    result = Todo::ArgParser.parse(LIST_DEF, ['--all', '--plain', '--done-only'])

    assert_nil result[:error]
    assert result[:all]
    assert result[:plain]
    assert result[:done_only]
  end

  # ── Integer type + range validation ────────────────────────────────

  def test_parse_integer_option_valid
    result = Todo::ArgParser.parse(ADD_DEF, ['Task', '-p', '5'])

    assert_nil result[:error]
    assert_equal 5, result[:priority]
  end

  def test_parse_integer_option_out_of_range
    result = Todo::ArgParser.parse(ADD_DEF, ['Task', '-p', '10000'])

    assert_match(/range/, result[:error])
  end

  def test_parse_integer_option_non_numeric
    result = Todo::ArgParser.parse(ADD_DEF, ['Task', '-p', 'abc'])

    assert_match(/integer/i, result[:error])
  end

  # ── Help detection ─────────────────────────────────────────────────

  def test_parse_help_long
    result = Todo::ArgParser.parse(ADD_DEF, ['--help'])

    assert result[:help]
  end

  def test_parse_help_short
    result = Todo::ArgParser.parse(ADD_DEF, ['-h'])

    assert result[:help]
  end

  # ── Unknown args ───────────────────────────────────────────────────

  def test_parse_unknown_option_returns_error
    result = Todo::ArgParser.parse(LIST_DEF, ['--unknown'])

    assert_match(/unknown/i, result[:error])
  end

  def test_parse_extra_positional_returns_error
    result = Todo::ArgParser.parse(ADD_DEF, %w[Task extra])

    assert_match(/unknown/i, result[:error])
  end

  # ── No args definition (init) ──────────────────────────────────────

  def test_parse_no_args_definition
    result = Todo::ArgParser.parse(INIT_DEF, [])

    assert_nil result[:error]
  end

  def test_parse_no_args_definition_rejects_unknown
    result = Todo::ArgParser.parse(INIT_DEF, ['--foo'])

    assert_match(/unknown/i, result[:error])
  end

  # ── Mixed positional and options ───────────────────────────────────

  def test_parse_positional_with_options_interleaved
    result = Todo::ArgParser.parse(ADD_DEF, ['-c', 'work', 'Task desc', '-p', '3'])

    assert_nil result[:error]
    assert_equal 'Task desc', result[:description]
    assert_equal 'work', result[:category]
    assert_equal 3, result[:priority]
  end

  def test_parse_variadic_with_options_interleaved
    result = Todo::ArgParser.parse(MARK_DEF, ['1', '-c', 'work', '2', '3'])

    assert_nil result[:error]
    assert_equal [1, 2, 3], result[:task_ids]
    assert_equal 'work', result[:category]
  end

  # ── Option key normalization ───────────────────────────────────────

  def test_option_key_strips_dashes
    result = Todo::ArgParser.parse(LIST_DEF, ['--done-only'])

    assert_nil result[:error]
    assert result[:done_only]
  end
end
