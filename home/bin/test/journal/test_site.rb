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
      assert_equal(%w[2026-01-14.html 2026-01-14.md archive.html archive.md favicon.svg index.html journal.css journal.js kit llms.txt],
                   Dir.children(out).sort)
      index = Journal.read(File.join(out, 'index.html'))
      assert_match('Second run of the day.', index)
      refute_match('A quiet day.', index)
      assert_equal(1, Journal.read(File.join(out, 'archive.html')).scan('2026-01-14.html').size)
      refute_match('Secret focus', index)
      assert_match('3 private items are not shown here.', index)
      assert_match('role="radiogroup" aria-label="Theme"', index)
      assert_operator(index.index('localStorage.getItem("theme")'), :<, index.index('<link rel="stylesheet"'))
    end
  end

  def test_site_ships_the_kit_its_twins_and_a_house_header
    Dir.mktmpdir do |dir|
      archive = File.join(dir, 'archive')
      out = File.join(dir, 'site')
      FileUtils.mkdir_p(archive)
      File.write(File.join(archive, '2026-01-14.json'), JSON.generate(data))
      with_env('JOURNAL_BYLINE' => 'Ada Lovelace') { Journal::Site.build(archive, out) }
      %w[kit/palette.css kit/components.css kit/site.js kit/fonts/source-serif-4.woff2 kit/fonts/LICENSE.md].each do |file|
        assert_path_exists(File.join(out, file))
      end
      assert_match('<svg', Journal.read(File.join(out, 'favicon.svg')))
      index = Journal.read(File.join(out, 'index.html'))
      assert_match('<a class="skip" href="#main">', index)
      assert_match(/<a class="home" href="index.html"><svg class="mark seal"/, index)
      %w[front backlog happened].each { |part| assert_match(%(<li><a href="##{part}">), index) }
      assert_match('<a href="index.html" aria-current="page">Today</a>', index)
      assert_match('<dl class="brief strip wide">', index)
      assert_match('<link rel="alternate" type="text/markdown" href="2026-01-14.md">', index)
      assert_match('<span class="by">by Ada Lovelace</span>', index)
      refute_match(%r{https?://[^"]*fonts\.googleapis}, index)
      twin = Journal.read(File.join(out, '2026-01-14.md'))
      assert_match('A quiet day.', twin)
      assert_match('[Cache fix](https://example.com/pr/1)', twin)
      %w[PRIVATE Secret Interview compensation budget].each { |word| refute_match(word, twin) }
      assert_match('- [Wednesday, January 14](2026-01-14.html)', Journal.read(File.join(out, 'llms.txt')))
    end
  end

  def test_editions_link_to_their_neighbours
    Dir.mktmpdir do |dir|
      archive = File.join(dir, 'archive')
      out = File.join(dir, 'site')
      FileUtils.mkdir_p(archive)
      File.write(File.join(archive, '2026-01-13.json'), JSON.generate(data.merge('date' => '2026-01-13', 'heading' => 'Tuesday, January 13')))
      File.write(File.join(archive, '2026-01-14.json'), JSON.generate(data))
      Journal::Site.build(archive, out)
      older = Journal.read(File.join(out, '2026-01-13.html'))
      newer = Journal.read(File.join(out, '2026-01-14.html'))
      assert_match('<a href="2026-01-14.html" rel="next">Wed Jan 14 →</a>', older)
      assert_match('<a href="2026-01-13.html" rel="prev">← Tue Jan 13</a>', newer)
      refute_match('aria-current="page">Today', older)
      assert_operator(Journal.read(File.join(out, 'archive.html')).index('2026-01-14.html'), :<,
                      Journal.read(File.join(out, 'archive.html')).index('2026-01-13.html'))
    end
  end

  def test_briefing_carries_its_kit_and_follows_bbs_theme
    html = Journal::Render.page(data)
    assert_match('<body class="briefing">', html)
    assert_match('data:font/woff2;base64,', html)
    assert_match('--background', html)
    assert_match('The Morning <em>Edge</em>', html)
    refute_match('href="kit/', html)
    refute_match('url("fonts/', html)
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  def test_long_side_lists_expand_in_place
    d = data
    d['ledger']['waiting'] = (1..5).map { |n| item(10 + n, "Wait #{n}", 'kind' => 'wait') }
    html = Journal::Render.page(d)
    assert_match('<summary>and 2 more</summary>', html)
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

  def test_briefing_lists_every_item_and_the_site_only_public_ones
    d = data
    d['ledger']['backlog'] << item(6, 'Older thing', 'first_seen' => '2026-01-02')
    d['ledger']['waiting'][0]['first_seen'] = '2026-01-10'
    list = Journal::Render.page(d)[/<details class="more ilist">.*?<\/details>/m]
    assert_match('Every open item, oldest first (6)', list)
    assert_operator(list.index('J-6'), :<, list.index('J-4'))
    assert_match(%r{<td class="st" data-label="Status"><span class="late">2 days late</span> · private</td>}, list)
    assert_match('Secret focus', list)
    refute_match('not listed', list)
    assert_match('<tr data-kind="action" class="late"><td class="jid" data-label="Id">J-3</td>', list)
    %w[Seen Kind].each { |label| assert_match(%(data-label="#{label}"), list) }
    pub, = Journal::Share.public_data(d, pats: Journal::Share::DEFAULT_PATTERNS)
    site_list = Journal::Paper.body(pub, site: true)[/<details class="more ilist">.*?<\/details>/m]
    assert_match('Every open item, oldest first (3)', site_list)
    refute_match('Secret focus', site_list)
  end

  def test_site_weather_counts_one_population
    Dir.mktmpdir do |dir|
      archive = File.join(dir, 'archive')
      out = File.join(dir, 'site')
      FileUtils.mkdir_p(archive)
      older = data.merge('date' => '2026-01-13', 'heading' => 'Tuesday, January 13')
      older['ledger'] = JSON.parse(JSON.generate(data['ledger']))
      older['ledger']['backlog'] += [item(7, 'Extra'), item(8, 'Another')]
      newer = data
      newer['ledger']['new'] = [item(9, 'Fresh')]
      newer['ledger']['closed_recently'] = [item(10, 'Gone')]
      newer['ledger']['trend'] = [{ 'date' => '2026-01-13', 'open' => 9, 'overdue' => 1 }, { 'date' => '2026-01-14', 'open' => 12, 'overdue' => 3 }]
      File.write(File.join(archive, '2026-01-13.json'), JSON.generate(older))
      File.write(File.join(archive, '2026-01-14.json'), JSON.generate(newer))
      Journal::Site.build(archive, out)
      first = Journal.read(File.join(out, '2026-01-13.html'))
      page = Journal.read(File.join(out, '2026-01-14.html'))
      assert_match('first edition on this site · 0 new · 0 closed', first)
      assert_match('down 1 since Jan 13 · 1 new · 1 closed', page)
      assert_match('the line counts private items too', page)
      assert_match('This copy leaves private items out of the counts', page)
      assert_match('down 3 since Jan 13', Journal::Render.page(newer))
      archive_page = Journal.read(File.join(out, 'archive.html'))
      assert_match('<td class="fig" data-label="Open">6</td><td class="fig" data-label="Overdue">3</td><td class="fig" data-label="Shipped">1</td>',
                   archive_page)
      assert_match('<title>Jan 14: 6 open, 3 overdue</title>', archive_page)
      twin = Journal.read(File.join(out, '2026-01-14.md'))
      assert_match('3 open, 1 overdue; down 1 since Jan 13 · 1 new · 1 closed.', twin)
      assert_match("| Edition | Open | Overdue |\n| --- | --- | --- |\n| Jan 13 | 9 | 1 |\n| Jan 14 | 12 | 3 |", twin)
    end
  end

  def test_only_the_briefing_shortens_shipped_titles
    d = data
    long = 'Deploy Envoy Gateway apps from Infra Central with a longer tail (infrastructure#88397)'
    d['shipped'] = [{ 'title' => long, 'url' => 'https://example.com/pr/2' }]
    d['public']['shipped'] = d['shipped']
    refute_match('#88397', Journal::Render.page(d))
    pub, = Journal::Share.public_data(d, pats: Journal::Share::DEFAULT_PATTERNS)
    assert_match(long, Journal::Paper.body(pub, site: true))
  end

  def test_twin_carries_the_chips
    d = data
    d['public']['chips'] = [{ 'text' => 'On call: Ada until 18:00 today', 'tone' => 'info' }]
    pub, = Journal::Share.public_data(d, pats: Journal::Share::DEFAULT_PATTERNS)
    pub['edition'] = 1
    assert_match("- On call: Ada until 18:00 today\n", Journal::Twin.edition(pub, '2026-01-14'))
  end

  def test_thread_page_shows_private_items_and_reply_hint
    html = Journal::Render.page(data)
    assert_match('Secret focus', html)
    assert_match('private', html)
    assert_match('1 day late', html)
    assert_match('Reply in the journal thread', html)
  end
end
