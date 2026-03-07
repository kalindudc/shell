#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../lib/todo/cli'

class TestCompletions < Minitest::Test
  def generate
    Todo::Completions::Zsh.generate(Todo::CLI::COMMANDS)
  end

  # ── Basic structure ────────────────────────────────────────────────

  def test_output_starts_with_compdef
    output = generate

    assert_match(/\A#compdef todo/, output)
  end

  def test_output_contains_todo_function
    output = generate

    assert_includes output, '_todo()'
  end

  # ── Command names ──────────────────────────────────────────────────

  def test_contains_expected_command_names
    output = generate

    %w[add list mark edit delete search category show init].each do |cmd|
      assert_includes output, "'#{cmd}:", "Expected completions to include #{cmd}"
    end
  end

  def test_does_not_contain_history
    output = generate

    refute_match(/'history:/, output)
  end

  def test_contains_help
    output = generate

    assert_includes output, "'help:Show help information'"
  end

  # ── Options per command ────────────────────────────────────────────

  def test_list_has_expected_options
    output = generate

    assert_includes output, '--category'
    assert_includes output, '--all'
    assert_includes output, '--plain'
    assert_includes output, '--done-only'
    assert_includes output, '--from'
    assert_includes output, '--to'
  end

  def test_mark_has_options
    output = generate

    assert_includes output, '--category'
    assert_includes output, '--tag'
  end

  def test_delete_has_force_option
    output = generate

    assert_includes output, '--force'
  end

  # ── Subcommands ────────────────────────────────────────────────────

  def test_category_has_subcommands
    output = generate

    assert_includes output, 'subcmds'
    assert_match(/'list:/, output)
    assert_match(/'add:/, output)
    assert_match(/'delete:/, output)
  end

  # ── Aliases ────────────────────────────────────────────────────────

  def test_list_aliases_include_h
    output = generate

    assert_match(/list.*alias.*h/, output)
  end

  def test_mark_alias_m_only
    output = generate
    # Find the mark line in the completions
    mark_line = output.lines.find { |l| l.include?("'mark:") }

    assert mark_line, 'Expected mark in completions'
    assert_includes mark_line, 'alias: m'
    refute_includes mark_line, 'alias: d'
    refute_includes mark_line, 'alias: u'
  end

  # ── DEFINITION changes reflected ───────────────────────────────────

  def test_definition_changes_reflected
    # Verify the completions are generated from DEFINITION, not COMPLETIONS
    # by checking that delete has --force (only in DEFINITION, not old COMPLETIONS)
    output = generate

    assert_includes output, '--force'
  end
end
