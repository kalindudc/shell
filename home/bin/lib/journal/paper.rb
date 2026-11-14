# frozen_string_literal: true

module Journal
  # The briefing as a newspaper front page, The Morning Edge, set in the house kit: a nameplate,
  # the stats strip, stories beside a sidebar, then the backlog's weather and its tile map. One
  # body serves the briefing shown in bb (Paper.page) and every edition of the shareable site.
  module Paper
    STORIES = 5
    SIDE_ROWS = 3
    STALE_DAYS = 30
    KINDS = [['action', 'Needs you'], %w[review Reviews], ['owe', 'You owe'], %w[wait Waiting], %w[discuss Discussions],
             ['task', 'Tracked work']].freeze
    KIND_TONE = { 'action' => 'red', 'review' => 'orange', 'owe' => 'purple', 'wait' => 'blue', 'discuss' => 'green',
                  'task' => 'aqua' }.freeze
    KIND_LABEL = KINDS.to_h.transform_values(&:downcase).freeze
    CHIP = { 'brand' => 'info', 'warn' => 'warn', 'bad' => 'bad', 'good' => 'good', 'ok' => 'good', 'fail' => 'bad' }.freeze
    WORDS = %w[No One Two Three Four Five Six Seven Eight Nine Ten].freeze
    PARTS = [['front', 'Front page'], %w[backlog Backlog]].freeze
    # The briefing follows bb's theme: bb sets --background on the frame's root, light or dark.
    THEME_JS = <<~JS.tr("\n", ' ')
      (()=>{const r=document.documentElement,c=document.createElement('canvas').getContext('2d',{willReadFrequently:true});
      const sync=()=>{const v=getComputedStyle(r).getPropertyValue('--background').trim();if(!v)return;
      c.clearRect(0,0,1,1);c.fillStyle='#808080';c.fillStyle=v;c.fillRect(0,0,1,1);const[R,G,B]=c.getImageData(0,0,1,1).data;
      r.dataset.theme=0.2126*R+0.7152*G+0.0722*B<128?'dark':'light'};sync();addEventListener('DOMContentLoaded',sync);
      new MutationObserver(sync).observe(r,{attributes:true,attributeFilter:['style','class']});
      matchMedia('(prefers-color-scheme: dark)').addEventListener('change',sync)})();
    JS

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

    def open_items(ledger) = %w[overdue due_today new waiting backlog].flat_map { |k| Array(ledger[k]) }

    def days(count) = count.to_i == 1 ? '1 day' : "#{count} days"

    def pretty(iso) = Date.iso8601(iso).strftime('%b %-d')

    def word(count) = WORDS.fetch(count, count.to_s)

    # Cuts at a word boundary so titles never end mid-word.
    def clip(text, max)
      text = text.to_s
      text.length <= max ? text : "#{text[0, max].sub(/\s+\S*\z/, '')}…"
    end

    def owner = ENV.fetch('JOURNAL_OWNER', '')

    def journal_name = owner.empty? ? 'Daily journal' : "#{owner}'s journal"

    def masthead(data, editions: '')
      path = [journal_name, data['heading'], data['edition'] && "Edition #{data['edition']}",
              data['journal_id'] && "cortex @#{data['journal_id']}"].compact
      kicker = path.map { |p| "<span>#{esc(p)}</span>" }.join('<span class="sep">/</span>')
      chips = Array(data['chips']).map { |c| %(<li><span class="#{['state', CHIP[c['tone']]].compact.join(' ')}">#{esc(c['text'])}</span></li>) }
      %(<header class="masthead" id="top" tabindex="-1"><div class="dateline wide"><p class="kicker">#{kicker}</p>#{editions}</div>) +
        %(<h1 class="nameplate wide">The Morning <em>Edge</em></h1>#{%(<ul class="chips wide">#{chips.join}</ul>) unless chips.empty?}) +
        %(<p class="lede wide" data-content>#{esc(data['lede'])}</p>#{brief(data)}</header>)
    end

    # The stats strip is the page's brief: the five numbers a reader needs first.
    def brief(data)
      cells = Array(data['metrics']).map do |m|
        tone = %w[bad warn good].include?(m['tone']) ? %( class="#{m['tone']}") : ''
        %(<div#{tone}><dt>#{esc(m['label'])}</dt><dd>#{esc(m['value'])}</dd></div>)
      end
      cells.empty? ? '' : %(<dl class="brief strip wide">#{cells.join}</dl>)
    end

    def part(id, number, label, heading, body, figure: nil)
      said = figure ? %( data-figure="#{esc(figure)}") : ''
      %(<section class="part" id="#{id}" tabindex="-1" aria-labelledby="#{id}-h"#{said}><header>) +
        %(<p class="label"><span class="n">#{number}</span><span class="sep">/</span>#{esc(label)}</p>) +
        %(<h2 id="#{id}-h">#{heading}</h2></header>#{body}</section>)
    end

    def stories(data, by_id)
      Array(data['focus']).first(STORIES).map do |f|
        item = by_id[f['id'].to_i] || {}
        meta = ["J-#{f['id']}", item['age'] && "open #{days(item['age'])}", item['private'] && 'private'].compact.join(' · ')
        late = item['days_overdue'] ? %( <span class="late">· #{days(item['days_overdue'])} late</span>) : ''
        url = f['url'].to_s.empty? ? href(item) : f['url']
        %(<article class="story"><p class="meta">#{esc(meta)}#{late}</p><h3>#{link(f['title'], url)}</h3><p>#{esc(f['why'])}</p></article>)
      end.join
    end

    def sidebar(data, site:)
      ledger = data['ledger']
      cal = data['calendar'] || {}
      agenda = Array(cal['events']).reject { |e| e['kind'] == 'personal' }.map do |e|
        tag = e['kind'] == 'unanswered' ? ' <span class="late">(not answered)</span>' : ''
        %(<li><b>#{esc(e['start'])}</b> #{link(clip(e['title'], 48), e['url'])}#{tag}</li>)
      end
      agenda << %(<li class="late">#{esc(cal['warning'])}</li>) if cal['warning']
      waits = Array(ledger['waiting']).map do |i|
        %(<li>#{link(clip(i['title'], 64), href(i))} <span class="mono">#{i['age']}d#{' · nudge' if i['nudge']}</span></li>)
      end
      closed = Array(ledger['closed_recently']).map { |i| %(<li>#{link(clip(i['title'], 64), href(i))}</li>) }
      # The briefing shortens shipped titles to fit bb's frame; the site has the room to show them whole.
      shipped = Array(data['shipped']).map { |s| %(<li>#{link(site ? s['title'] : clip(s['title'], 64), s['url'])}</li>) }
      [section('On the agenda', agenda, limit: agenda.size), section('Still waiting on', waits),
       section('Shipped', shipped), section('Corrections', closed, 'Closed since the last edition')].join
    end

    # Shows the first SIDE_ROWS rows; the rest sit in a fold, "and N more", that opens in place.
    def section(title, rows, hint = nil, limit: SIDE_ROWS)
      return '' if rows.empty?

      shown = rows.first(limit)
      rest = rows.drop(limit)
      more = rest.empty? ? '' : %(<details class="more"><summary>and #{rest.size} more</summary><ul>#{rest.join}</ul></details>)
      title_attr = hint ? %( title="#{esc(hint)}") : ''
      %(<section><h3 class="label"#{title_attr}>#{title}</h3><ul>#{shown.join}</ul>#{more}</section>)
    end

    # Open items per edition (solid) and overdue (dashed); each point says its date and counts.
    def sparkline(trend, width: 240, height: 44)
      points = Array(trend).select { |t| t['open'] }
      return '' if points.size < 2

      lo, hi = points.flat_map { |t| [t['open'].to_i, t['overdue']].compact.map(&:to_i) }.minmax
      span = [hi - lo, 1].max
      x = ->(i) { (i * width.to_f / (points.size - 1)).round(1) }
      y = ->(v) { (height - ((v.to_i - lo) * height.to_f / span)).round(1) }
      # Snapshots without an overdue count predate the ledger and counted differently; they draw grey.
      cut = points.index { |t| t.key?('overdue') } || points.size
      coords = points.each_with_index.map { |t, i| "#{x.call(i)},#{y.call(t['open'])}" }
      before = cut.positive? ? %(<polyline points="#{coords.first(cut + 1).join(' ')}" fill="none" stroke="var(--ink-soft)" stroke-width="1.5" opacity=".6"/>) : ''
      late = points.each_with_index.select { |t, _| t['overdue'] }
      late_line = if late.size > 1
                    %(<polyline points="#{late.map { |t, i| "#{x.call(i)},#{y.call(t['overdue'])}" }.join(' ')}" ) +
                      %(fill="none" stroke="var(--bad)" stroke-width="1.5" stroke-dasharray="3 3"/>)
                  else
                    ''
                  end
      dots = points.each_with_index.map do |t, i|
        label = "#{pretty(t['date'])}: #{t['open']} open#{", #{t['overdue']} overdue" if t['overdue']}"
        %(<circle cx="#{x.call(i)}" cy="#{y.call(t['open'])}" r="5" fill="transparent"><title>#{esc(label)}</title></circle>)
      end
      first = points.first
      last = points.last
      said = "Open items per edition: #{first['open']} on #{pretty(first['date'])}, #{last['open']} on #{pretty(last['date'])}"
      %(<svg viewBox="0 0 #{width} #{height + 4}" role="img" aria-label="#{esc(said)}">) +
        %(#{before}<polyline points="#{coords.drop(cut).join(' ')}" fill="none" stroke="var(--tint)" stroke-width="2"/>#{late_line}#{dots.join}</svg>)
    end

    def change_line(trend, open)
      prev = Array(trend).select { |t| t.key?('overdue') }[-2]
      prev ? since(open, prev) : 'first ledger edition'
    end

    def since(open, prev)
      delta = open - prev['open'].to_i
      change = if delta.positive? then "up #{delta}"
               elsif delta.negative? then "down #{-delta}"
               else 'unchanged'
               end
      "#{change} since #{pretty(prev['date'])}"
    end

    # How the open count moved. The briefing counts the whole ledger, as its trend does; the site
    # counts only what it shows, so it compares with the previous edition's public count.
    def movement(ledger, open, site:)
      change = if !site then change_line(ledger['trend'], open)
               elsif ledger['previous'] then since(open, ledger['previous'])
               else 'first edition on this site'
               end
      "#{change} · #{Array(ledger['new']).size} new · #{Array(ledger['closed_recently']).size} closed"
    end

    def kind_counts(items)
      KINDS.filter_map do |kind, name|
        n = items.count { |i| i['kind'] == kind }
        [kind, name, n] if n.positive?
      end
    end

    def first_action(items, overdue)
      stale, late = overdue.partition { |i| i['days_overdue'].to_i > STALE_DAYS }
      first = late.max_by { |i| i['days_overdue'].to_i }
      act = if first
              "Start with #{link("J-#{first['id']}", href(first))}, #{days(first['days_overdue'])} late. " \
                'Reply <code>done</code> for finished items, <code>drop</code> for ones that are not yours, <code>snooze</code> for what can wait.'
            elsif items.any? then 'Nothing is overdue. Clear what is due today, then the oldest backlog.'
            else
              'Nothing is open.'
            end
      return act if stale.empty?

      ids = stale.sort_by { |i| -i['days_overdue'].to_i }.first(4).map { |i| link("J-#{i['id']}", href(i)) }.join(', ')
      "#{act} #{stale.size} #{stale.size == 1 ? 'item is' : 'items are'} over #{STALE_DAYS} days late (#{ids}); " \
        '<code>drop</code> them if they no longer matter.'
    end

    def mix(counts)
      segs = counts.map do |kind, name, n|
        %(<span style="flex:#{n};background:var(--#{KIND_TONE[kind]})" data-filter="kind-#{kind}" title="#{n} #{esc(name.downcase)}"></span>)
      end
      keys = counts.map do |kind, name, n|
        %(<li><button type="button" data-filter="kind-#{kind}" aria-pressed="false"><i style="background:var(--#{KIND_TONE[kind]})"></i>) +
          %(#{n} #{esc(name.downcase)}</button></li>)
      end
      %(<div class="stackbar" aria-hidden="true">#{segs.join}</div><ul class="legend" aria-label="Pick a kind out in the map">#{keys.join}</ul>)
    end

    # What the backlog is made of, how it moved, and what to do first; every part filters the map.
    def weather(data, items, site:)
      ledger = data['ledger']
      trend = Array(ledger['trend'])
      overdue = Array(ledger['overdue'])
      spark = sparkline(trend)
      grey = trend.any? { |t| !t.key?('overdue') } ? '; grey: before the ledger, counted differently' : ''
      whole = site ? '; the line counts private items too' : ''
      span = trend.size > 1 ? "one point per edition, #{pretty(trend.first['date'])} to #{pretty(trend.last['date'])}#{whole}#{grey}" : ''
      now = %(<p class="now"><button type="button" data-filter="all" aria-pressed="false" title="Show every open item in the map"><b>#{items.size}</b>open</button>) +
            %(<span aria-hidden="true">·</span><button type="button" class="late" data-filter="overdue" aria-pressed="false" ) +
            %(title="Show only overdue items in the map"><b>#{overdue.size}</b>overdue</button></p>)
      move = %(<p class="label move">#{esc(movement(ledger, items.size, site: site))}</p>)
      scope = site ? ' This copy leaves private items out of the counts, the colours and the map; the line still counts them.' : ''
      why = %(<details class="more"><summary>What is this?</summary><p>Every open item in your ledger, from all sources: questions waiting on you, ) +
            %(reviews, promises, people you wait on, discussions and tracked work. The line is how many were open at each edition, ) +
            %(and the dashed line how many of those were overdue. It falls when you close more than arrives. Press a colour, a count ) +
            %(or "overdue" to pick those tiles out in the map below; press it again to show everything.#{scope}</p></details>)
      trend_html = spark.empty? ? '' : %(<div class="trend">#{spark}<p class="mono">#{esc(span)}</p></div>)
      %(<figure class="fig wide weather"><div class="body"><div>#{now}#{move}#{mix(kind_counts(items))}) +
        %(<p class="act">#{first_action(items, overdue)}</p>#{why}</div>#{trend_html}</div>) +
        %(<figcaption><b>Backlog weather.</b> What the open items are, and how their count moved from edition to edition.</figcaption></figure>)
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

    def tiles(list)
      list.map do |i|
        tip = ["J-#{i['id']}", i['title'], "open #{i['age']}d", i['days_overdue'] && "#{i['days_overdue']}d late",
               i['private'] && 'private'].compact.join(' · ')
        url = href(i)
        target = url.to_s.start_with?('http') ? ' target="_blank"' : ''
        %(<a class="#{tone(i)}" href="#{esc(url || '#')}"#{target} data-t="#{esc(tip)}" aria-label="#{esc(tip)}" tabindex="-1"></a>)
      end.join
    end

    def backlog_map(items, site:)
      groups = KINDS.filter_map do |kind, name|
        list = items.select { |i| i['kind'] == kind }.sort_by { |i| -i['age'].to_i }
        next if list.empty?

        %(<div class="grp" data-kind="#{kind}"><div class="lbl"><b>#{list.size}</b>#{name}</div><div class="tiles" aria-hidden="true">#{tiles(list)}</div></div>)
      end
      # The tiles are for a pointer; every one of their links is in the item list below, for every reader.
      legend = [%w[t0 new], ['t1', '2 to 4 days'], ['t2', '5 to 9 days'], ['t3', '10 days or more'], %w[t4 overdue]]
               .map { |c, l| %(<li><i class="#{c}"></i>#{l}</li>) }.join
      %(<figure class="fig wide map" id="backlog-map"><div class="body">#{groups.join}<ul class="legend">#{legend}</ul>) +
        %(<p id="tip" aria-live="polite">Point at a tile to read it; open it to follow its link.</p>#{item_list(items, site: site)}</div>) +
        %(<figcaption><b>The backlog, tile by tile.</b> One tile per open item, grouped by kind and coloured by age.) +
        %(<span class="shown" id="shown"></span></figcaption></figure>)
    end

    def status_text(item)
      return [%(<span class="late">#{days(item['days_overdue'])} late</span>), 'late'] if item['days_overdue']
      return ["due #{pretty(item['due'])}", ''] if item['due']

      ["open #{days(item['age'])}", '']
    end

    # Every open item, oldest first, for finding an id, and the way to every tile's link without a
    # pointer. The briefing is the owner's own copy, so it lists private items too; the site never does.
    def item_list(items, site:)
      shown = site ? items.reject { |i| i['private'] } : items
      return '' if shown.empty?

      rows = shown.sort_by { |i| [i['first_seen'].to_s, i['id'].to_i] }.map do |i|
        text, cls = status_text(i)
        text = "#{text} · private" if i['private']
        seen = i['first_seen'] ? pretty(i['first_seen']) : ''
        %(<tr data-kind="#{esc(i['kind'])}" class="#{cls}"><td class="jid" data-label="Id">J-#{esc(i['id'])}</td>) +
          %(<td class="seen" data-label="Seen">#{esc(seen)}</td><td data-label="Kind"><i style="background:var(--#{KIND_TONE[i['kind']] || 'ink-soft'})"></i>) +
          %(#{esc(KIND_LABEL[i['kind']])}</td><td>#{link(i['title'], href(i))}</td><td class="st" data-label="Status">#{text}</td></tr>)
      end
      %(<details class="more ilist"><summary>Every open item, oldest first (#{shown.size})</summary><div class="table"><table class="ledger">) +
        %(<thead><tr><th scope="col">Id</th><th scope="col">Seen</th><th scope="col">Kind</th><th scope="col">Item</th><th scope="col">Status</th></tr></thead>) +
        %(<tbody>#{rows.join}</tbody></table></div></details>)
    end

    def colophon(data, site)
      sources = Array(data['sources']).map do |s|
        title = s['note'].to_s.empty? ? '' : %( title="#{esc(s['note'])}")
        %(<li><span class="#{['state', CHIP[s['status']]].compact.join(' ')}"#{title}>#{esc(s['name'])}</span></li>)
      end
      hidden = data.dig('ledger', 'private_open').to_i
      note = if site
               shown = if hidden.positive?
                         "#{hidden} private #{hidden == 1 ? 'item is' : 'items are'} not shown here. "
                       else
                         ''
                       end
               "#{shown}Written each weekday by an agent from #{owner.empty? ? "its owner's" : "#{owner}'s"} work sources; " \
                 'private and sensitive items stay in the private journal.'
             else
               'Reply in the journal thread: done 12 15 · drop 20 not mine · snooze 31 mon · private 7 · share 7'
             end
      %(<div class="colophon wide"><p class="reply">#{esc(note)}</p><ul aria-label="Sources">#{sources.join}</ul></div>)
    end

    def headings(data, items)
      stories = [Array(data['focus']).size, STORIES].min
      overdue = Array(data.dig('ledger', 'overdue')).size
      front = "#{word(stories)} #{stories == 1 ? 'story' : 'stories'} <em>for today.</em>"
      backlog = "#{items.size} open, <em>#{overdue.zero? ? 'none' : overdue} overdue.</em>"
      [front, backlog]
    end

    def body(data, site: false, editions: '', extra: '')
      items = open_items(data.fetch('ledger'))
      by_id = items.to_h { |i| [i['id'], i] }
      front_h, backlog_h = headings(data, items)
      front = %(<div class="cols wide"><div class="stories">#{stories(data, by_id)}</div>) +
              %(<aside class="side" aria-label="Agenda, waiting, shipped and corrections">#{sidebar(data, site: site)}</aside></div>)
      [masthead(data, editions: editions),
       part('front', '01', 'Front page', front_h, front, figure: "the day's stories and lists of links; a drawing would only repeat them"),
       part('backlog', '02', 'Backlog', backlog_h, weather(data, items, site: site) + backlog_map(items, site: site)),
       extra, colophon(data, site)].join
    end

    def page(data)
      %(<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">) +
        %(<title>The Morning Edge: #{esc(data['heading'])}</title><style>#{Kit.inline_css}</style><script>#{THEME_JS}</script></head>) +
        %(<body class="briefing"><main class="page edge" id="main">#{body(data)}</main><script>#{Kit.script}</script></body></html>)
    end
  end
end
