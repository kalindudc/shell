# frozen_string_literal: true

require_relative 'formatter'

module Todo
  # Single source of truth for task line formatting.
  # Used by: list (terminal), list --plain (scripts), mark (fzf input).
  module TaskRenderer
    # ── Rendering ────────────────────────────────────────────────────

    # Formatted terminal line with ANSI colors.
    def self.render_line(task, config: {})
      dmax = desc_max(config)
      checkbox = task['status'] == 'done' ? '[x]' : '[ ]'
      pri = task['priority']
      badge = pri.nil? ? '      ' : format('[%4s]', pri)
      desc = format("%-#{dmax}s", truncate(task['description'].to_s, dmax))
      category = task['category'].to_s
      tags = (task['tags'] || []).map { |t| "##{t}" }.join('  ')

      core = format('%s %-3s %s %s', checkbox, task['id'], badge, desc)

      if Formatter::NO_COLOR
        "  #{core}  #{category}  #{tags}"
      else
        pri_str = pri.to_s
        line_color = if task['status'] == 'done'
                       '0;32'
                     else
                       pri_str.empty? ? nil : Formatter.priority_color(pri)
                     end

        cat_part = "  #{Formatter.c_dim(category)}"
        tags_part = (task['tags'] || []).map { |t| "  #{Formatter.c_cyan("##{t}")}" }.join

        if line_color
          "  \033[#{line_color}m#{core}\033[0m#{cat_part}#{tags_part}"
        else
          "  #{core}#{cat_part}#{tags_part}"
        end
      end
    end

    # Tab-delimited plain line (no ANSI, no truncation).
    # Used for: list --plain, external scripts, piping.
    def self.render_plain(task, config: {})
      checkbox = task['status'] == 'done' ? '[x]' : '[ ]'
      pri = task['priority']
      pri_str = pri.nil? ? '' : pri.to_s
      desc = task['description'].to_s.tr("\t", ' ')
      category = task['category'].to_s
      tags = (task['tags'] || []).join(',')

      [task['id'], checkbox, pri_str, desc, category, tags].join("\t")
    end

    # Pre-formatted line for fzf display with hidden searchable text.
    # Fixed-width columns ensure alignment. Description is truncated for display.
    # The full description is appended after a TAB character; --tabstop=9999
    # pushes it off-screen so it's invisible, but fzf still searches it.
    def self.render_fzf(task, config: {})
      dmax = desc_max(config)
      checkbox = task['status'] == 'done' ? '[x]' : '[ ]'
      pri = task['priority']
      badge = pri.nil? ? '      ' : format('[%4s]', pri)
      full_desc = task['description'].to_s
      desc = format("%-#{dmax}s", truncate(full_desc, dmax))
      category = task['category'].to_s
      tags = (task['tags'] || []).map { |t| "##{t}" }.join('  ')

      visible = format('  %s %-4s %s %s  %-10s  %s', checkbox, task['id'], badge, desc, category, tags)
      "#{visible}\t#{full_desc}"
    end

    # Column header row.
    def self.render_header(config: {})
      dmax = desc_max(config)
      header = format("%-3s %-3s %-6s %-#{dmax}s  %s  %s", ' ', 'ID', 'Pri', 'Description', 'Category', 'Tags')
      if Formatter::NO_COLOR
        "  #{header}"
      else
        "  #{Formatter.c_dim(header)}"
      end
    end

    # Count summary footer.
    def self.render_footer(count, label)
      label = label.sub(/s\z/, '') if count == 1
      "#{count} #{label}"
    end

    # Consistent sort key: [done?0:1, priority_or_10000, created_date]
    def self.task_sort_key(task)
      done = task['status'] == 'done' ? 1 : 0
      pri = task['priority'].nil? ? 10_000 : task['priority'].to_i
      [done, pri, task['created'].to_s]
    end

    # ── Text helpers ─────────────────────────────────────────────────

    def self.desc_max(config)
      (config['desc_max'] || 32).to_i
    end

    def self.truncate(str, max)
      return str if str.length <= max

      "#{str[0, max - 3]}..."
    end

    private_class_method :desc_max, :truncate
  end
end
