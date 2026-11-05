# frozen_string_literal: true

module Journal
  # The briefing as a newspaper front page in the house palette, with the whole backlog
  # drawn as tiles below it. Sized to stay under bb's 2000px inline frame.
  module Paper
    PALETTE = File.expand_path('../../../.agents/skills/house-style/palette.css', __dir__)
    STORIES = 5
    SIDE_ROWS = 3
    KINDS = [%w[action Needs\ you], %w[review Reviews], %w[owe You\ owe], %w[wait Waiting], %w[discuss Discussions],
             %w[task Tracked\ work]].freeze

    CSS = <<~CSS
      .sheet{background:var(--paper);color:var(--ink);border-radius:8px;padding:22px 24px;font-family:var(--serif);font-size:15px;line-height:1.5}
      .sheet a{color:var(--ink);text-decoration:none;border-bottom:1px solid var(--rule)}
      .sheet a:hover{color:var(--blue);border-color:var(--blue)}
      .mono{font-family:var(--mono);font-size:11px;text-transform:uppercase;letter-spacing:.1em;color:var(--ink-soft)}
      .mast{display:flex;justify-content:space-between;align-items:baseline;flex-wrap:wrap;gap:6px;border-bottom:3px double var(--rule);padding-bottom:8px}
      .mast h1{font-size:30px;margin:0;letter-spacing:-.01em;line-height:1.1}
      .chips{display:flex;gap:6px;flex-wrap:wrap;margin-top:8px}
      .chip{font-family:var(--mono);font-size:10.5px;padding:2px 8px;border-radius:999px;border:1px solid var(--rule);color:var(--ink-soft)}
      .chip.b{border-color:var(--blue);color:var(--blue)}.chip.w{border-color:var(--orange);color:var(--orange)}
      .chip.r{border-color:var(--red);color:var(--red)}.chip.g{border-color:var(--aqua);color:var(--aqua)}
      .lede{font-size:17px;line-height:1.55;margin:12px 0 10px}
      .stats{display:flex;gap:18px;flex-wrap:wrap;border-top:1px solid var(--rule);border-bottom:1px solid var(--rule);padding:6px 0;margin-bottom:12px}
      .stats b{font-family:var(--serif);font-size:20px;margin-right:5px;color:var(--ink)}
      .stats .bad b{color:var(--red)}.stats .warn b{color:var(--orange)}.stats .good b{color:var(--aqua)}
      .cols{display:grid;grid-template-columns:1.6fr 1fr;gap:22px}
      .story{border-top:1px solid var(--rule);padding:9px 0}
      .story:first-child{border-top:0;padding-top:0}
      .story h3{font-size:17.5px;margin:2px 0 3px;line-height:1.3}
      .story p{margin:0;font-size:14px;color:var(--ink-soft)}
      .late{color:var(--red)}
      .side{border-left:1px solid var(--rule);padding-left:18px;font-size:13.5px;line-height:1.45}
      .side h4{font-family:var(--mono);font-size:11px;text-transform:uppercase;letter-spacing:.1em;margin:0 0 5px;color:var(--blue)}
      .side ul{margin:0 0 13px;padding-left:16px}.side li{margin-bottom:2px}
      .side .warnline{color:var(--orange)}
      .more-rows{margin:-9px 0 13px}
      .more-rows summary{cursor:pointer;color:var(--blue);list-style:none;padding-left:16px}
      .more-rows summary::-webkit-details-marker{display:none}
      .more-rows summary::before{content:"+ "}.more-rows[open] summary::before{content:"− "}
      .more-rows ul{margin:4px 0 0}
      .weather{background:var(--deep);border-radius:6px;padding:12px 14px;margin-bottom:14px}
      .weather b{font-size:26px}
      .weather.wide{display:grid;grid-template-columns:1fr 230px;gap:16px;align-items:start}
      .weather .trend{padding-top:14px}
      @media(max-width:560px){.weather.wide{grid-template-columns:1fr}}
      .weather button{font:inherit;color:inherit;background:none;border:0;padding:0;cursor:pointer;text-align:left}
      .weather .big:hover,.weather .key:hover{color:var(--blue)}
      .weather .late{color:var(--red)}
      .weather .on{text-decoration:underline;text-underline-offset:3px}
      .weather .move{font-size:10.5px;margin:2px 0 8px}
      .mix{display:flex;height:9px;border-radius:4px;overflow:hidden;gap:2px}
      .mix .seg{height:9px;min-width:4px}.mix .seg:hover,.mix .seg.on{outline:2px solid var(--ink);outline-offset:-2px}
      .keys{display:flex;flex-wrap:wrap;gap:2px 10px;margin:6px 0 2px;font-size:12px}
      .keys i{display:inline-block;width:8px;height:8px;border-radius:2px;margin-right:4px}
      .act{font-size:13px;line-height:1.4;margin:8px 0 4px}.act code{font-size:11.5px;background:var(--card);padding:0 4px;border-radius:3px}
      .why summary{cursor:pointer;color:var(--blue);font-size:10.5px;list-style:none}.why summary::-webkit-details-marker{display:none}
      .why p{font-size:12.5px;line-height:1.45;margin:6px 0 0;color:var(--ink-soft)}
      .shown{font-size:10.5px;font-weight:400;margin-left:8px;color:var(--blue)}
      .map[data-filter^="kind-"] .grp{opacity:.22}
      .map[data-filter="kind-action"] .grp[data-kind="action"],.map[data-filter="kind-review"] .grp[data-kind="review"],
      .map[data-filter="kind-owe"] .grp[data-kind="owe"],.map[data-filter="kind-wait"] .grp[data-kind="wait"],
      .map[data-filter="kind-discuss"] .grp[data-kind="discuss"],.map[data-filter="kind-task"] .grp[data-kind="task"]{opacity:1}
      .map[data-filter="overdue"] .tiles a:not(.t4){opacity:.15}
      .map[data-filter="overdue"] .grp:not(:has(.t4)){opacity:.22}
      .ilist{margin-top:10px}.ilist summary{cursor:pointer;color:var(--blue);list-style:none}
      .ilist summary::-webkit-details-marker{display:none}.ilist summary::before{content:"+ "}.ilist[open] summary::before{content:"− "}
      .ilist table{width:100%;border-collapse:collapse;font-size:13px;margin-top:6px}
      .ilist th{font-family:var(--mono);font-size:10.5px;text-transform:uppercase;letter-spacing:.08em;color:var(--ink-soft);text-align:left;font-weight:500}
      .ilist td,.ilist th{border-bottom:1px solid var(--rule-soft);padding:4px 6px 4px 0;vertical-align:top}
      .ilist .jid{font-family:var(--mono);font-size:12px;font-weight:600;white-space:nowrap}
      .ilist .seen,.ilist .st{font-family:var(--mono);font-size:11px;white-space:nowrap;color:var(--ink-soft)}
      .ilist td:nth-child(3){white-space:nowrap}
      .ilist td i{display:inline-block;width:8px;height:8px;border-radius:2px;margin-right:5px}
      .ilist .hid{font-size:10.5px;margin:6px 0 0}
      .map[data-filter^="kind-"] .ilist tbody tr{display:none}
      .map[data-filter="kind-action"] .ilist tr[data-kind="action"],.map[data-filter="kind-review"] .ilist tr[data-kind="review"],
      .map[data-filter="kind-owe"] .ilist tr[data-kind="owe"],.map[data-filter="kind-wait"] .ilist tr[data-kind="wait"],
      .map[data-filter="kind-discuss"] .ilist tr[data-kind="discuss"],.map[data-filter="kind-task"] .ilist tr[data-kind="task"]{display:table-row}
      .map[data-filter="overdue"] .ilist tbody tr:not(.late){display:none}
      .map{margin-top:16px;border-top:3px double var(--rule);padding-top:10px}
      .map h2{font-size:19px;margin:0 0 8px}
      .grp{display:grid;grid-template-columns:96px 1fr;gap:10px;align-items:start;margin-bottom:7px}
      .grp .lbl{font-size:12.5px;line-height:1.2}.grp .lbl b{font-size:17px;display:block}
      .tiles{display:flex;flex-wrap:wrap;gap:3px}
      .tiles a{display:block;width:12px;height:12px;border-radius:2px;border:0}
      .tiles a:hover{outline:2px solid var(--ink)}
      .t0{background:color-mix(in srgb,var(--aqua) 40%,transparent)}.t1{background:var(--aqua-fill)}
      .t2{background:color-mix(in srgb,var(--orange) 55%,transparent)}.t3{background:var(--orange)}.t4{background:var(--red)}
      .legend{display:flex;gap:12px;flex-wrap:wrap;margin-top:6px}
      .legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px}
      #tip{min-height:20px;font-size:13.5px;margin-top:8px;color:var(--ink-soft)}
      .foot{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-top:12px;border-top:1px solid var(--rule);padding-top:8px}
      .reply{font-family:var(--mono);font-size:11.5px;color:var(--ink-soft)}
      .src{display:flex;gap:5px;flex-wrap:wrap}
      @media(max-width:560px){.cols{grid-template-columns:1fr}.side{border-left:0;padding-left:0}.grp{grid-template-columns:1fr}}
    CSS
    # Hovering a tile names it; the weather's buttons pick tiles out of the map, and clicking one again shows all.
    TIP_JS = <<~JS.tr("\n", ' ')
      document.querySelectorAll('.tiles a').forEach(t=>t.addEventListener('mouseenter',()=>
      document.getElementById('tip').textContent=t.dataset.t));
      (function(){var m=document.getElementById('backlog'),n=document.getElementById('shown');if(!m)return;
      var bs=document.querySelectorAll('[data-filter]');bs.forEach(function(b){b.addEventListener('click',function(){
      var f=b.dataset.filter;if(f==='all'||m.dataset.filter===f)f='';m.dataset.filter=f;
      bs.forEach(function(x){x.classList.toggle('on',f!==''&&x.dataset.filter===f)});
      n.textContent=f?'showing '+b.textContent.trim().replace(/^\d+\s*/,'')+' · click again for all':'';
      if(f)m.scrollIntoView({behavior:'smooth',block:'start'})})})})();
    JS
    CHIP = { 'brand' => 'b', 'warn' => 'w', 'bad' => 'r', 'good' => 'g', 'ok' => 'g', 'fail' => 'r' }.freeze

    module_function

    def esc(value) = CGI.escapeHTML(value.to_s)

    def link(title, url)
      return esc(title) if url.to_s.empty?
      return %(<a href="#{esc(url)}">#{esc(title)}</a>) if url.start_with?('cortex:')

      %(<a href="#{esc(url)}" target="_blank">#{esc(title)}</a>)
    end

    # Its own link, else the Cortex desktop app at its task: cortex://app/task/<id> opens the installed app.
    def href(item)
      return item['url'] unless item['url'].to_s.empty?

      id = Array(item['cortex']).first || item['title'].to_s[/\A@(\d+)\b/, 1]
      id ? "cortex://app/task/#{id}" : nil
    end

    def palette
      css = Journal.read(PALETTE)
      css.sub(/\A.*?display=swap"\);/m, '').split('/* Semantic roles').first
    end

    def fonts = Journal.read(PALETTE)[/@import url\("[^"]+"\);/].to_s

    def open_items(ledger) = %w[overdue due_today new waiting backlog].flat_map { |k| Array(ledger[k]) }

    def masthead(data)
      right = [data['heading'], data['edition'] && "Edition #{data['edition']}", data['journal_id'] && "cortex @#{data['journal_id']}"]
      chips = Array(data['chips']).map { |c| %(<span class="chip #{CHIP[c['tone']]}">#{esc(c['text'])}</span>) }.join
      %(<div class="mast"><h1>The Morning Edge</h1><span class="mono">#{esc(right.compact.join(' · '))}</span></div>) +
        (chips.empty? ? '' : %(<div class="chips">#{chips}</div>))
    end

    def stats(data)
      cells = Array(data['metrics']).map { |m| %(<span class="mono #{esc(m['tone'])}"><b>#{esc(m['value'])}</b>#{esc(m['label'])}</span>) }
      cells.empty? ? '' : %(<div class="stats">#{cells.join}</div>)
    end

    def stories(data, by_id)
      Array(data['focus']).first(STORIES).map do |f|
        item = by_id[f['id'].to_i] || {}
        meta = ["J-#{f['id']}", item['age'] && "open #{days(item['age'])}", item['private'] && 'private'].compact.join(' · ')
        late = item['days_overdue'] ? %( <span class="late">· #{days(item['days_overdue'])} late</span>) : ''
        %(<div class="story"><span class="mono">#{esc(meta)}#{late}</span><h3>#{link(f['title'], f['url'].to_s.empty? ? href(item) : f['url'])}</h3><p>#{esc(f['why'])}</p></div>)
      end.join
    end

    STALE_DAYS = 30
    KIND_TONE = { 'action' => 'red', 'review' => 'orange', 'owe' => 'purple', 'wait' => 'blue', 'discuss' => 'green',
                  'task' => 'aqua' }.freeze

    # Open items per journal (solid) and overdue (dashed); each point says its date and counts on hover.
    def sparkline(trend, width: 220, height: 38)
      points = Array(trend).select { |t| t['open'] }
      return '' if points.size < 2

      lo, hi = points.flat_map { |t| [t['open'].to_i, t['overdue']].compact.map(&:to_i) }.minmax
      span = [hi - lo, 1].max
      x = ->(i) { (i * width.to_f / (points.size - 1)).round(1) }
      y = ->(v) { (height - ((v.to_i - lo) * height.to_f / span)).round(1) }
      # Snapshots without an overdue count predate the ledger and counted differently; they draw grey.
      cut = points.index { |t| t.key?('overdue') } || points.size
      coords = points.each_with_index.map { |t, i| "#{x.call(i)},#{y.call(t['open'])}" }
      before = cut.positive? ? %(<polyline points="#{coords.first(cut + 1).join(' ')}" fill="none" stroke="var(--ink-soft)" ) +
                               %(stroke-width="1.5" opacity=".6"/>) : ''
      line = coords.drop(cut).join(' ')
      late = points.each_with_index.select { |t, _| t['overdue'] }
      late_line = late.size > 1 ? %(<polyline points="#{late.map { |t, i| "#{x.call(i)},#{y.call(t['overdue'])}" }.join(' ')}" ) +
                                  %(fill="none" stroke="var(--red)" stroke-width="1.5" stroke-dasharray="3 3"/>) : ''
      dots = points.each_with_index.map do |t, i|
        label = "#{pretty(t['date'])}: #{t['open']} open#{", #{t['overdue']} overdue" if t['overdue']}"
        %(<circle cx="#{x.call(i)}" cy="#{y.call(t['open'])}" r="5" fill="transparent"><title>#{esc(label)}</title></circle>)
      end
      %(<svg width="#{width}" height="#{height + 4}" style="display:block;margin-top:6px;overflow:visible">) +
        %(#{before}<polyline points="#{line}" fill="none" stroke="var(--orange)" stroke-width="2"/>#{late_line}#{dots.join}</svg>)
    end

    def change_line(trend, open)
      prev = Array(trend).select { |t| t.key?('overdue') }[-2]
      return 'first ledger edition' unless prev

      delta = open - prev['open'].to_i
      word = delta.positive? ? "up #{delta}" : delta.negative? ? "down #{-delta}" : 'unchanged'
      "#{word} since #{pretty(prev['date'])}"
    end

    # What the backlog is made of, how it moved, and what to do first; every part filters the map below.
    def weather(data, items)
      ledger = data['ledger']
      trend = Array(ledger['trend'])
      overdue = Array(ledger['overdue'])
      counts = KINDS.filter_map do |kind, name|
        n = items.count { |i| i['kind'] == kind }
        [kind, name, n] if n.positive?
      end
      segs = counts.map do |kind, name, n|
        %(<button type="button" class="seg" style="flex:#{n};background:var(--#{KIND_TONE[kind]})" data-filter="kind-#{kind}" ) +
          %(title="#{n} #{esc(name.downcase)}: show them in the map"></button>)
      end
      keys = counts.map do |kind, name, n|
        %(<button type="button" class="key" data-filter="kind-#{kind}"><i style="background:var(--#{KIND_TONE[kind]})"></i>#{n} #{esc(name.downcase)}</button>)
      end
      stale, late = overdue.partition { |i| i['days_overdue'].to_i > STALE_DAYS }
      first = late.max_by { |i| i['days_overdue'].to_i }
      act = if first
              "Start with #{link("J-#{first['id']}", href(first))}, #{days(first['days_overdue'])} late. " \
                'Reply <code>done</code> for finished items, <code>drop</code> for ones that are not yours, <code>snooze</code> for what can wait.'
            elsif items.any? then 'Nothing is overdue. Clear what is due today, then the oldest backlog.'
            else 'Nothing is open.'
            end
      unless stale.empty?
        ids = stale.sort_by { |i| -i['days_overdue'].to_i }.first(4).map { |i| link("J-#{i['id']}", href(i)) }.join(', ')
        act += " #{stale.size} #{stale.size == 1 ? 'item is' : 'items are'} over #{STALE_DAYS} days late (#{ids}); " \
               '<code>drop</code> them if they no longer matter.'
      end
      spark = sparkline(trend)
      grey = trend.any? { |t| !t.key?('overdue') } ? '; grey: before the ledger, counted differently' : ''
      span = trend.size > 1 ? "one point per edition, #{pretty(trend.first['date'])} to #{pretty(trend.last['date'])}; hover for counts#{grey}" : ''
      %(<div class="weather wide"><div><div class="mono">Backlog weather</div>) +
        %(<div><button type="button" class="big" data-filter="all" title="Show every open item in the map"><b>#{items.size}</b> open</button> · ) +
        %(<button type="button" class="big late" data-filter="overdue" title="Show only overdue items in the map">#{overdue.size} overdue</button></div>) +
        %(<div class="mono move">#{esc(change_line(trend, items.size))} · #{Array(ledger['new']).size} new · ) +
        %(#{Array(ledger['closed_recently']).size} closed</div>) +
        %(<div class="mix">#{segs.join}</div><div class="keys">#{keys.join}</div>) +
        %(<p class="act">#{act}</p>) +
        %(<details class="why"><summary class="mono">What is this?</summary><p>Every open item in your ledger, from all sources: ) +
        %(questions waiting on you, reviews, promises, people you wait on, discussions and tracked work. The line is how many were ) +
        %(open at each edition, and the dashed line how many of those were overdue. It falls when you close more than arrives. ) +
        %(Click a colour, a count or "overdue" to pick those tiles out in the map below; click it again to show everything.</p></details></div>) +
        %(<div class="trend">#{spark}#{spark.empty? ? '' : %(<div class="mono" style="font-size:10px">#{esc(span)}</div>)}</div></div>)
    end

    def sidebar(data, items)
      ledger = data['ledger']
      cal = data['calendar'] || {}
      agenda = Array(cal['events']).reject { |e| e['kind'] == 'personal' }.map do |e|
        tag = e['kind'] == 'unanswered' ? ' <span class="warnline">(not answered)</span>' : ''
        %(<li><b>#{esc(e['start'])}</b> #{link(clip(e['title'], 48), e['url'])}#{tag}</li>)
      end
      agenda << %(<li class="warnline">#{esc(cal['warning'])}</li>) if cal['warning']
      waits = Array(ledger['waiting']).map do |i|
        %(<li>#{link(clip(i['title'], 64), href(i))} <span class="mono">#{i['age']}d#{' · nudge' if i['nudge']}</span></li>)
      end
      closed = Array(ledger['closed_recently']).map { |i| %(<li>#{link(clip(i['title'], 64), href(i))}</li>) }
      shipped = Array(data['shipped']).map { |s| %(<li>#{link(s['title'], s['url'])}</li>) }
      [section('On the agenda', agenda, limit: agenda.size), section('Still waiting on', waits),
       section('Shipped', shipped), section('Corrections', closed, 'Closed since the last edition')].join
    end

    # Shows the first SIDE_ROWS rows; the rest sit behind an "and N more" toggle that expands in place.
    def section(title, rows, hint = nil, limit: SIDE_ROWS)
      return '' if rows.empty?

      shown, rest = rows.first(limit), rows.drop(limit)
      more = rest.empty? ? '' : %(<details class="more-rows"><summary class="mono">and #{rest.size} more</summary><ul>#{rest.join}</ul></details>)
      %(<h4 title="#{esc(hint)}">#{title}</h4><ul>#{shown.join}</ul>#{more})
    end

    def days(count) = count.to_i == 1 ? '1 day' : "#{count} days"

    # Cuts at a word boundary so titles never end mid-word.
    def clip(text, max)
      text = text.to_s
      text.length <= max ? text : "#{text[0, max].sub(/\s+\S*\z/, '')}…"
    end

    def tone(item)
      return 't4' if item['days_overdue']

      age = item['age'].to_i
      if age >= 10 then 't3'
      elsif age >= 5 then 't2'
      elsif age >= 2 then 't1'
      else 't0'
      end
    end

    def backlog_map(items)
      groups = KINDS.filter_map do |kind, name|
        list = items.select { |i| i['kind'] == kind }.sort_by { |i| -i['age'].to_i }
        next if list.empty?

        tiles = list.map do |i|
          tip = ["J-#{i['id']}", i['title'], "open #{i['age']}d", i['days_overdue'] && "#{i['days_overdue']}d late",
                 i['private'] && 'private'].compact.join(' · ')
          url = href(i)
          target = url.to_s.start_with?('http') ? ' target="_blank"' : ''
          %(<a class="#{tone(i)}" href="#{esc(url || '#')}"#{target} data-t="#{esc(tip)}"></a>)
        end
        %(<div class="grp" data-kind="#{kind}"><div class="lbl"><b>#{list.size}</b>#{name}</div><div class="tiles">#{tiles.join}</div></div>)
      end
      legend = [%w[t0 new], ['t1', '2 to 4 days'], ['t2', '5 to 9 days'], ['t3', '10 days or more'], %w[t4 overdue]]
               .map { |c, l| %(<span class="mono"><i class="#{c}"></i>#{l}</span>) }.join
      %(<div class="map" id="backlog"><h2>The backlog, at a glance <span class="mono shown" id="shown"></span></h2>#{groups.join}) +
        %(<div class="legend">#{legend}</div><div id="tip">Hover a tile to read it; click to open it.</div>#{item_list(items)}</div>)
    end

    KIND_LABEL = KINDS.to_h.transform_values(&:downcase).freeze

    def status_text(item)
      return [%(<span class="late">#{days(item['days_overdue'])} late</span>), 'late'] if item['days_overdue']
      return ["due #{pretty(item['due'])}", ''] if item['due']

      ["open #{days(item['age'])}", '']
    end

    # Every open item, oldest first, for finding an id; private items are never listed, only counted.
    def item_list(items)
      shown, hidden = items.partition { |i| !i['private'] }
      return '' if shown.empty?

      rows = shown.sort_by { |i| [i['first_seen'].to_s, i['id'].to_i] }.map do |i|
        text, cls = status_text(i)
        seen = i['first_seen'] ? pretty(i['first_seen']) : ''
        %(<tr data-kind="#{esc(i['kind'])}" class="#{cls}"><td class="jid">J-#{esc(i['id'])}</td><td class="seen">#{esc(seen)}</td>) +
          %(<td><i style="background:var(--#{KIND_TONE[i['kind']] || 'ink-soft'})"></i>#{esc(KIND_LABEL[i['kind']])}</td>) +
          %(<td>#{link(i['title'], href(i))}</td><td class="st">#{text}</td></tr>)
      end
      note = hidden.empty? ? '' : %(<p class="mono hid">#{hidden.size} private #{hidden.size == 1 ? 'item is' : 'items are'} not listed.</p>)
      %(<details class="ilist"><summary class="mono">Every open item, oldest first (#{shown.size})</summary>) +
        %(<table><thead><tr><th>Id</th><th>Seen</th><th>Kind</th><th>Item</th><th>Status</th></tr></thead>) +
        %(<tbody>#{rows.join}</tbody></table>#{note}</details>)
    end

    def footer(data, site)
      sources = Array(data['sources']).map do |s|
        %(<span class="chip #{CHIP[s['status']]}" title="#{esc(s['note'])}">#{esc(s['name'])}</span>)
      end
      hidden = data.dig('ledger', 'private_open').to_i
      note = if site then hidden.positive? ? "#{hidden} private #{hidden == 1 ? 'item is' : 'items are'} not shown here." : ''
             else 'Reply in the journal thread: done 12 15 · drop 20 not mine · snooze 31 mon · private 7 · share 7'
             end
      %(<div class="foot"><span class="reply">#{esc(note)}</span><div class="src">#{sources.join}</div></div>)
    end

    def pretty(iso) = Date.iso8601(iso).strftime('%b %-d')

    def body(data, site: false)
      items = open_items(data.fetch('ledger'))
      by_id = items.to_h { |i| [i['id'], i] }
      %(<div class="sheet">#{masthead(data)}<p class="lede">#{esc(data['lede'])}</p>#{stats(data)}#{weather(data, items)}) +
        %(<div class="cols"><div>#{stories(data, by_id)}</div><div class="side">#{sidebar(data, items)}</div></div>) +
        %(#{backlog_map(items)}#{footer(data, site)}</div>#{site ? '' : "<script>#{TIP_JS}</script>"})
    end

    def head = %(<meta charset="utf-8"><style>#{fonts}#{palette}#{CSS}</style>)

    def page(data) = %(<!doctype html><html><head>#{head}</head><body>#{body(data)}</body></html>)
  end
end
