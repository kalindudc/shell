# frozen_string_literal: true

module Journal
  # The site's Markdown twins: the same facts as each page, every number, row and link, as plain
  # text for agents and readers who want it. Built only from the public copy of an edition.
  module Twin
    module_function

    def link(title, url) = url.to_s.empty? ? title.to_s : "[#{title}](#{url})"

    def bullets(items) = items.map { |i| "- #{i}" }

    def edition(pub, name)
      ledger = pub['ledger']
      items = Paper.open_items(ledger)
      lines = ["# #{Site::NAME}: #{pub['heading']}", '',
               "#{Paper.journal_name}, edition #{pub['edition']}. This is the plain text of [the page](#{name}.html).", '']
      lines += [pub['lede'], ''] unless pub['lede'].to_s.empty?
      lines += Array(pub['chips']).map { |c| "- #{c['text']}" } + [''] if Array(pub['chips']).any?
      lines += Array(pub['metrics']).map { |m| "- #{m['label']}: #{m['value']}" } + ['']
      lines += front(pub) + backlog(pub, items) + happened(pub)
      lines += ['## Sources', '', Array(pub['sources']).map { |s| "#{s['name']} (#{s['status']})" }.join(', '), '']
      hidden = ledger['private_open'].to_i
      lines << "#{hidden} private #{hidden == 1 ? 'item is' : 'items are'} not shown here." if hidden.positive?
      "#{lines.join("\n").strip}\n"
    end

    def front(pub)
      ledger = pub['ledger']
      lines = ['## 01. Front page', '']
      Array(pub['focus']).first(Paper::STORIES).each do |f|
        lines += ["### J-#{f['id']}: #{link(f['title'], f['url'])}", '', f['why'].to_s, '']
      end
      events = Array(pub.dig('calendar', 'events')).reject { |e| e['kind'] == 'personal' }.map { |e| "#{e['start']} #{link(e['title'], e['url'])}" }
      { 'On the agenda' => events,
        'Still waiting on' => Array(ledger['waiting']).map { |i| "#{link(i['title'], Paper.href(i))} (#{i['age']}d)" },
        'Shipped' => Array(pub['shipped']).map { |s| link(s['title'], s['url']) },
        'Corrections' => Array(ledger['closed_recently']).map { |i| link(i['title'], Paper.href(i)) } }.each do |title, rows|
        lines += ["### #{title}", ''] + bullets(rows) + [''] unless rows.empty?
      end
      lines
    end

    def backlog(pub, items)
      ledger = pub['ledger']
      kinds = Paper.kind_counts(items).map { |_, name, n| "#{n} #{name.downcase}" }.join(', ')
      lines = ['## 02. Backlog', '', "#{items.size} open, #{Array(ledger['overdue']).size} overdue; " \
                                     "#{Paper.movement(ledger, items.size, site: true)}.", '']
      lines += ["By kind: #{kinds}.", ''] unless kinds.empty?
      lines += trend(ledger['trend'])
      shown = items.reject { |i| i['private'] }.sort_by { |i| [i['first_seen'].to_s, i['id'].to_i] }
      return lines if shown.empty?

      lines += ['| Id | Seen | Kind | Item | Status |', '| --- | --- | --- | --- | --- |']
      shown.each do |i|
        status = if i['days_overdue'] then "#{Paper.days(i['days_overdue'])} late"
                 elsif i['due'] then "due #{Paper.pretty(i['due'])}"
                 else "open #{Paper.days(i['age'])}"
                 end
        seen = i['first_seen'] ? Paper.pretty(i['first_seen']) : ''
        lines << "| J-#{i['id']} | #{seen} | #{Paper::KIND_LABEL[i['kind']]} | #{link(i['title'].to_s.tr('|', '/'), Paper.href(i))} | #{status} |"
      end
      lines + ['']
    end

    def trend(points)
      points = Array(points)
      return [] if points.empty?

      lines = ['Open items at each edition, private ones included:', '', '| Edition | Open | Overdue |', '| --- | --- | --- |']
      lines + points.map { |t| "| #{Paper.pretty(t['date'])} | #{t['open']} | #{t['overdue'] || ''} |" } + ['']
    end

    def happened(pub)
      did = Array(pub['did']).group_by { |d| d['category'] }
      groups = Site::CATEGORIES.filter_map { |k, name| did[k] && [name, did[k]] }
      groups << ['Team context', pub['context']] if Array(pub['context']).any?
      return [] if groups.empty?

      lines = ['## 03. What happened since the last edition', '']
      groups.each do |name, entries|
        rows = entries.map { |e| e['note'].to_s.empty? ? link(e['title'], e['url']) : "#{link(e['title'], e['url'])}: #{e['note']}" }
        lines += ["### #{name}", ''] + bullets(rows) + ['']
      end
      lines
    end

    def archive(entries)
      rows = entries.reverse.map { |name, heading| "- [#{heading || name}](#{name}.html) ([Markdown](#{name}.md))" }
      "#{(["# #{Site::NAME}: the archive", '', "#{entries.size} editions, newest first.", ''] + rows).join("\n")}\n"
    end

    def llms(entries)
      latest = entries.last.first
      lines = ["# #{Site::NAME}", '', "> #{Paper.journal_name}: a daily work journal written each weekday by an agent. " \
                                      'Private and sensitive items are left out.', '',
               "- [Today](index.html): the newest edition ([Markdown](#{latest}.md))",
               '- [Archive](archive.html): every edition ([Markdown](archive.md))', '', '## Editions', '']
      lines += entries.reverse.map { |name, heading| "- [#{heading || name}](#{name}.html): [Markdown](#{name}.md)" }
      "#{lines.join("\n")}\n"
    end
  end
end
