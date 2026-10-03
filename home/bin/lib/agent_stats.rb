# frozen_string_literal: true

require 'json'
require 'open3'
require 'time'

# Workflow metrics for cortex plans and the pi sessions that planned and
# implemented them. Read-only: it reads `cortex ls/show --json` and the pi
# session logs, and prints a markdown table.
module AgentStats
  BOOKKEEPING_TOOLS = %w[quest cortex_update].freeze
  UUID = /([0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12})/
  NO_DEVIATION = /\bno deviations?\b|\bdeviations?:\s*none\b/i
  SESSIONS_GLOB = File.join(Dir.home, '.pi', 'agent', 'sessions', '*', '*.jsonl')

  module_function

  def median(values)
    return nil if values.empty?

    sorted = values.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end

  # Stats for one pi session log, given its JSONL lines.
  def session_stats(lines)
    stats = { turns: 0, bookkeeping_turns: 0, tool_calls: 0, cost: 0.0, peak_context: 0, minutes: 0.0 }
    times = []
    lines.each do |line|
      entry = parse(line)
      next unless entry && entry['type'] == 'message'

      times << Time.parse(entry['timestamp'])
      message = entry['message']
      count_assistant_turn(stats, message) if message['role'] == 'assistant'
    end
    stats[:minutes] = (times.max - times.min) / 60.0 unless times.empty?
    stats
  end

  def count_assistant_turn(stats, message)
    usage = message['usage'] || {}
    calls = Array(message['content']).select { |c| c.is_a?(Hash) && c['type'] == 'toolCall' }.map { |c| c['name'] }
    stats[:turns] += 1
    stats[:tool_calls] += calls.length
    stats[:bookkeeping_turns] += 1 if calls.any? && calls.all? { |name| BOOKKEEPING_TOOLS.include?(name) }
    stats[:cost] += usage.dig('cost', 'total').to_f
    context = %w[input cacheRead cacheWrite].sum { |key| usage[key].to_i }
    stats[:peak_context] = context if context > stats[:peak_context]
  end

  # Session uuids that wrote and implemented a plan. The implementing session
  # is the author of the first `status → review` when it differs from the planner.
  def session_roles(updates)
    sorted = updates.sort_by { |u| u['created'].to_i }
    planning = uuid(sorted.find { |u| u['summary'].to_s.downcase.include?('plan written') })
    implementing = uuid(sorted.find { |u| u['summary'].to_s.start_with?('status → review') })
    { planning: planning, implementing: implementing == planning ? nil : implementing }
  end

  def deviation?(update)
    text = "#{update['summary']}\n#{update['body']}"
    text.match?(/deviation/i) && !text.match?(NO_DEVIATION)
  end

  def minutes_to_open(updates)
    sorted = updates.sort_by { |u| u['created'].to_i }
    written = sorted.find { |u| u['summary'].to_s.downcase.include?('plan written') }
    opened = sorted.find { |u| u['summary'].to_s.start_with?('status → open') && u['created'].to_i >= written['created'].to_i } if written
    (opened['created'] - written['created']) / 60_000.0 if opened
  end

  def report(plans, sessions)
    planning = sessions[:planning]
    implementing = sessions[:implementing]
    waits = plans.filter_map { |p| minutes_to_open(p['updates']) }
    deviating = plans.count { |p| p['updates'].any? { |u| deviation?(u) } }
    <<~TABLE
      | Metric | Planning | Implementing |
      |---|---|---|
      | Sessions matched | #{planning.length} | #{implementing.length} |
      | Bookkeeping-only turns | #{share(planning)} | #{share(implementing)} |
      | Median session minutes | #{med(planning, :minutes)} | #{med(implementing, :minutes)} |
      | Median tool calls | #{med(planning, :tool_calls)} | #{med(implementing, :tool_calls)} |
      | Median cost | #{money(planning)} | #{money(implementing)} |
      | Median peak context | #{kilo(planning)} | #{kilo(implementing)} |
      | Plans with real deviations | #{deviating} of #{plans.length} | |
      | Median `plan written` to `open` | #{waits.empty? ? 'n/a' : "#{median(waits).round} min"} | |
    TABLE
  end

  def run(argv)
    since = argv.include?('--since') ? Time.parse(argv[argv.index('--since') + 1]) : nil
    plans = load_plans(since)
    index = Dir.glob(SESSIONS_GLOB).to_h { |path| [path[UUID, 1], path] }
    ids = { planning: [], implementing: [] }
    plans.each { |plan| session_roles(plan['updates']).each { |role, id| ids[role] << id if id && index[id] } }
    # A session that wrote several plans (a stack) counts once.
    sessions = ids.transform_values { |list| list.uniq.map { |id| session_stats(File.foreach(index[id])) } }
    puts "Plans created since #{since ? since.to_date : 'the beginning'}: #{plans.length}"
    puts report(plans, sessions)
  end

  def load_plans(since)
    tasks = JSON.parse(cortex('ls', '--json', '-t', 'plan'))
    tasks = tasks.select { |t| Time.at(t['created'] / 1000) >= since } if since
    tasks.map { |t| JSON.parse(cortex('show', t['id'].to_s, '--json')) }
  end

  def cortex(*args)
    out, status = Open3.capture2('cortex', *args)
    raise "cortex #{args.join(' ')} failed" unless status.success?

    out
  end

  def parse(line)
    JSON.parse(line)
  rescue JSON::ParserError
    nil
  end

  def uuid(update)
    update && update['author'].to_s[UUID, 1]
  end

  def share(list)
    turns = list.sum { |s| s[:turns] }
    turns.zero? ? 'n/a' : "#{(100.0 * list.sum { |s| s[:bookkeeping_turns] } / turns).round}%"
  end

  def med(list, key)
    value = median(list.map { |s| s[key] })
    value ? value.round.to_s : 'n/a'
  end

  def money(list)
    value = median(list.map { |s| s[:cost] })
    value ? format('$%.2f', value) : 'n/a'
  end

  def kilo(list)
    value = median(list.map { |s| s[:peak_context] })
    value ? "#{(value / 1000.0).round}k" : 'n/a'
  end
end
