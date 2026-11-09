# frozen_string_literal: true

module Journal
  # Markdown for the ledger part of a journal body: urgent buckets as short lines, the rest as one table.
  module LedgerView
    KIND_NAMES = {
      'action' => 'Needs my action', 'review' => 'Reviews', 'owe' => 'I owe', 'wait' => 'Waiting on others',
      'discuss' => 'Open discussions', 'task' => 'Tracked work'
    }.freeze

    module_function

    def markdown(ledger, since: nil)
      v = ledger.view(since: since)
      out = []
      out << bucket("Overdue (#{v['overdue'].size})", v['overdue'], ledger, 'Nothing overdue.')
      out << bucket("Due today (#{v['due_today'].size})", v['due_today'], ledger, 'Nothing due today.')
      out << bucket("New since the last journal (#{v['new'].size})", v['new'], ledger, 'Nothing new.')
      out << bucket("Waiting on others (#{v['waiting'].size})", v['waiting'], ledger, nil)
      out << backlog(v['backlog'], ledger)
      out << closed(v['closed_recently'], ledger) if v['closed_recently'].any?
      out << snoozed(v['snoozed'], ledger) if v['snoozed'].any?
      out.compact.join("\n")
    end

    def bucket(title, list, ledger, empty)
      return nil if list.empty? && empty.nil?
      return "## #{title}\n#{empty}\n" if list.empty?

      "## #{title}\n#{list.map { |i| line(i, ledger) }.join("\n")}\n"
    end

    # Private items keep only their id here: their titles and links appear only in the journal thread.
    def line(item, ledger)
      s = ledger.summary(item)
      return "- #{s['label']} (private, see the journal thread). #{timing(s)}" if s['private']

      text = "- #{s['label']}: #{link(s)}."
      text += " #{s['detail'].chomp('.')}." if s['detail'] && !s['detail'].empty?
      text + " #{timing(s)}"
    end

    def timing(sum)
      parts = []
      if sum['days_overdue']
        parts << "Overdue by #{days(sum['days_overdue'])} (due #{pretty(sum['due'])})"
      elsif sum['due']
        parts << "Due #{pretty(sum['due'])}"
      end
      parts << "open #{days(sum['age'])}, since #{pretty(sum['first_seen'])}"
      parts << 'worth a nudge' if sum['nudge']
      parts << "no scout has reported it for #{days(sum['unseen_days'])}" if sum['unseen_days']
      sentence = parts.join('; ')
      "#{sentence[0].upcase}#{sentence[1..]}."
    end

    def backlog(list, ledger)
      return "## Backlog\nNothing else open.\n" if list.empty?

      rows = list.group_by { |i| i['kind'] }.flat_map do |kind, group|
        ["| **#{KIND_NAMES.fetch(kind, kind)}** | | |"] + group.map do |i|
          s = ledger.summary(i)
          shown = s['private'] ? 'Private, see the journal thread' : link(s).gsub('|', '/')
          "| #{s['label']} | #{shown} | #{days(s['age'])} |"
        end
      end
      "## Backlog (#{list.size})\n| Id | Item | Open |\n|---|---|---|\n#{rows.join("\n")}\n"
    end

    def closed(list, ledger)
      lines = list.map do |i|
        i['private'] ? "- #{ledger.label(i)} #{i['status']} (private)" : "- #{ledger.label(i)} #{i['status']}: #{link(i)} (#{i['close_note']})"
      end
      "## Closed since the last journal (#{list.size})\n#{lines.join("\n")}\n"
    end

    def snoozed(list, ledger)
      lines = list.map { |i| "- #{ledger.label(i)}: #{i['private'] ? 'private' : link(i)}, until #{pretty(i['snooze_until'])}" }
      "## Snoozed (#{list.size})\n#{lines.join("\n")}\n"
    end

    def link(item) = item['url'] ? "[#{item['title']}](#{item['url']})" : item['title'].to_s

    def days(count) = count == 1 ? '1 day' : "#{count} days"

    def pretty(iso) = Date.parse(iso).strftime('%a %b %-d')
  end
end
