#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require_relative '../../lib/agent_stats'

class TestAgentStats < Minitest::Test
  PLANNER = 'pi-01a0ff33-171d-75b4-bddf-1cc32f45d2c9'
  IMPLEMENTER = 'pi-01a0f55a-8c53-7300-bfc5-e34d07867898'

  def entry(time, role, calls: [], cost: 0.0, context: 0)
    content = calls.map { |name| { 'type' => 'toolCall', 'name' => name } }
    usage = role == 'assistant' ? { 'input' => context, 'cacheRead' => 0, 'cacheWrite' => 0, 'cost' => { 'total' => cost } } : nil
    JSON.generate('type' => 'message', 'timestamp' => time, 'message' => { 'role' => role, 'content' => content, 'usage' => usage })
  end

  def update(summary, author: PLANNER, created: 0, body: nil)
    { 'summary' => summary, 'author' => author, 'created' => created, 'body' => body }
  end

  def test_median_of_odd_and_even_lists
    assert_equal(2, AgentStats.median([3, 1, 2]))
    assert_in_delta(2.5, AgentStats.median([4, 1, 2, 3]))
    assert_nil(AgentStats.median([]))
  end

  def test_session_stats_counts_bookkeeping_only_turns
    lines = [
      JSON.generate('type' => 'session', 'id' => 'x'),
      entry('2026-10-02T10:00:00Z', 'user'),
      entry('2026-10-02T10:01:00Z', 'assistant', calls: %w[quest], cost: 0.5, context: 1000),
      entry('2026-10-02T10:02:00Z', 'assistant', calls: %w[quest read], cost: 1.0, context: 3000),
      entry('2026-10-02T10:03:00Z', 'assistant', calls: %w[cortex_update], cost: 0.5, context: 2000),
      entry('2026-10-02T10:10:00Z', 'assistant', cost: 1.0, context: 2500),
      'not json'
    ]
    stats = AgentStats.session_stats(lines)

    assert_equal(4, stats[:turns])
    assert_equal(2, stats[:bookkeeping_turns])
    assert_equal(4, stats[:tool_calls])
    assert_in_delta(3.0, stats[:cost])
    assert_equal(3000, stats[:peak_context])
    assert_in_delta(10.0, stats[:minutes])
  end

  def test_session_roles_from_plan_updates
    updates = [
      update('plan written', created: 1),
      update('status → open', author: 'kalindudc', created: 2),
      update('task 1: done', author: IMPLEMENTER, created: 3),
      update('status → review', author: IMPLEMENTER, created: 4)
    ]
    roles = AgentStats.session_roles(updates)

    assert_equal('01a0ff33-171d-75b4-bddf-1cc32f45d2c9', roles[:planning])
    assert_equal('01a0f55a-8c53-7300-bfc5-e34d07867898', roles[:implementing])
  end

  def test_session_roles_skip_implementer_when_same_session_planned
    updates = [update('plan written'), update('status → review')]

    assert_nil(AgentStats.session_roles(updates)[:implementing])
  end

  def test_deviation_ignores_explicit_none
    assert(AgentStats.deviation?(update('task 2: x', body: 'Deviation: used a shim')))
    refute(AgentStats.deviation?(update('ready for review', body: 'Deviations: none')))
    refute(AgentStats.deviation?(update('task 3: no deviations')))
  end

  def test_minutes_to_open_measures_plan_written_to_first_open
    updates = [
      update('status → open', author: 'kalindudc', created: 10 * 60_000),
      update('plan written', created: 0)
    ]

    assert_in_delta(10.0, AgentStats.minutes_to_open(updates))
    assert_nil(AgentStats.minutes_to_open([update('plan written')]))
  end

  def test_report_renders_a_markdown_table
    plans = [{ 'updates' => [update('plan written'), update('status → open', created: 60_000)] }]
    sessions = { planning: [{ turns: 10, bookkeeping_turns: 2, tool_calls: 5, cost: 1.0, peak_context: 100, minutes: 3.0 }], implementing: [] }
    text = AgentStats.report(plans, sessions)

    assert_includes(text, '| Bookkeeping-only turns | 20% | n/a |')
    assert_includes(text, '| Median `plan written` to `open` | 1 min | |')
  end
end
