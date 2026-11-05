# frozen_string_literal: true

module Journal
  # The `journal ledger` subcommands.
  module CLI
    module_function

    def ledger(args)
      sub, *rest = args
      case sub
      when 'seed' then seed(rest.fetch(0))
      when 'upsert' then upsert(rest)
      when 'apply' then apply(rest)
      when 'view' then view(rest)
      when 'ls' then list(rest)
      when 'show' then show(rest.fetch(0))
      when 'snapshot' then puts(JSON.generate(Ledger.transaction(&:snapshot)))
      else
        warn('usage: journal ledger seed|upsert|apply|view|ls|show|snapshot (see journal --help)')
        return 2
      end
      0
    rescue ArgumentError, KeyError, IndexError => e
      warn("journal ledger: #{e.message}")
      2
    end

    def seed(task_id)
      body = Journal.cortex_body(task_id)
      date = Date.parse(body[/\A# Journal: (.+)$/, 1] || Date.today.iso8601)
      titles = cortex_open_titles
      added = Ledger.transaction { |l| l.seed(body, journal_date: date, cortex_titles: titles) }
      puts(JSON.generate('seeded_from' => task_id.to_i, 'added' => added.size, 'ids' => added))
    end

    def upsert(files)
      raise ArgumentError, 'upsert needs at least one items file' if files.empty?

      items = files.flat_map do |f|
        parsed = JSON.parse(Journal.read(f))
        parsed.is_a?(Hash) ? parsed.fetch('items', []) : parsed
      end
      report = Ledger.transaction { |l| l.upsert(items) }
      puts(JSON.generate(report.transform_values(&:size).merge('ids' => report)))
    end

    def apply(args)
      cortex = !args.delete('--no-cortex')
      results = Ledger.transaction { |l| l.apply(args.join(' ')) }
      results.each do |r|
        r['cortex_closed'] = r.fetch('cortex', []).select { |id| close_cortex(id, r['id']) } if cortex
      end
      puts(JSON.pretty_generate(results))
    end

    def view(args)
      since = (i = args.index('--since')) ? Time.parse(args.fetch(i + 1)) : nil
      public = args.include?('--public')
      ledger = Ledger.new
      if args.include?('--json')
        buckets = ledger.view(since: since, public: public).transform_values { |list| list.map { |item| ledger.summary(item) } }
        buckets['private_open'] = ledger.open_items.count { |item| item['private'] }
        puts(JSON.pretty_generate(buckets.merge('oldest_open_days' => ledger.open_items.map { |item| ledger.age(item) }.max,
                                                'trend' => ledger.trend)))
      else
        puts(LedgerView.markdown(ledger, since: since))
      end
    end

    def list(args)
      ledger = Ledger.new
      chosen = args.include?('--all') ? ledger.items : ledger.items.reject { |i| Ledger::CLOSED.include?(i['status']) }
      puts(JSON.pretty_generate(chosen.map { |i| ledger.summary(i).merge('keys' => [i['key']] + i['keys'].to_a) }))
    end

    def show(id)
      item = Ledger.new.find(id[/\d+/])
      raise ArgumentError, "no item #{id}" unless item

      puts(JSON.pretty_generate(item))
    end

    def cortex_open_titles
      out, status = Open3.capture2('cortex', 'ls', '--json')
      raise 'cortex ls failed' unless status.success?

      JSON.parse(out.force_encoding('UTF-8')).reject { |t| t['status'] == 'done' || t['lane'] == 'journal' }
          .to_h { |t| [t['id'].to_i, { 'title' => t['title'], 'created' => Time.at(t['created'].to_i / 1000).to_date.iso8601 }] }
    end

    # Closes a cortex task as the user, unless it is already done; returns whether it changed.
    def close_cortex(task_id, item_id)
      out, = Open3.capture2('cortex', 'show', task_id.to_s, '--json')
      return false if JSON.parse(out.force_encoding('UTF-8')).dig('task', 'status') == 'done'

      _, status = Open3.capture2('cortex', 'update', task_id.to_s, '-s', 'done', '--as-me',
                                 '-m', "Closed from the daily journal (J-#{item_id}).")
      status.success?
    end
  end
end
