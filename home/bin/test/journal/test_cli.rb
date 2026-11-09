#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../../lib/journal'
require_relative '../../lib/journal/cli'

class TestCLI < Minitest::Test
  PR = 'https://github.com/acme/app/pull'

  def setup
    @dir = Dir.mktmpdir
    bin = File.join(@dir, 'bin')
    FileUtils.mkdir_p(bin)
    write_stub(bin, 'gh', "case \"$3\" in 7|9) echo MERGED;; 8) echo CLOSED;; *) echo OPEN;; esac")
    write_stub(bin, 'cortex', %(echo '[{"id":41,"status":"done"},{"id":42,"status":"open"}]'))
    @env = ENV.to_h.slice('PATH', 'JOURNAL_LEDGER')
    ENV['PATH'] = "#{bin}:#{ENV.fetch('PATH')}"
    ENV['JOURNAL_LEDGER'] = File.join(@dir, 'ledger.json')
    Journal::Ledger.transaction do |l|
      l.upsert([{ 'url' => "#{PR}/7", 'title' => 'Review 7', 'kind' => 'review' },
                { 'url' => "#{PR}/10", 'title' => 'Review 10', 'kind' => 'review' },
                { 'url' => "#{PR}/8", 'title' => 'Both', 'kind' => 'task', 'links' => ["#{PR}/9"] },
                { 'url' => "#{PR}/11", 'title' => 'One open', 'kind' => 'task', 'links' => ["#{PR}/9"] },
                { 'url' => 'https://delta.example.com/pull/5', 'title' => 'Other host', 'kind' => 'task', 'links' => ["#{PR}/7"] },
                { 'url' => 'https://acme.slack.com/archives/C1/p1700000001000100', 'title' => 'Talk', 'kind' => 'discuss', 'links' => ["#{PR}/7"] },
                { 'key' => '@41', 'title' => '@41 done task', 'kind' => 'task', 'cortex' => [41] },
                { 'key' => '@42', 'title' => '@42 open task', 'kind' => 'task', 'cortex' => [42] }])
    end
  end

  def teardown
    ENV['PATH'] = @env['PATH']
    @env['JOURNAL_LEDGER'] ? ENV['JOURNAL_LEDGER'] = @env['JOURNAL_LEDGER'] : ENV.delete('JOURNAL_LEDGER')
    FileUtils.rm_rf(@dir)
  end

  def write_stub(dir, name, body)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def run_sync(*args)
    out, = capture_io { Journal::CLI.ledger(['sync', *args]) }
    JSON.parse(out)
  end

  def test_sync_closes_items_whose_prs_are_all_finished_or_cortex_task_is_done
    report = run_sync
    assert_equal([1, 3, 7], report['closed'].map { |c| c['id'] })
    assert_equal('the PR is merged', report['closed'][0]['evidence'])
    assert_equal('all PRs are closed or merged', report['closed'][1]['evidence'])
    assert_equal('cortex @41 done', report['closed'][2]['evidence'])
    assert_equal('open', Journal::Ledger.new.find(6)['status'])
    statuses = Journal::Ledger.new.items.to_h { |i| [i['id'], i['status']] }
    assert_equal({ 2 => 'open', 4 => 'open', 5 => 'open', 6 => 'open', 8 => 'open' }, statuses.reject { |_, s| s == 'done' })
  end

  def test_dry_run_changes_nothing
    report = run_sync('--dry-run')
    assert(report['dry_run'])
    assert_equal(3, report['closed'].size)
    assert_empty(Journal::Ledger.new.items.select { |i| i['status'] == 'done' })
  end
end
