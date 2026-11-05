# frozen_string_literal: true

module Journal
  # The shareable copy of a briefing. Private ledger items never leave; everything else is
  # scanned for sensitive patterns, and any entry that matches is left out and reported.
  module Share
    DEFAULT_PATTERNS = [
      /\b(salary|salaries|compensation|comp (band|numbers|review)|equity grant|promotion|promo packet)\b/i,
      /\b(performance review|impact (review|cycle)|mastery|calibration|\bPIP\b|1:1 notes?)/i,
      /\b(interview(er|s|ing)?|candidates?|recruit(er|ing)?|hiring (committee|decision)|offer letter)\b/i,
      /\b(medical|doctor|dentist|therapy|therapist|sick|leave of absence|parental leave|appointment)\b/i,
      /\b(passwords?|passphrase|secret key|credentials?|api[ _-]?keys?|access tokens?|private key|ssh key|2fa|mfa code)\b/i,
      /\b(vulnerabilit(y|ies)|exploit|zero[- ]day|CVE-\d{4}-\d+|bypass(es|ed)?)\b/i,
      /\b(budget|spend|invoice)\b|\$\s?\d/i,
      %r{slack\.com/archives/D\w+}, # direct messages
      %r{mail\.google\.com/} # email threads
    ].freeze
    LIST_KEYS = %w[focus shipped did context chips].freeze
    LEDGER_KEYS = %w[overdue due_today new waiting backlog closed_recently].freeze

    module_function

    def patterns(extra_file = File.join(Journal.home, 'sensitive.txt'))
      extra = File.exist?(extra_file) ? Journal.read(extra_file).lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') } : []
      DEFAULT_PATTERNS + extra.map { |l| Regexp.new(l, Regexp::IGNORECASE) }
    end

    def hit(value, pats)
      strings(value).each do |s|
        pats.each { |p| (m = s.match(p)) && (return m[0]) }
      end
      nil
    end

    def strings(value)
      case value
      when String then [value]
      when Hash then value.values.flat_map { |v| strings(v) }
      when Array then value.flat_map { |v| strings(v) }
      else []
      end
    end

    # Every work meeting of the day keeps its time slot; one the public copy does not list shows
    # only as "Private meeting", so the day reads right without saying what or with whom.
    def public_events(data, pub, keep)
      shown = Array(pub.dig('calendar', 'events')).select { |e| keep.call('calendar', e) }
      listed = shown.to_set { |e| [e['start'], e['end']] }
      hidden = Array(data.dig('calendar', 'events')).reject { |e| e['kind'] == 'personal' || listed.include?([e['start'], e['end']]) }
      (shown + hidden.map { |e| { 'start' => e['start'], 'end' => e['end'], 'title' => 'Private meeting', 'kind' => 'private' } })
        .sort_by { |e| e['start'].to_s }
    end

    # Counts that depend on which items are shown are recomputed from the public ledger.
    def public_metrics(data, led)
      open = %w[overdue due_today new waiting backlog].flat_map { |k| led[k] }
      counts = { 'overdue' => led['overdue'].size, 'due today' => led['due_today'].size,
                 'need you' => open.count { |i| %w[action review].include?(i['kind']) },
                 'oldest open' => "#{open.map { |i| i['age'].to_i }.max.to_i}d" }
      Array(data['metrics']).map do |m|
        m = m.slice('value', 'label', 'tone')
        counts.key?(m['label']) ? m.merge('value' => counts[m['label']].to_s) : m
      end
    end

    # Returns [public_data, redactions]. Only fields listed here reach the site.
    def public_data(data, pats: patterns)
      pub = data['public'] || {}
      redacted = []
      keep = lambda do |where, entry|
        word = hit(entry, pats)
        redacted << { 'where' => where, 'match' => word, 'title' => entry.is_a?(Hash) ? entry['title'] || entry['text'] : entry.to_s[0, 80] } if word
        word.nil?
      end

      ledger = data.fetch('ledger', {})
      private_ids = LEDGER_KEYS.flat_map { |k| Array(ledger[k]) }.select { |i| i['private'] }.to_set { |i| i['id'] }
      out_ledger = LEDGER_KEYS.to_h do |k|
        [k, Array(ledger[k]).reject { |i| i['private'] }.select { |i| keep.call("ledger.#{k} #{i['label']}", i.slice('title', 'url', 'detail')) }
                            .map { |i| i.slice('id', 'label', 'title', 'url', 'kind', 'age', 'days_overdue', 'due', 'nudge', 'first_seen', 'cortex') }]
      end
      out_ledger['trend'] = Array(ledger['trend'])
      shown = %w[overdue due_today new waiting backlog].sum { |k| out_ledger[k].size }
      total = %w[overdue due_today new waiting backlog].sum { |k| Array(ledger[k]).size }
      out_ledger['private_open'] = total - shown

      lede = pub['lede'].to_s
      lede = '' unless keep.call('lede', lede)
      out = {
        'date' => data['date'], 'heading' => data['heading'], 'subtitle' => data['subtitle'], 'lede' => lede,
        'metrics' => public_metrics(data, out_ledger),
        'ledger' => out_ledger,
        'calendar' => { 'events' => public_events(data, pub, keep) },
        'sources' => Array(data['sources']).map { |s| s.slice('name', 'status') }
      }
      # A focus story about an item the ledger hid, by its private flag or a pattern hit, stays hidden too.
      shown_ids = LEDGER_KEYS.flat_map { |k| out_ledger[k] }.to_set { |i| i['id'] }
      hidden_ids = LEDGER_KEYS.flat_map { |k| Array(ledger[k]) }.map { |i| i['id'] }.reject { |id| shown_ids.include?(id) }.to_set | private_ids
      focus = Array(data['focus']).reject { |f| hidden_ids.include?(f['id'].to_i) }
      { 'focus' => focus, 'shipped' => pub['shipped'], 'did' => pub['did'], 'context' => pub['context'], 'chips' => pub['chips'] }
        .each { |k, list| out[k] = Array(list).select { |e| keep.call(k, e) } }
      [out, redacted]
    end
  end
end
