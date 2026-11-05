# frozen_string_literal: true

require 'fileutils'
require 'time'

module Journal
  # A durable list of journal items with short ids, so a closed item stays closed
  # across journals and the briefing can sort by due date and age.
  class Ledger
    KINDS = %w[action review owe wait discuss task].freeze
    CLOSED = %w[done dropped].freeze
    # Business days until an item without an explicit due date counts as overdue; nil never goes overdue.
    DEFAULT_DUE_DAYS = { 'action' => 1, 'review' => 2, 'owe' => 5, 'wait' => nil, 'discuss' => nil, 'task' => nil }.freeze
    WAIT_NUDGE_DAYS = 3
    SECTION_KINDS = {
      "Today's focus" => 'action', 'Needs my action' => 'action', 'I owe' => 'owe', 'Follow-ups' => 'owe',
      'Waiting on others' => 'wait', 'Open discussions' => 'discuss', 'Remaining tasks' => 'task',
      'Pull requests' => 'task', 'Cortex' => 'task', 'Other' => 'task'
    }.freeze
    VERBS = %w[done drop snooze due reopen note private share].freeze
    BARE_HOST = %r{\Ahttps?://[^/]+/?\z}
    WEEKDAYS = %w[sun mon tue wed thu fri sat].freeze
    MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

    attr_reader :path, :today, :data

    def self.default_path
      ENV.fetch('JOURNAL_LEDGER') { File.join(Journal.home, 'ledger.json') }
    end

    def initialize(path = self.class.default_path, today: Date.today)
      @path = path
      @today = today
      @data = File.exist?(path) ? JSON.parse(Journal.read(path)) : { 'next_id' => 1, 'items' => [] }
    end

    # Loads, yields and saves under an exclusive lock, so a reply and the morning run cannot overwrite each other.
    def self.transaction(path = default_path, today: Date.today)
      FileUtils.mkdir_p(File.dirname(path))
      File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        ledger = new(path, today: today)
        result = yield ledger
        ledger.save
        result
      end
    end

    def items = data['items']

    def save
      tmp = "#{path}.tmp"
      File.write(tmp, "#{JSON.pretty_generate(data)}\n", encoding: 'UTF-8')
      File.rename(tmp, path)
    end

    def find(id) = items.find { |i| i['id'] == id.to_i }

    def find_by_keys(keys)
      keys = keys.to_set
      items.find { |i| (([i['key']] + i['keys'].to_a).to_set & keys).any? }
    end

    # A primary link on either side must match; two items that only share a secondary link
    # (a digest message listing several actions, a PR cited as context) stay separate.
    def find_match(found)
      all = ([found['key']] + found['keys']).to_set
      items.find { |i| ([i['key']] + i['keys'].to_a).include?(found['key']) || all.include?(i['key']) }
    end

    # Every key the ledger knows, in any status; the carry-over check treats these as tracked.
    def known_keys = items.flat_map { |i| [i['key']] + i['keys'].to_a + i['refs'].to_a }.to_set

    # Merges scout findings: matching items are refreshed, closed items with newer activity reopen,
    # resolved findings close their item, and the rest become new items.
    def upsert(incoming, now: Time.now)
      report = Hash.new { |h, k| h[k] = [] }
      incoming.each do |raw|
        begin
          found = normalize_incoming(raw)
        rescue ArgumentError => e
          report['rejected'] << e.message
          next
        end
        item = find_match(found)
        if item.nil?
          next if found['resolved']

          report['new'] << add(found, now)['id']
        else
          report[merge(item, found, now)] << item['id']
        end
      end
      report
    end

    # Applies a reply like "done 12 15, drop 20 not mine, snooze 31 mon".
    def apply(text, now: Time.now)
      parse_commands(text).map do |cmd|
        item = find(cmd[:id])
        next { 'id' => cmd[:id], 'error' => 'no such item' } unless item

        run(cmd, item, now)
      end
    end

    # Seeds open items from a journal body, splitting Cortex bullets into one item per task.
    def seed(body, journal_date:, cortex_titles: {}, now: Time.now)
      added = []
      Journal.open_items(body).each do |entry|
        kind = SECTION_KINDS.find { |s, _| entry[:section].start_with?(s) }&.last || 'task'
        since = carried_since(entry[:full], journal_date)
        if entry[:section] == 'Cortex'
          entry[:keys].grep(TASK_RE).each do |tid|
            id = tid.delete('@').to_i
            next if find_by_keys([tid]) || !cortex_titles.key?(id)

            task = cortex_titles[id].is_a?(Hash) ? cortex_titles[id] : { 'title' => cortex_titles[id] }
            first = task['created'] ? [Date.parse(task['created']), since].min : since
            added << add({ 'key' => tid, 'keys' => [], 'title' => "#{tid} #{task['title']}", 'kind' => 'task', 'cortex' => [id],
                           'detail' => strip_title(entry[:full]) }, now, first_seen: first)['id']
          end
          next
        end
        # Outside the Cortex section an @id in a bullet is context, so it is kept as a reference, not a match key.
        keys = entry[:keys].select { |k| k.start_with?('http') && !k.match?(BARE_HOST) }.map { |k| Journal.normalize(k) }
        refs = entry[:keys].grep(TASK_RE)
        next if keys.empty? || find_by_keys(keys)

        url = entry[:full][LINK_RE, 1]
        kind = 'review' if entry[:section].start_with?('Needs my action') && url.to_s.match?(%r{/pulls?/\d+})
        added << add({ 'key' => keys.first, 'keys' => keys.drop(1), 'title' => strip_title(entry[:full]), 'kind' => kind,
                       'url' => url, 'refs' => refs }, now, first_seen: since)['id']
      end
      added
    end

    def status(item)
      return item['status'] if CLOSED.include?(item['status'])
      return 'snoozed' if item['snooze_until'] && Date.parse(item['snooze_until']) > today

      'open'
    end

    def due(item)
      return Date.parse(item['due']) if item['due']

      days = DEFAULT_DUE_DAYS[item['kind']]
      days && add_business_days(Date.parse(item['first_seen']), days)
    end

    def age(item) = (today - Date.parse(item['first_seen'])).to_i

    def open_items = items.select { |i| status(i) == 'open' }

    # Buckets for the journal body and the briefing, each sorted most urgent first.
    def view(since: nil, public: false)
      open = open_items
      open = open.reject { |i| i['private'] } if public
      overdue, rest = open.partition { |i| (d = due(i)) && d < today }
      due_today, rest = rest.partition { |i| due(i) == today }
      waiting, rest = rest.partition { |i| i['kind'] == 'wait' }
      fresh = since ? rest.select { |i| Time.parse(i['created_at']) >= since } : []
      {
        'overdue' => sort_urgent(overdue), 'due_today' => sort_urgent(due_today),
        'new' => sort_urgent(fresh), 'waiting' => waiting.sort_by { |i| -age(i) },
        'backlog' => (rest - fresh).sort_by { |i| [KINDS.index(i['kind']) || 9, -age(i)] },
        'snoozed' => items.select { |i| status(i) == 'snoozed' },
        'closed_recently' => since ? items.select { |i| i['closed_at'] && Time.parse(i['closed_at']) >= since && !(public && i['private']) } : []
      }
    end

    # Records today's open and overdue counts, one entry per date, for the backlog trend.
    def snapshot
      v = view
      open = open_items.size
      (data['snapshots'] ||= {})[today.iso8601] = { 'open' => open, 'overdue' => v['overdue'].size, 'due_today' => v['due_today'].size }
    end

    def trend = data.fetch('snapshots', {}).sort.map { |date, counts| counts.merge('date' => date) }

    def label(item) = "J-#{item['id']}"

    def summary(item)
      parts = { 'id' => item['id'], 'label' => label(item), 'title' => item['title'], 'kind' => item['kind'],
                'url' => item['url'], 'detail' => item['detail'], 'first_seen' => item['first_seen'],
                'age' => age(item), 'status' => status(item) }
      d = due(item)
      parts['due'] = d&.iso8601
      parts['days_overdue'] = (today - d).to_i if d && d < today
      parts['nudge'] = true if item['kind'] == 'wait' && age(item) >= WAIT_NUDGE_DAYS
      parts['snooze_until'] = item['snooze_until'] if item['snooze_until']
      parts['closed_at'] = item['closed_at'] if item['closed_at']
      parts['cortex'] = item['cortex'] if item['cortex']&.any?
      parts['private'] = true if item['private']
      parts['private_reason'] = item['private_reason'] if item['private']
      parts.compact
    end

    # Relative dates for snooze and due: today, tomorrow, mon..sun, next week, Nd, Nw, "nov 10", or yyyy-mm-dd.
    def parse_date(word)
      w = word.to_s.downcase.strip
      case w
      when 'today' then today
      when 'tomorrow', 'tmr' then today + 1
      when 'next week', 'nextweek' then next_weekday('mon')
      when /\A(\d+)d\z/ then today + Regexp.last_match(1).to_i
      when /\A(\d+)w\z/ then today + (7 * Regexp.last_match(1).to_i)
      when /\A\d{4}-\d{2}-\d{2}\z/ then Date.parse(w)
      when /\A(#{MONTHS.join('|')})[a-z]*\s+(\d{1,2})\z/ then month_day(Regexp.last_match(1), Regexp.last_match(2).to_i)
      else
        day = WEEKDAYS.find { |d| w.start_with?(d) }
        raise ArgumentError, "cannot read the date #{word.inspect}" unless day

        next_weekday(day)
      end
    end

    def parse_commands(text)
      tokens = text.to_s.gsub(/[,;\n]/, ' ').split
      commands = []
      until tokens.empty?
        verb = tokens.shift.downcase
        raise ArgumentError, "unknown command #{verb.inspect}; use #{VERBS.join(', ')}" unless VERBS.include?(verb)

        ids = []
        ids << tokens.shift[/\d+/].to_i while tokens.first&.match?(/\A(?:J-?)?\d+\z/i)
        raise ArgumentError, "#{verb} needs at least one item id" if ids.empty?

        words = []
        words << tokens.shift while tokens.any? && !VERBS.include?(tokens.first.downcase)
        ids.each { |id| commands << { verb: verb, id: id, rest: words.join(' ') } }
      end
      commands
    end

    private

    def run(cmd, item, now)
      case cmd[:verb]
      when 'done', 'drop'
        close(item, cmd[:verb] == 'done' ? 'done' : 'dropped', cmd[:rest].empty? ? 'closed from a reply' : cmd[:rest], now)
      when 'snooze'
        until_date = parse_date(cmd[:rest].empty? ? 'tomorrow' : cmd[:rest])
        item['snooze_until'] = until_date.iso8601
        log(item, now, 'snoozed', until_date.iso8601)
      when 'due'
        item['due'] = parse_date(cmd[:rest]).iso8601
        item['due_reason'] = 'set from a reply'
        log(item, now, 'due', item['due'])
      when 'reopen' then reopen(item, now, cmd[:rest].empty? ? 'reopened from a reply' : cmd[:rest])
      when 'note'
        item['detail'] = cmd[:rest]
        log(item, now, 'note', cmd[:rest])
      when 'private'
        mark_private(item, cmd[:rest].empty? ? 'marked private from a reply' : cmd[:rest], now, by_reply: true)
      when 'share'
        item['private'] = false
        item['private_reason'] = 'shared from a reply'
        log(item, now, 'shared', cmd[:rest])
      end
      { 'id' => item['id'], 'verb' => cmd[:verb], 'status' => status(item), 'title' => item['title'],
        'cortex' => cmd[:verb] == 'done' ? item['cortex'].to_a : [] }
    end

    def normalize_incoming(raw)
      keys = ([raw['key'], raw['url']] + raw['keys'].to_a + raw['links'].to_a.map { |l| l.is_a?(Hash) ? l['url'] : l })
             .compact.map(&:strip).reject { |k| k.empty? || k.match?(BARE_HOST) }
             .map { |k| k.start_with?('http') ? Journal.normalize(k) : k }.uniq
      raise ArgumentError, "item without a key or url: #{raw['title'].inspect}" if keys.empty?

      kind = raw['kind'].to_s
      raise ArgumentError, "unknown kind #{kind.inspect} for #{raw['title'].inspect}" unless KINDS.include?(kind) || raw['resolved']

      raw.merge('key' => keys.first, 'keys' => keys.drop(1))
    end

    def add(found, now, first_seen: nil)
      item = {
        'id' => data['next_id'], 'key' => found['key'], 'keys' => found['keys'].to_a, 'title' => found['title'],
        'kind' => found['kind'], 'url' => found['url'], 'detail' => found['detail'], 'source' => found['source'],
        'due' => found['due'], 'due_reason' => found['due_reason'], 'cortex' => found['cortex'].to_a, 'refs' => found['refs'],
        'first_seen' => (first_seen || Date.parse(found['first_seen'] || today.iso8601)).iso8601,
        'last_activity' => found['last_activity'], 'status' => 'open', 'created_at' => now.iso8601, 'history' => [],
        'private' => found['private'] ? true : nil, 'private_reason' => found['private'] ? found['private_reason'] : nil
      }.compact
      data['next_id'] += 1
      items << item
      log(item, now, 'added', found['source'])
      item
    end

    def merge(item, found, now)
      item['keys'] = (item['keys'].to_a + [found['key']] + found['keys'] - [item['key']]).uniq
      %w[detail url].each { |f| item[f] = found[f] unless found[f].to_s.strip.empty? }
      %w[due due_reason].each { |f| item[f] = found[f] if found[f] } unless item['due_reason'] == 'set from a reply'
      item['title'] = found['title'] if found['title'] && found['kind']
      item['kind'] = found['kind'] if KINDS.include?(found['kind'])
      item['cortex'] = (item['cortex'].to_a + found['cortex'].to_a).uniq
      mark_private(item, found['private_reason'], now) if found['private'] && item['private_reason'] != 'shared from a reply'
      newer = found['last_activity'] && (item['last_activity'].nil? || later?(found['last_activity'], item['last_activity']))
      item['last_activity'] = found['last_activity'] if newer

      if found['resolved']
        return 'unchanged' if CLOSED.include?(item['status'])

        close(item, 'done', found['resolved_evidence'] || 'resolved by a scout', now)
        return 'resolved'
      end
      if CLOSED.include?(item['status']) && newer && later?(found['last_activity'], item['closed_at'])
        reopen(item, now, found['detail'] || 'new activity after it was closed')
        return 'reopened'
      end
      'updated'
    end

    # Private is sticky: a scout can only set it; only a "share" reply clears it.
    def mark_private(item, reason, now, by_reply: false)
      return if item['private'] && !by_reply

      item['private'] = true
      item['private_reason'] = reason || 'sensitive'
      log(item, now, 'private', item['private_reason'])
    end

    # Compares two ISO 8601 times as times: sources write different offsets, so strings do not sort.
    def later?(left, right)
      Time.parse(left.to_s) > Time.parse(right.to_s)
    rescue ArgumentError
      false
    end

    def close(item, state, note, now)
      item['status'] = state
      item['closed_at'] = now.iso8601
      item['close_note'] = note
      item.delete('snooze_until')
      log(item, now, state, note)
    end

    def reopen(item, now, note)
      item['status'] = 'open'
      %w[closed_at close_note snooze_until].each { |f| item.delete(f) }
      log(item, now, 'reopened', note)
    end

    def log(item, now, event, note)
      (item['history'] ||= []) << { 'at' => now.iso8601, 'event' => event, 'note' => note }.compact
    end

    def sort_urgent(list) = list.sort_by { |i| [due(i) || Date.new(9999), -age(i)] }

    def carried_since(line, journal_date)
      m = line.match(/carried over since (#{MONTHS.join('|')})[a-z]*\s+(\d{1,2})/i)
      return journal_date unless m

      date = Date.new(journal_date.year, MONTHS.index(m[1].downcase[0, 3]) + 1, m[2].to_i)
      date > journal_date ? date.prev_year : date
    end

    def strip_title(line)
      text = line.sub(/\A\s*- (\[[ x]\] )?/, '').gsub(/\(\[[^\]]*\]\([^)]*\)(, \[[^\]]*\]\([^)]*\))*\)/, '')
      text = text.gsub(/\[([^\]]*)\]\([^)]*\)/, '\1').gsub(/\(carried over since [^)]*\)/, '').squeeze(' ').strip
      text = text.split(/(?<=[.;])\s+(?=[A-Z(@])/).first.to_s.sub(/\s+([.;])\z/, '\1').chomp('.').chomp(';')
      text.length > 110 ? "#{text[0, 107].rstrip}..." : text
    end

    def add_business_days(date, days)
      days.times do
        date += 1
        date += 1 while date.saturday? || date.sunday?
      end
      date
    end

    def next_weekday(name)
      target = WEEKDAYS.index(name)
      delta = (target - today.wday) % 7
      today + (delta.zero? ? 7 : delta)
    end

    def month_day(month, day)
      date = Date.new(today.year, MONTHS.index(month) + 1, day)
      date < today ? date.next_year : date
    end
  end
end
