#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../../lib/journal'

class TestLedger < Minitest::Test
  TODAY = Date.new(2026, 1, 14) # a Wednesday
  NOW = Time.parse('2026-01-14T09:00:00-05:00')

  BODY = <<~MD
    # Journal: Wednesday, January 14, 2026
    ## Today's focus
    - Reply to Ada about the rollout ([thread](https://acme.slack.com/archives/C111/p1700000002000200?thread_ts=1700000001.000100&cid=C111)). (carried over since January 9)
    ## Needs my action
    - [ ] Reply to Ada about the rollout; she asked twice ([thread](https://acme.slack.com/archives/C111/p1700000001000100?thread_ts=1700000001.000100&cid=C111))
    - [ ] Review the cache PR ([PR](https://github.com/acme/app/pull/7)). (carried over since December 30)
    ### Waiting on others
    - Bob: the capacity numbers ([mail](https://mail.google.com/mail/u/0/#all/abc123)). (carried over since January 5)
    ### Cortex
    - Can be closed: @41 and @42, both shipped.
    ## What I did since the last journal
    - Shipped ([PR](https://github.com/acme/app/pull/1))
  MD

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, 'ledger.json')
  end

  def teardown = FileUtils.rm_rf(@dir)

  def ledger = Journal::Ledger.new(@path, today: TODAY)

  def seeded
    l = ledger
    l.seed(BODY, journal_date: TODAY, cortex_titles: { 41 => 'Ship the cache', 42 => 'Write the docs' }, now: NOW)
    l
  end

  def test_seed_dedupes_by_key_and_splits_cortex_bullets
    l = seeded
    assert_equal(['Reply to Ada about the rollout', 'Review the cache PR', 'Bob: the capacity numbers', '@41 Ship the cache',
                  '@42 Write the docs'], l.items.map { |i| i['title'] })
    assert_equal(%w[action review wait task task], l.items.map { |i| i['kind'] })
    assert_equal([[], [], [], [41], [42]], l.items.map { |i| i['cortex'] })
  end

  def test_seed_keeps_task_mentions_outside_cortex_as_references
    l = ledger
    l.seed("## Needs my action\n- [ ] Ping Ada about @41 ([thread](https://acme.slack.com/archives/C222/p1700000003000300))\n",
           journal_date: TODAY, now: NOW)
    assert_equal([[], ['@41']], [l.items[0]['keys'], l.items[0]['refs']])
    assert_equal({ 'new' => [2] }, l.upsert([{ 'key' => '@41', 'title' => '@41 Ship', 'kind' => 'task' }], now: NOW))
    assert_includes(l.known_keys, '@41')
  end

  def test_seed_keeps_carried_since_dates_across_a_year_boundary
    assert_equal(%w[2026-01-09 2025-12-30 2026-01-05], seeded.items.first(3).map { |i| i['first_seen'] })
  end

  def test_default_due_dates_skip_weekends_and_drive_overdue
    l = seeded
    v = l.view
    assert_equal([2, 1], v['overdue'].map { |i| i['id'] })
    assert_equal(Date.new(2026, 1, 12), l.due(l.find(1))) # Friday plus one business day
    assert_equal([3], v['waiting'].map { |i| i['id'] })
  end

  def test_apply_parses_a_mixed_reply
    l = seeded
    results = l.apply('done 1 J-4, drop 2 not mine; snooze 3 mon', now: NOW)
    assert_equal([%w[done done], %w[done done], %w[drop dropped], %w[snooze snoozed]], results.map { |r| [r['verb'], r['status']] })
    assert_equal([41], results[1]['cortex'])
    assert_equal('not mine', l.find(2)['close_note'])
    assert_equal('2026-01-19', l.find(3)['snooze_until'])
    assert_equal([5], l.view['backlog'].map { |i| i['id'] })
  end

  def test_closed_item_stays_closed_until_newer_activity
    l = seeded
    l.apply('done 2', now: NOW)
    key = 'https://github.com/acme/app/pull/7'
    assert_equal({ 'updated' => [2] }, l.upsert([{ 'url' => key, 'kind' => 'review', 'last_activity' => '2026-01-13T10:00:00Z' }], now: NOW))
    assert_equal('done', l.status(l.find(2)))
    report = l.upsert([{ 'url' => key, 'kind' => 'review', 'last_activity' => '2026-01-15T10:00:00Z', 'detail' => 'new push' }], now: NOW)
    assert_equal({ 'reopened' => [2] }, report)
    assert_equal('open', l.status(l.find(2)))
  end

  def test_reopen_compares_times_not_strings_across_offsets
    l = seeded
    l.apply('done 2', now: Time.parse('2026-01-14T14:00:00+00:00'))
    later = '2026-01-14T09:30:00-05:00' # 14:30 UTC, after the close, though it sorts lower as a string
    report = l.upsert([{ 'url' => 'https://github.com/acme/app/pull/7', 'kind' => 'review', 'last_activity' => later }], now: NOW)
    assert_equal({ 'reopened' => [2] }, report)
  end

  def test_upsert_matches_slack_replies_to_their_thread_and_resolves
    l = seeded
    reply = 'https://acme.slack.com/archives/C111/p1700000009000900?thread_ts=1700000001.000100&cid=C111'
    report = l.upsert([{ 'url' => reply, 'resolved' => true, 'resolved_evidence' => 'Ada said thanks' }], now: NOW)
    assert_equal({ 'resolved' => [1] }, report)
    assert_equal('Ada said thanks', l.find(1)['close_note'])
  end

  def test_upsert_adds_new_items_and_skips_resolved_unknown_ones
    l = seeded
    report = l.upsert([{ 'url' => 'https://github.com/acme/app/pull/9', 'title' => 'Review #9', 'kind' => 'review', 'due' => '2026-01-15' },
                       { 'url' => 'https://github.com/acme/app/pull/10', 'resolved' => true }], now: NOW + 3600)
    assert_equal({ 'new' => [6] }, report)
    assert_equal([6], l.view(since: NOW + 1)['new'].map { |i| i['id'] })
  end

  def test_upsert_rejects_bad_items_without_failing_the_batch
    report = seeded.upsert([{ 'title' => 'no link', 'kind' => 'action' },
                            { 'url' => 'https://github.com/acme/app/pull/11', 'title' => 'x', 'kind' => 'bogus' },
                            { 'url' => 'https://github.com/acme/app/pull/12', 'title' => 'Review #12', 'kind' => 'review' }], now: NOW)
    assert_equal([6], report['new'])
    assert_equal(2, report['rejected'].size)
  end

  def test_blank_urls_and_shared_secondary_links_do_not_merge_items
    l = seeded
    digest = 'https://acme.slack.com/archives/D999/p1700000005000500'
    report = l.upsert([{ 'key' => '@41', 'url' => '', 'title' => '@41 Ship the cache', 'kind' => 'task' },
                       { 'key' => '@77', 'url' => '', 'title' => '@77 Something else', 'kind' => 'task' },
                       { 'key' => 'fellow:a', 'url' => digest, 'title' => 'Do A', 'kind' => 'owe' },
                       { 'key' => 'fellow:b', 'url' => 'https://acme.fellow.app/b', 'links' => [digest], 'title' => 'Do B', 'kind' => 'owe' }], now: NOW)
    assert_equal({ 'updated' => [4], 'new' => [6, 7, 8] }, report)
    assert_equal(['@41 Ship the cache', '@77 Something else'], [l.find(4)['title'], l.find(6)['title']])
    refute_includes(l.find(4)['keys'], '')
  end

  def test_bare_host_links_are_not_keys
    l = seeded
    report = l.upsert([{ 'key' => 'gtask:L/1', 'url' => 'https://tasks.example.com/', 'title' => 'Task one', 'kind' => 'task' },
                       { 'key' => 'gtask:L/2', 'url' => 'https://tasks.example.com', 'title' => 'Task two', 'kind' => 'task' }], now: NOW)
    assert_equal({ 'new' => [6, 7] }, report)
  end

  def test_reply_due_date_wins_over_scout_due_date
    l = seeded
    l.apply('due 2 fri', now: NOW)
    l.upsert([{ 'url' => 'https://github.com/acme/app/pull/7', 'kind' => 'review', 'due' => '2026-01-14' }], now: NOW)
    assert_equal('2026-01-16', l.find(2)['due'])
  end

  def test_parse_date_forms
    l = ledger
    assert_equal(Date.new(2026, 1, 15), l.parse_date('tomorrow'))
    assert_equal(Date.new(2026, 1, 21), l.parse_date('wed'))
    assert_equal(Date.new(2026, 1, 19), l.parse_date('next week'))
    assert_equal(Date.new(2026, 1, 17), l.parse_date('3d'))
    assert_equal(Date.new(2026, 2, 3), l.parse_date('feb 3'))
    assert_equal(Date.new(2027, 1, 2), l.parse_date('jan 2'))
    assert_raises(ArgumentError) { l.parse_date('someday') }
  end

  def test_unknown_verbs_and_missing_ids_are_errors
    assert_raises(ArgumentError) { ledger.parse_commands('close 3') }
    assert_raises(ArgumentError) { ledger.parse_commands('done soon') }
    assert_equal([{ 'id' => 99, 'error' => 'no such item' }], ledger.apply('done 99'))
  end

  def test_transaction_persists
    Journal::Ledger.transaction(@path, today: TODAY) { |l| l.seed(BODY, journal_date: TODAY) }
    assert_equal(3, Journal::Ledger.new(@path, today: TODAY).items.size)
  end

  def test_markdown_view_lists_ids_and_timing
    md = Journal::LedgerView.markdown(seeded, since: NOW + 1)
    assert_match('## Overdue (2)', md)
    assert_match(/J-1: \[Reply to Ada about the rollout\]\(.*\)\. Overdue by 2 days \(due Mon Jan 12\); open 5 days/, md)
    assert_match('| J-4 | @41 Ship the cache |', md)
    assert_match('worth a nudge', md.lines.grep(/J-3/).first)
  end

  def test_private_items_keep_only_their_id_in_the_markdown_and_stay_private
    l = seeded
    l.apply('private 3 personal', now: NOW)
    l.upsert([{ 'url' => 'https://mail.google.com/mail/u/0/#all/abc123', 'kind' => 'wait', 'detail' => 'still waiting' }], now: NOW)
    md = Journal::LedgerView.markdown(l, since: NOW + 1)
    assert_match('J-3 (private, see the journal thread).', md)
    refute_match('capacity numbers', md)
    assert(l.find(3)['private'])
    l.apply('share 3', now: NOW)
    refute(l.find(3)['private'])
  end

  def test_carryover_counts_ledger_keys_as_tracked
    known = seeded.known_keys
    total, missing = Journal.missing_items(BODY, 'nothing here', known: known)
    assert_equal(5, total)
    assert_empty(missing)
  end
end
