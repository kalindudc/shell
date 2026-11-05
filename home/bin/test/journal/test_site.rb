#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../../lib/journal'

class TestSite < Minitest::Test
  def item(id, title, extra = {})
    { 'id' => id, 'label' => "J-#{id}", 'title' => title, 'url' => "https://example.com/#{id}", 'kind' => 'action', 'age' => 3 }.merge(extra)
  end

  def data(lede: 'A quiet day.')
    {
      'date' => '2026-01-14', 'heading' => 'Wednesday, January 14', 'lede' => 'PRIVATE LEDE about Ada',
      'metrics' => [{ 'value' => '3', 'label' => 'overdue', 'tone' => 'bad' }, { 'value' => '2', 'label' => 'PRs merged' }],
      'focus' => [{ 'id' => 1, 'title' => 'Ship it', 'why' => 'Soon' }, { 'id' => 2, 'title' => 'Secret focus', 'why' => 'x' }],
      'calendar' => { 'events' => [{ 'start' => '10:30', 'end' => '11:00', 'title' => 'Town hall', 'url' => 'https://example.com/th' },
                                   { 'start' => '13:00', 'end' => '14:00', 'title' => 'Interview with Ada', 'url' => 'https://example.com/i' },
                                   { 'start' => '18:00', 'end' => '19:00', 'title' => 'Climbing', 'kind' => 'personal' }] },
      'ledger' => {
        'overdue' => [item(1, 'Ship it', 'days_overdue' => 1), item(2, 'Secret focus', 'private' => true, 'days_overdue' => 2),
                      item(3, 'Answer about compensation', 'days_overdue' => 3)],
        'due_today' => [], 'new' => [], 'waiting' => [item(4, 'Bob: numbers', 'kind' => 'wait')],
        'backlog' => [item(5, 'Reply in DM', 'url' => 'https://acme.slack.com/archives/D123/p1')],
        'closed_recently' => [], 'trend' => [{ 'date' => '2026-01-13', 'open' => 5 }, { 'date' => '2026-01-14', 'open' => 4 }]
      },
      'public' => { 'lede' => lede, 'calendar' => { 'events' => [{ 'start' => '10:30', 'end' => '11:00', 'title' => 'Town hall' }] },
                    'shipped' => [{ 'title' => 'Cache fix', 'url' => 'https://example.com/pr/1' }, { 'title' => 'Bumped the budget' }],
                    'did' => [{ 'category' => 'reviewed', 'title' => 'Reviewed #7' }] }
    }
  end

  def test_public_data_keeps_private_and_sensitive_items_out
    pub, redacted = Journal::Share.public_data(data, pats: Journal::Share::DEFAULT_PATTERNS)
    text = JSON.generate(pub)
    %w[Secret PRIVATE Interview compensation D123 budget].each { |w| refute_match(w, text) }
    assert_equal([1], pub['ledger']['overdue'].map { |i| i['id'] })
    assert_equal([1], pub['focus'].map { |f| f['id'] })
    assert_equal(3, pub['ledger']['private_open'])
    assert_equal('1', pub['metrics'][0]['value'])
    assert_equal('2', pub['metrics'][1]['value'])
    assert_equal(['ledger.overdue J-3', 'ledger.backlog J-5', 'shipped'], redacted.map { |r| r['where'] })
  end

  def test_unlisted_work_meetings_keep_their_slot_without_details
    pub, = Journal::Share.public_data(data, pats: Journal::Share::DEFAULT_PATTERNS)
    assert_equal([['10:30', 'Town hall'], ['13:00', 'Private meeting']], pub['calendar']['events'].map { |e| [e['start'], e['title']] })
    refute(pub['calendar']['events'].last.key?('url'))
  end

  def test_focus_on_a_redacted_item_is_not_published
    d = data
    d['focus'] << { 'id' => 3, 'title' => 'A clean-sounding title', 'why' => 'fine' }
    pub, = Journal::Share.public_data(d, pats: Journal::Share::DEFAULT_PATTERNS)
    assert_equal([1], pub['focus'].map { |f| f['id'] })
  end

  def test_sensitive_lede_is_dropped_not_published
    pub, redacted = Journal::Share.public_data(data(lede: 'My doctor appointment ran long'), pats: Journal::Share::DEFAULT_PATTERNS)
    assert_equal('', pub['lede'])
    assert_includes(redacted.map { |r| r['where'] }, 'lede')
  end

  def test_site_replaces_a_days_edition_instead_of_duplicating
    Dir.mktmpdir do |dir|
      archive = File.join(dir, 'archive')
      out = File.join(dir, 'site')
      FileUtils.mkdir_p(archive)
      File.write(File.join(archive, '2026-01-14.json'), JSON.generate(data))
      Journal::Site.build(archive, out)
      File.write(File.join(archive, '2026-01-14.json'), JSON.generate(data(lede: 'Second run of the day.')))
      report = Journal::Site.build(archive, out)
      assert_equal(1, report['editions'])
      assert_equal(%w[2026-01-14.html archive.html index.html], Dir.children(out).sort)
      index = Journal.read(File.join(out, 'index.html'))
      assert_match('Second run of the day.', index)
      refute_match('A quiet day.', index)
      assert_equal(1, Journal.read(File.join(out, 'archive.html')).scan('2026-01-14.html').size)
      refute_match('Secret focus', index)
      assert_match('3 private items are not shown here.', index)
      assert_match('<html data-theme="light">', index)
      assert_match('id="theme"', index)
      assert_operator(index.index('journal-theme'), :<, index.index('<style>'))
    end
  end

  def test_long_side_lists_expand_in_place
    d = data
    d['ledger']['waiting'] = (1..5).map { |n| item(10 + n, "Wait #{n}", 'kind' => 'wait') }
    html = Journal::Render.page(d)
    assert_match('<summary class="mono">and 2 more</summary>', html)
    assert_match('Wait 5', html)
  end

  def test_cortex_tasks_open_in_the_desktop_app
    d = data
    d['ledger']['backlog'] << item(41, '@41 Ship the cache', 'url' => '', 'kind' => 'task', 'cortex' => [41])
    html = Journal::Render.page(d)
    assert_match(%r{<a class="t\d" href="cortex://app/task/41" data-t="J-41}, html)
    pub, = Journal::Share.public_data(d, pats: Journal::Share::DEFAULT_PATTERNS)
    assert_equal([41], pub['ledger']['backlog'].last['cortex'])
  end

  def test_weather_explains_itself_and_filters_the_map
    d = data
    d['ledger']['trend'] = [{ 'date' => '2026-01-13', 'open' => 7, 'overdue' => 1 }, { 'date' => '2026-01-14', 'open' => 5, 'overdue' => 3 }]
    html = Journal::Render.page(d)
    assert_match('down 2 since Jan 13', html)
    assert_match('data-filter="overdue"', html)
    assert_match('data-filter="kind-wait"', html)
    assert_match('<div class="grp" data-kind="wait">', html)
    assert_match('<title>Jan 14: 5 open, 3 overdue</title>', html)
    assert_match('stroke-dasharray', html)
    assert_match('What is this?', html)
    assert_match(/Start with <a[^>]*>J-3<\/a>, 3 days late/, html)
  end

  def test_weather_starts_with_a_real_item_and_flags_stale_ones
    d = data
    d['ledger']['overdue'] << item(9, 'A task from 2021', 'days_overdue' => 1970)
    d['ledger']['trend'] = [{ 'date' => '2026-01-13', 'open' => 50 }, { 'date' => '2026-01-14', 'open' => 5, 'overdue' => 3 }]
    html = Journal::Render.page(d)
    assert_match(/Start with <a[^>]*>J-3<\/a>, 3 days late/, html)
    assert_match(/1 item is over 30 days late \(<a[^>]*>J-9<\/a>\)/, html)
    assert_match('first ledger edition', html)
    assert_match('grey: before the ledger', html)
  end

  def test_item_list_is_chronological_folded_and_leaves_private_items_out
    d = data
    d['ledger']['backlog'] << item(6, 'Older thing', 'first_seen' => '2026-01-02')
    d['ledger']['waiting'][0]['first_seen'] = '2026-01-10'
    html = Journal::Render.page(d)
    list = html[/<details class="ilist">.*?<\/details>/m]
    assert_match('Every open item, oldest first (5)', list)
    assert_operator(list.index('J-6'), :<, list.index('J-4'))
    refute_match('Secret focus', list)
    assert_match('1 private item is not listed.', list)
    assert_match('<tr data-kind="action" class="late"><td class="jid">J-3</td>', list)
    pub, = Journal::Share.public_data(d, pats: Journal::Share::DEFAULT_PATTERNS)
    refute_match('Secret focus', Journal::Paper.body(pub, site: true)[/<details class="ilist">.*?<\/details>/m])
  end

  def test_thread_page_shows_private_items_and_reply_hint
    html = Journal::Render.page(data)
    assert_match('Secret focus', html)
    assert_match('private', html)
    assert_match('1 day late', html)
    assert_match('Reply in the journal thread', html)
  end
end
