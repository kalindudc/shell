#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../../lib/journal'

class TestJournal < Minitest::Test
  PREVIOUS = <<~MD
    # Journal
    ## Today's focus
    - Reply to the thread ([thread](https://acme.slack.com/archives/C111/p1700000002000200?thread_ts=1700000001.000100&cid=C111))
    ## Needs my action
    - [ ] Review the PR ([PR](https://github.com/acme/app/pull/7))
    - [ ] Answer the mail ([mail](https://mail.google.com/mail/u/0/#all/abc123))
    ### I owe
    - [ ] Finish the task @42
    ## What I did since the last journal
    - Shipped ([PR](https://github.com/acme/app/pull/1))
  MD

  def test_open_items_skip_closed_sections
    items = Journal.open_items(PREVIOUS)
    assert_equal(["Today's focus", 'Needs my action', 'Needs my action', 'I owe'], items.map { |i| i[:section] })
  end

  def test_nothing_missing_when_every_key_is_carried
    new_body = <<~MD
      - newer reply in the same thread (https://acme.slack.com/archives/C111/p1700000009000900?thread_ts=1700000001.000100&cid=C111)
      - https://github.com/acme/app/pull/7#issuecomment-1
      - https://mail.google.com/mail/u/0/#all/abc123
      - @42
    MD
    total, missing = Journal.missing_items(PREVIOUS, new_body)
    assert_equal(4, total)
    assert_empty(missing)
  end

  def test_reports_dropped_items
    _, missing = Journal.missing_items(PREVIOUS, 'only @42 here')
    assert_equal(3, missing.size)
    assert_match('Review the PR', missing[1][:line])
  end

  def test_task_ids_do_not_match_issue_refs_or_mentions
    refute(Journal.body_keys('see #@42 and foo@42').include?('@42'))
  end

  def data
    {
      'date' => '2026-01-14', 'heading' => 'Wednesday, January 14', 'subtitle' => 'Since Tue 09:05', 'journal_id' => 12,
      'metrics' => [{ 'value' => '3', 'label' => 'need you', 'tone' => 'warn' }],
      'focus' => [{ 'title' => 'Reply <now>', 'url' => 'https://example.com/a?x=1&y=2', 'why' => 'Waiting', 'since' => '2026-01-10' }],
      'calendar' => { 'events' => [{ 'start' => '10:30', 'end' => '11:00', 'title' => 'Sync' }] },
      'needs' => [{ 'title' => 'Review', 'url' => 'https://example.com/pr', 'since' => '2026-01-13' }],
      'bars' => [{ 'title' => 'PRs', 'parts' => [{ 'label' => 'draft', 'value' => 2 }, { 'label' => 'none', 'value' => 0 }] }],
      'week' => [{ 'label' => 'Mon', 'merged' => 2, 'threads' => 10 }],
      'sources' => [{ 'name' => 'Mail', 'status' => 'fail' }]
    }
  end

  def test_page_escapes_and_links
    page = Journal::Render.page(data, now: Time.new(2026, 1, 1))
    assert_includes(page, 'Reply &lt;now&gt;')
    assert_includes(page, 'href="https://example.com/a?x=1&amp;y=2"')
    assert_includes(page, 'cortex @12')
    refute_includes(page, 'class="now"')
  end

  def test_age_badges
    today = Date.new(2026, 1, 14)
    assert_includes(Journal::Render.age(nil, today), '>new<')
    assert_includes(Journal::Render.age('2026-01-13', today), 'a1')
    assert_includes(Journal::Render.age('2026-01-10', today), '>4d<')
  end

  def test_empty_bar_parts_are_dropped
    refute_includes(Journal::Render.page(data), 'none 0')
  end

  def test_read_is_utf8_under_an_ascii_locale
    previous = Encoding.default_external
    Encoding.default_external = Encoding::US_ASCII
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'data.json')
      File.binwrite(path, '{"heading": "Mikołaj"}')
      assert_equal('Mikołaj', JSON.parse(Journal.read(path))['heading'])
    end
  ensure
    Encoding.default_external = previous
  end

  def test_calendar_clamps_to_day
    assert_in_delta(0.0, Journal::Render.pct(6))
    assert_in_delta(100.0, Journal::Render.pct(23))
  end
end
