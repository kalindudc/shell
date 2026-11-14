# frozen_string_literal: true

require 'fileutils'

module Journal
  # A static site of shareable journal editions in the house style: index.html is the newest front
  # page, <date>.html each edition and archive.html the list of them, each with its Markdown twin,
  # built only from Share.public_data of the archived briefings. The kit sits beside them in kit/.
  module Site
    NAME = 'The Morning Edge'
    CATEGORIES = { 'shipped' => 'Shipped', 'reviewed' => 'Reviewed', 'discussed' => 'Discussions and decisions',
                   'meeting' => 'Meetings', 'agent' => 'Agent work' }.freeze

    module_function

    def esc(value) = CGI.escapeHTML(value.to_s)

    def editions(archive)
      Dir[File.join(archive, '*.json')].map { |f| [File.basename(f, '.json'), JSON.parse(Journal.read(f))] }
                                       .select { |name, _| name.match?(/\A\d{4}-\d{2}-\d{2}\z/) }.sort_by(&:first)
    end

    def short(name) = Date.iso8601(name).strftime('%a %b %-d')

    def list(items)
      rows = items.map do |e|
        title = e['url'].to_s.empty? ? esc(e['title']) : %(<a href="#{esc(e['url'])}" target="_blank">#{esc(e['title'])}</a>)
        note = e['note'].to_s.empty? ? '' : %( <span class="note">— #{esc(e['note'])}</span>)
        "<li>#{title}#{note}</li>"
      end
      "<ul>#{rows.join}</ul>"
    end

    def happened(pub)
      did = Array(pub['did']).group_by { |d| d['category'] }
      parts = CATEGORIES.filter_map { |k, name| did[k] && %(<h3 class="label">#{name}</h3>#{list(did[k])}) }
      parts << %(<h3 class="label">Team context</h3>#{list(pub['context'])}) if Array(pub['context']).any?
      return '' if parts.empty?

      Paper.part('happened', '03', 'What happened', 'What happened <em>since the last edition.</em>',
                 %(<div class="happened">#{parts.join}</div>),
                 figure: 'lists of links to what shipped and what was discussed; a drawing would only repeat them')
    end

    def editions_nav(prev_name, next_name)
      links = []
      links << %(<a href="#{prev_name}.html" rel="prev">← #{short(prev_name)}</a>) if prev_name
      links << %(<a href="archive.html">All editions</a>)
      links << %(<a href="#{next_name}.html" rel="next">#{short(next_name)} →</a>) if next_name
      %(<nav class="editions" aria-label="Editions">#{links.join}</nav>)
    end

    def edition_page(pub, name, seal, neighbours, latest:)
      prev_name, next_name = neighbours
      extra = happened(pub)
      parts = Paper::PARTS + (extra.empty? ? [] : [['happened', 'What happened']])
      main = Paper.body(pub, site: true, editions: editions_nav(prev_name, next_name), extra: extra)
      links = [prev_name && %(<a href="#{prev_name}.html">← #{short(prev_name)}</a>), %(<a href="archive.html">Archive</a>),
               %(<a href="#{name}.md">Markdown</a>)].compact
      lede = pub['lede'].to_s.empty? ? "#{Paper.journal_name}, #{pub['heading']}." : pub['lede']
      Frame.shell(title: "#{NAME}: #{pub['heading']}", description: lede, twin: "#{name}.md",
                  header: Frame.header(seal, parts, latest ? :today : nil), main: main, foot: Frame.foot(links))
    end

    def archive_page(all, rows, seal, trend)
      first = Date.iso8601(all.first.first).strftime('%-d %B %Y')
      latest = Date.iso8601(all.last.first).strftime('%-d %B %Y')
      kicker = %(<p class="kicker"><span>#{esc(Paper.journal_name)}</span><span class="sep">/</span><span>Archive</span></p>)
      lede = "#{all.size} #{all.size == 1 ? 'edition' : 'editions'} since #{first}, each the public copy of that morning's journal."
      brief = %(<dl class="brief strip wide"><div><dt>editions</dt><dd>#{all.size}</dd></div><div><dt>first</dt><dd>#{esc(first)}</dd></div>) +
              %(<div><dt>latest</dt><dd>#{esc(latest)}</dd></div></dl>)
      table = %(<div class="table wide"><table class="ledger archive"><thead><tr><th scope="col">Edition</th><th scope="col">Open</th>) +
              %(<th scope="col">Overdue</th><th scope="col">Shipped</th></tr></thead><tbody>#{rows.reverse.join}</tbody></table></div>)
      chart = %(<figure class="fig wide">#{Paper.sparkline(trend, width: 800, height: 120)}<figcaption><b>Open items at each edition.</b> ) +
              %(The solid line and the table count every open item, private ones included; the dashed line, those overdue. ) +
              %(Each edition's own page counts only the items it shows.</figcaption></figure>)
      main = %(<header class="masthead" id="top" tabindex="-1"><div class="dateline wide">#{kicker}</div>) +
             %(<h1 class="nameplate wide">The Morning <em>Edge</em></h1><p class="lede wide" data-content>#{esc(lede)}</p>#{brief}</header>) +
             Paper.part('editions', '01', 'Editions', 'Every edition, <em>newest first.</em>', chart + table)
      Frame.shell(title: "#{NAME}: the archive", description: lede, twin: 'archive.md', header: Frame.header(seal, [%w[editions Editions]], :archive),
                  main: main, foot: Frame.foot([%(<a href="index.html">Today</a>), %(<a href="archive.md">Markdown</a>)]))
    end

    def write(out, name, text) = File.write(File.join(out, name), text, encoding: 'UTF-8')

    # The archive counts the whole ledger, private items included, as each edition's trend line does.
    def whole_ledger(name, led)
      { 'date' => name, 'open' => Paper.open_items(led).size + led['private_open'].to_i,
        'overdue' => Array(led['overdue']).size + led['private_overdue'].to_i }
    end

    def archive_row(name, pub, point)
      %(<tr><th scope="row"><a href="#{name}.html">#{esc(pub['heading'] || name)}</a></th>) +
        %(<td class="fig" data-label="Open">#{point['open']}</td><td class="fig" data-label="Overdue">#{point['overdue']}</td>) +
        %(<td class="fig" data-label="Shipped">#{Array(pub['shipped']).size}</td></tr>)
    end

    # Builds the site and returns { editions:, out:, redacted: { date => [...] } }.
    def build(archive, out)
      all = editions(archive)
      raise ArgumentError, "no editions in #{archive}" if all.empty?

      FileUtils.mkdir_p(out)
      Kit.copy(out)
      seal = Kit.seal(favicon: File.join(out, 'favicon.svg'))
      redacted = {}
      rows = []
      entries = []
      trend = []
      previous = nil
      all.each_with_index do |(name, data), i|
        pub, hits = Share.public_data(data)
        redacted[name] = hits if hits.any?
        pub['edition'] = i + 1
        pub['ledger']['previous'] = previous
        previous = { 'date' => name, 'open' => Paper.open_items(pub['ledger']).size }
        entries << [name, pub['heading']]
        latest = i == all.size - 1
        html = edition_page(pub, name, seal, [i.zero? ? nil : all[i - 1].first, all[i + 1]&.first], latest: latest)
        write(out, "#{name}.html", html)
        write(out, "#{name}.md", Twin.edition(pub, name))
        write(out, 'index.html', html) if latest
        point = whole_ledger(name, pub['ledger'])
        trend << point
        rows << archive_row(name, pub, point)
      end
      write(out, 'archive.html', archive_page(all, rows, seal, trend))
      write(out, 'archive.md', Twin.archive(entries))
      write(out, 'llms.txt', Twin.llms(entries))
      { 'editions' => all.size, 'out' => out, 'redacted' => redacted }
    end
  end
end
