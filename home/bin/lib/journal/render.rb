# frozen_string_literal: true

module Journal
  # Renders the journal's visual briefing: one self-contained HTML page styled
  # with bb's theme variables, so it can be shown inline in a bb reply. The
  # page leaves its own background unset and draws no outer card.
  module Render
    SCHEMA = <<~JSON
      {
        "date": "2026-01-14", "heading": "Wednesday, January 14", "subtitle": "Since Tue 09:05",
        "journal_id": 12,
        "chips": [{"text": "On call: someone else", "tone": "neutral|brand|good|warn|bad"}],
        "metrics": [{"value": "9", "label": "need your action", "tone": "neutral|good|warn|bad"}],
        "focus": [{"title": "...", "url": "https://...", "why": "...", "since": "2026-01-12"}],
        "calendar": {"events": [{"start": "10:30", "end": "11:00", "title": "...", "kind": "work|personal|unanswered"}],
                     "warning": "optional line about a conflict or tomorrow"},
        "needs": [{"title": "...", "url": "...", "detail": "...", "since": "2026-01-12"}],
        "followups": [{"kind": "owe|wait", "title": "...", "url": "...", "since": "2026-01-12"}],
        "bars": [{"title": "My open PRs (13)", "parts": [{"label": "draft", "value": 7, "tone": "chart-2|bad|warn|good|brand"}]}],
        "week": [{"label": "Mon", "merged": 1, "threads": 12}],
        "shipped": [{"title": "...", "url": "...", "note": "optional suffix"}],
        "sources": [{"name": "Calendar", "status": "ok|warn|fail", "note": "optional"}]
      }
    JSON

    CHIP_CLASS = { 'brand' => 'b', 'good' => 'g', 'warn' => 'w', 'bad' => 'r' }.freeze
    SOURCE_CLASS = { 'ok' => 'g', 'warn' => 'w', 'fail' => 'r' }.freeze
    TONE_COLOR = {
      'bad' => 'var(--destructive)', 'warn' => 'var(--warning)',
      'good' => 'var(--success)', 'brand' => 'var(--brand)'
    }.freeze
    DAY_START = 8
    DAY_END = 20

    CSS = <<~CSS
      :root{--r:var(--radius,8px)}
      body{margin:0;font-family:var(--font-sans);color:var(--foreground)}
      a{color:inherit;text-decoration:none;border-bottom:1px dotted var(--muted-foreground)}
      a:hover{color:var(--brand);border-color:var(--brand)}
      .wrap{display:flex;flex-direction:column;gap:18px}
      .hdr{display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:8px}
      .hdr h1{font-size:20px;margin:0;font-weight:650;letter-spacing:-.01em}
      .sub{color:var(--muted-foreground);font-size:12px}
      .chips,.src{display:flex;gap:6px;flex-wrap:wrap}
      .chip{font-size:11px;padding:3px 8px;border-radius:999px;border:1px solid var(--border);color:var(--muted-foreground);white-space:nowrap}
      .chip.b{border-color:var(--brand);color:var(--brand)}
      .chip.w{border-color:var(--warning);color:var(--warning-text)}
      .chip.g{border-color:var(--success);color:var(--success)}
      .chip.r{border-color:var(--destructive);color:var(--destructive-text)}
      .metrics{display:grid;grid-template-columns:repeat(auto-fit,minmax(118px,1fr));gap:8px}
      .m{background:var(--surface-raised,var(--card));border-radius:var(--r);padding:12px 14px}
      .m .v{font-size:24px;font-weight:650;line-height:1.1}
      .m .l{font-size:11px;color:var(--muted-foreground);margin-top:2px}
      .m.warn .v{color:var(--warning-text)}.m.bad .v{color:var(--destructive-text)}.m.good .v{color:var(--success)}
      h2{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted-foreground);margin:0 0 8px;font-weight:600}
      .focus{display:flex;flex-direction:column;gap:6px}
      .f{display:grid;grid-template-columns:26px 1fr auto;gap:10px;align-items:start;background:var(--surface-raised,var(--card));border-radius:var(--r);padding:10px 12px;border-left:3px solid var(--brand)}
      .f .n{font-weight:700;color:var(--brand);font-size:15px}
      .f .t{font-weight:600}
      .f .why{color:var(--muted-foreground);font-size:12.5px;margin-top:2px}
      .age{align-self:start;font-size:10.5px;padding:2px 7px;border-radius:999px;white-space:nowrap;background:var(--surface-recessed,var(--muted))}
      .a0{color:var(--success)}.a1{color:var(--warning-text)}.a2{color:var(--destructive-text);font-weight:600}
      .day{position:relative;height:64px;background:var(--surface-recessed,var(--muted));border-radius:var(--r);overflow:hidden}
      .tick{position:absolute;top:0;bottom:0;border-left:1px solid var(--border);font-size:10px;color:var(--subtle-foreground,var(--muted-foreground));padding:3px 0 0 3px}
      .ev{position:absolute;top:22px;height:32px;border-radius:6px;padding:4px 7px;font-size:11px;line-height:1.2;overflow:hidden;color:var(--primary-foreground);background:var(--chart-1);box-sizing:border-box}
      .ev.personal{background:var(--chart-3)}
      .ev.unanswered{background:transparent;color:var(--warning-text);border:1px dashed var(--warning)}
      .now{position:absolute;top:0;bottom:0;border-left:2px solid var(--destructive)}
      .two{display:grid;grid-template-columns:1fr 1fr;gap:14px}
      @media (max-width:560px){.two{grid-template-columns:1fr}}
      .list{display:flex;flex-direction:column}
      .row{display:grid;grid-template-columns:1fr auto;gap:8px;padding:7px 0;border-bottom:1px solid var(--border);font-size:13px}
      .row:last-child{border-bottom:0}
      .d{color:var(--muted-foreground);font-size:12px}
      .box{background:var(--surface-raised,var(--card));border-radius:var(--r);padding:14px 16px}
      .bar{display:flex;height:12px;border-radius:6px;overflow:hidden;margin:6px 0 8px;gap:2px}
      .legend{display:flex;gap:12px;flex-wrap:wrap;font-size:11.5px;color:var(--muted-foreground)}
      .legend i{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:5px;vertical-align:-1px}
      .week{display:grid;grid-auto-flow:column;grid-auto-columns:1fr;gap:6px;align-items:end;height:110px}
      .col{display:flex;flex-direction:column;align-items:center;gap:3px;height:100%;justify-content:flex-end}
      .stk{display:flex;gap:2px;align-items:flex-end;height:80px}
      .stk span{width:11px;border-radius:3px 3px 0 0;min-height:1px}
      .col .lbl{font-size:10.5px;color:var(--muted-foreground)}
      .ship{display:flex;flex-direction:column;gap:6px;font-size:13px}
      .ship div::before{content:"\\2713";color:var(--success);font-weight:700;margin-right:8px}
      .warnline{font-size:12.5px;padding:9px 12px;border-radius:var(--r);background:color-mix(in srgb,var(--warning) 14%,transparent);color:var(--warning-text)}
    CSS

    module_function

    def esc(value) = CGI.escapeHTML(value.to_s)

    def link(title, url)
      return esc(title) if url.to_s.empty?

      %(<a href="#{esc(url)}" target="_blank">#{esc(title)}</a>)
    end

    def age(since, today)
      days = since.to_s.empty? ? 0 : (today - Date.iso8601(since)).to_i
      return '<span class="age a0">new</span>' if days <= 0

      %(<span class="age #{days <= 2 ? 'a1' : 'a2'}" title="open since #{esc(since)}">#{days}d</span>)
    end

    def hours(hhmm)
      h, m = hhmm.split(':').map(&:to_i)
      h + (m / 60.0)
    end

    def pct(hour) = ((hour.clamp(DAY_START, DAY_END) - DAY_START) * 100.0 / (DAY_END - DAY_START)).round(2)

    def color(tone, index)
      return TONE_COLOR[tone] if TONE_COLOR.key?(tone)
      return "var(--#{tone})" if tone.to_s.start_with?('chart-')

      "var(--chart-#{(index % 6) + 1})"
    end

    def header(data)
      id = data['journal_id'] ? " · cortex @#{esc(data['journal_id'])}" : ''
      chips = Array(data['chips']).map { |c| %(<span class="chip #{CHIP_CLASS[c['tone']]}">#{esc(c['text'])}</span>) }.join
      %(<div class="hdr"><div><h1>#{esc(data['heading'])}</h1><div class="sub">#{esc(data['subtitle'])}#{id}</div></div>) +
        %(<div class="chips">#{chips}</div></div>)
    end

    def metrics(data)
      return '' if Array(data['metrics']).empty?

      cells = data['metrics'].map do |m|
        %(<div class="m #{m['tone'] if %w[good warn bad].include?(m['tone'])}"><div class="v">#{esc(m['value'])}</div>) +
          %(<div class="l">#{esc(m['label'])}</div></div>)
      end
      %(<div class="metrics">#{cells.join}</div>)
    end

    def focus(data, today)
      return '' if Array(data['focus']).empty?

      rows = data['focus'].each_with_index.map do |f, i|
        %(<div class="f"><div class="n">#{i + 1}</div><div><div class="t">#{link(f['title'], f['url'])}</div>) +
          %(<div class="why">#{esc(f['why'])}</div></div>#{age(f['since'], today)}</div>)
      end
      %(<div><h2>Today's focus</h2><div class="focus">#{rows.join}</div></div>)
    end

    def calendar(data, today, now)
      cal = data['calendar'] || {}
      events = Array(cal['events'])
      ticks = (DAY_START...DAY_END).step(2).map do |h|
        %(<div class="tick" style="left:#{pct(h)}%">#{h > 12 ? h - 12 : h}#{h < 12 ? 'a' : 'p'}</div>)
      end
      blocks = events.map do |ev|
        from = hours(ev['start'])
        to = [hours(ev['end'] || ev['start']), from + 0.5].max
        %(<div class="ev #{esc(ev['kind'] || 'work')}" title="#{esc(ev['start'])} #{esc(ev['title'])}" ) +
          %(style="left:#{pct(from)}%;width:calc(#{(pct(to) - pct(from)).round(2)}% - 2px)">#{esc(ev['title'])}</div>)
      end
      nowline = now.to_date == today ? %(<div class="now" style="left:#{pct(now.hour + (now.min / 60.0))}%"></div>) : ''
      empty = events.empty? ? '<div class="d" style="padding:22px 12px;position:relative">No meetings today.</div>' : ''
      warn = cal['warning'] ? %(<div style="height:8px"></div><div class="warnline">#{esc(cal['warning'])}</div>) : ''
      %(<div><h2>Today</h2><div class="day">#{ticks.join}#{blocks.join}#{nowline}#{empty}</div>#{warn}</div>)
    end

    def lists(data, today)
      needs = Array(data['needs']).map do |n|
        %(<div class="row"><div>#{link(n['title'], n['url'])}<div class="d">#{esc(n['detail'])}</div></div>#{age(n['since'], today)}</div>)
      end
      follow = Array(data['followups']).map do |f|
        kind = f['kind'] == 'owe' ? '<b>I owe</b>' : '<span class="d">Waiting</span>'
        %(<div class="row"><div>#{kind} · #{link(f['title'], f['url'])}</div>#{age(f['since'], today)}</div>)
      end
      needs_html = needs.empty? ? '<div class="d">Nothing waiting on you.</div>' : needs.join
      follow_html = follow.empty? ? '<div class="d">Nothing open.</div>' : follow.join
      %(<div class="two"><div class="box"><h2>Needs my action</h2><div class="list">#{needs_html}</div></div>) +
        %(<div class="box"><h2>Follow-ups</h2><div class="list">#{follow_html}</div></div></div>)
    end

    def bars(data)
      cells = Array(data['bars']).map do |bar|
        parts = Array(bar['parts']).select { |p| p['value'].to_f.positive? }
        segs = parts.each_with_index.map { |p, i| %(<span style="flex:#{p['value']};background:#{color(p['tone'], i)}"></span>) }
        legend = parts.each_with_index.map do |p, i|
          %(<span><i style="background:#{color(p['tone'], i)}"></i>#{esc(p['label'])} #{esc(p['value'])}</span>)
        end
        %(<div class="box"><h2>#{esc(bar['title'])}</h2><div class="bar">#{segs.join}</div><div class="legend">#{legend.join}</div></div>)
      end
      cells.empty? ? '' : %(<div class="two">#{cells.join}</div>)
    end

    def week(data)
      days = Array(data['week'])
      return '' if days.empty?

      top_m = [days.map { |w| w['merged'].to_i }.max, 1].max
      top_t = [days.map { |w| w['threads'].to_i }.max, 1].max
      cols = days.map do |w|
        m = w['merged'].to_i
        t = w['threads'].to_i
        %(<div class="col"><div class="stk">) +
          %(<span title="#{m} PRs merged" style="height:#{(m * 80.0 / top_m).round}px;background:var(--chart-1)"></span>) +
          %(<span title="#{t} agent threads" style="height:#{(t * 80.0 / top_t).round}px;background:var(--chart-3)"></span>) +
          %(</div><div class="lbl">#{esc(w['label'])}</div></div>)
      end
      %(<div class="box"><h2>This week</h2><div class="week">#{cols.join}</div><div class="legend" style="margin-top:8px">) +
        %(<span><i style="background:var(--chart-1)"></i>PRs merged (max #{top_m})</span>) +
        %(<span><i style="background:var(--chart-3)"></i>agent threads (max #{top_t})</span></div></div>)
    end

    def shipped(data)
      rows = Array(data['shipped']).map { |s| %(<div>#{link(s['title'], s['url'])}#{", #{esc(s['note'])}" if s['note']}</div>) }
      body = rows.empty? ? '<span class="d">Nothing shipped.</span>' : rows.join
      %(<div class="box"><h2>Shipped since the last journal</h2><div class="ship">#{body}</div></div>)
    end

    def sources(data)
      return '' if Array(data['sources']).empty?

      chips = data['sources'].map do |s|
        %(<span class="chip #{SOURCE_CLASS[s['status']]}" title="#{esc(s['note'])}">#{esc(s['name'])}</span>)
      end
      %(<div><h2>Sources</h2><div class="src">#{chips.join}</div></div>)
    end

    def page(data, now: Time.now)
      today = Date.iso8601(data.fetch('date'))
      body = [
        header(data), metrics(data), focus(data, today), calendar(data, today, now), lists(data, today), bars(data),
        %(<div class="two">#{week(data)}#{shipped(data)}</div>), sources(data)
      ].join
      %(<!doctype html><html><head><meta charset="utf-8"><style>#{CSS}</style></head><body><div class="wrap">#{body}</div></body></html>)
    end
  end
end
