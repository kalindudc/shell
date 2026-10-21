# frozen_string_literal: true

require 'cgi'
require 'date'
require 'json'
require 'open3'
require 'set'

# Helpers for an agent-written daily journal kept in cortex: a carry-over check
# between two journal bodies, and a themed HTML briefing rendered from JSON.
module Journal
  OPEN_SECTIONS = [
    "Today's focus", 'Needs my action', 'Follow-ups', 'I owe', 'Waiting on others',
    'Open discussions', 'Remaining tasks', 'Pull requests', 'Cortex', 'Other'
  ].freeze
  LINK_RE = %r{\]\((https?://[^)\s]+)\)}
  URL_RE = %r{https?://[^)\s"'<>]+}
  TASK_RE = /(?<![\w#])@\d+\b/
  SLACK_RE = %r{\Ahttps://[^/]*slack\.com/archives/(\w+)(?:/p(\d+))?(?:\?.*thread_ts=([\d.]+))?}

  module_function

  # Bullets with a link or @id in the previous journal's open sections.
  def open_items(body)
    section = nil
    body.each_line.with_object([]) do |line, items|
      if (m = line.match(/\A\#{2,3} (.*)/))
        section = m[1].strip
        next
      end
      next unless section && OPEN_SECTIONS.any? { |s| section.start_with?(s) } && line.match?(/\A\s*- /)

      keys = line.scan(LINK_RE).flatten.to_set | line.scan(TASK_RE).to_set
      items << { section: section, line: line.strip[0, 110], keys: keys } unless keys.empty?
    end
  end

  # Slack links match by channel and thread; mail links match exactly; other URLs ignore query and fragment.
  def normalize(url)
    if (m = url.match(SLACK_RE))
      thread = m[3].to_s.delete('.')
      return "slack:#{m[1]}:#{thread.empty? ? m[2].to_s : thread}"
    end
    return url if url.include?('mail.google')

    url.split('?').first.split('#').first.chomp('/')
  end

  def body_keys(body)
    body.scan(URL_RE).to_set { |u| normalize(u) } | body.scan(TASK_RE).to_set
  end

  def key_hit?(key, keys)
    return keys.any? { |k| k.start_with?(key) } if key.start_with?('slack:') && key.end_with?(':')

    keys.include?(key)
  end

  # Open items from previous_body with no matching link or @id anywhere in new_body.
  def missing_items(previous_body, new_body)
    keys = body_keys(new_body)
    items = open_items(previous_body)
    missing = items.reject do |item|
      item[:keys].any? { |k| key_hit?(k.start_with?('http') ? normalize(k) : k, keys) }
    end
    [items.size, missing]
  end

  # Agents often run with a US-ASCII locale; journals hold names and punctuation that are not.
  def read(path) = File.read(path, encoding: 'UTF-8')

  def cortex_body(id)
    out, status = Open3.capture2('cortex', 'show', id.to_s, '--json')
    raise "cortex show #{id} failed" unless status.success?

    JSON.parse(out.force_encoding('UTF-8')).fetch('task').fetch('body')
  end
end

require_relative 'journal/render'
