# frozen_string_literal: true

require 'fileutils'

module Journal
  # A static site of shareable journal editions: index.html is the newest front page,
  # <date>.html each edition, built only from Share.public_data of the archived briefings.
  module Site
    CSS = <<~CSS
      body{margin:0;background:var(--paper);color:var(--ink);font-family:var(--serif)}
      .site{max-width:780px;margin:0 auto;padding:22px 18px 60px}
      .nav{display:flex;justify-content:space-between;align-items:baseline;gap:10px;flex-wrap:wrap;margin-bottom:14px}
      .nav a{font-family:var(--mono);font-size:12px;color:var(--blue);text-decoration:none;margin-left:12px}
      .nav .who{font-family:var(--mono);font-size:12px;text-transform:uppercase;letter-spacing:.12em;color:var(--ink-soft)}
      .more{background:var(--card);border:1px solid var(--rule);border-radius:8px;padding:16px 22px;margin-top:16px;font-size:15.5px;line-height:1.6}
      .more h2{font-size:19px;margin:6px 0 8px}.more ul{padding-left:20px;margin:0 0 12px}
      .more a{color:var(--ink);border-bottom:1px solid var(--rule);text-decoration:none}
      table.arch{width:100%;border-collapse:collapse;font-size:15px}
      table.arch td,table.arch th{border-bottom:1px solid var(--rule-soft);padding:6px 4px;text-align:left}
      table.arch th{font-family:var(--mono);font-size:11px;text-transform:uppercase;letter-spacing:.08em;color:var(--ink-soft)}
      .note{font-family:var(--mono);font-size:11.5px;color:var(--ink-soft);margin-top:18px}
      .theme{font-family:var(--mono);font-size:12px;color:var(--blue);background:none;border:1px solid var(--rule);border-radius:999px;padding:2px 10px;margin-left:12px;cursor:pointer}
      .theme:hover{border-color:var(--blue)}
    CSS
    THEME_KEY = 'journal-theme'
    # Runs in <head> before first paint: light unless the reader picked dark on an earlier visit.
    THEME_INIT = "try{var t=localStorage.getItem('#{THEME_KEY}');if(t==='dark'||t==='light')" \
                 'document.documentElement.dataset.theme=t}catch(e){}'
    THEME_TOGGLE = <<~JS.tr("\n", ' ')
      (function(){var b=document.getElementById('theme'),r=document.documentElement;
      function label(){b.textContent=r.dataset.theme==='dark'?'Light mode':'Dark mode'}
      b.addEventListener('click',function(){r.dataset.theme=r.dataset.theme==='dark'?'light':'dark';
      try{localStorage.setItem('#{THEME_KEY}',r.dataset.theme)}catch(e){}label()});label()})();
    JS
    CATEGORIES = { 'shipped' => 'Shipped', 'reviewed' => 'Reviewed', 'discussed' => 'Discussions and decisions',
                   'meeting' => 'Meetings', 'agent' => 'Agent work' }.freeze

    module_function

    def esc(value) = CGI.escapeHTML(value.to_s)

    def editions(archive)
      Dir[File.join(archive, '*.json')].map { |f| [File.basename(f, '.json'), JSON.parse(Journal.read(f))] }
                                      .select { |name, _| name.match?(/\A\d{4}-\d{2}-\d{2}\z/) }.sort_by(&:first)
    end

    def list(items)
      rows = items.map do |e|
        title = e['url'].to_s.empty? ? esc(e['title']) : %(<a href="#{esc(e['url'])}" target="_blank">#{esc(e['title'])}</a>)
        "<li>#{title}#{" — #{esc(e['note'])}" if e['note'] && !e['note'].empty?}</li>"
      end
      "<ul>#{rows.join}</ul>"
    end

    def extras(pub)
      did = Array(pub['did']).group_by { |d| d['category'] }
      parts = CATEGORIES.filter_map { |k, name| did[k] && "<h2>#{name}</h2>#{list(did[k])}" }
      parts << "<h2>Team context</h2>#{list(pub['context'])}" if Array(pub['context']).any?
      parts.empty? ? '' : %(<div class="more"><h2 style="margin-top:0" class="mono">What happened since the last edition</h2>#{parts.join}</div>)
    end

    def nav(prev_name, next_name)
      links = [%(<a href="index.html">Today</a>), %(<a href="archive.html">Archive</a>)]
      links.unshift(%(<a href="#{prev_name}.html">← #{prev_name}</a>)) if prev_name
      links << %(<a href="#{next_name}.html">#{next_name} →</a>) if next_name
      %(<div class="nav"><span class="who">#{esc(owner)}'s journal</span>) +
        %(<span>#{links.join}<button class="theme" id="theme" type="button">Dark mode</button></span></div>)
    end

    def owner = ENV.fetch('JOURNAL_OWNER', 'My')

    def shell(title, inner)
      css = Journal.read(Paper::PALETTE).split('/* Semantic roles').first
      %(<!doctype html><html data-theme="light"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">) +
        %(<script>#{THEME_INIT}</script><title>#{esc(title)}</title><style>#{css}#{Paper::CSS}#{CSS}</style></head><body><div class="site">#{inner}) +
        %(<div class="note">Written each weekday by an agent from #{esc(owner)}'s work sources. Private and sensitive items are left out ) +
        %(and stay in the private journal.</div></div><script>#{Paper::TIP_JS};#{THEME_TOGGLE}</script></body></html>)
    end

    # Builds the site and returns { editions:, redacted: { date => [...] } }.
    def build(archive, out)
      all = editions(archive)
      raise ArgumentError, "no editions in #{archive}" if all.empty?

      FileUtils.mkdir_p(out)
      redacted = {}
      rows = []
      all.each_with_index do |(name, data), i|
        pub, hits = Share.public_data(data)
        redacted[name] = hits if hits.any?
        pub['edition'] = i + 1
        html = shell("Journal: #{pub['heading']}",
                     nav(i.zero? ? nil : all[i - 1].first, all[i + 1]&.first) + Paper.body(pub, site: true) + extras(pub))
        File.write(File.join(out, "#{name}.html"), html, encoding: 'UTF-8')
        File.write(File.join(out, 'index.html'), html, encoding: 'UTF-8') if i == all.size - 1
        led = pub['ledger']
        open_count = Paper.open_items(led).size + led['private_open'].to_i
        rows << "<tr><td><a href=\"#{name}.html\">#{esc(pub['heading'] || name)}</a></td><td>#{open_count}</td>" \
                "<td>#{Array(led['overdue']).size}</td><td>#{Array(pub['shipped']).size}</td></tr>"
      end
      arch = %(<div class="sheet"><div class="mast"><h1>The archive</h1><span class="mono">#{all.size} editions</span></div>) +
             %(<table class="arch"><thead><tr><th>Edition</th><th>Open</th><th>Overdue</th><th>Shipped</th></tr></thead>) +
             %(<tbody>#{rows.reverse.join}</tbody></table></div>)
      File.write(File.join(out, 'archive.html'), shell('Journal archive', nav(nil, nil) + arch), encoding: 'UTF-8')
      { 'editions' => all.size, 'out' => out, 'redacted' => redacted }
    end
  end
end
