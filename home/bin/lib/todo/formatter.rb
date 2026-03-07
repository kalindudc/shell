# frozen_string_literal: true

module Todo
  module Formatter
    NO_COLOR = !ENV.fetch('NO_COLOR', '').empty?

    @max_line_width = 0

    # ── Color helpers ─────────────────────────────────────────────

    def self.colorize(code, text)
      return text if NO_COLOR

      "\033[#{code}m#{text}\033[0m"
    end

    def self.c_bold(t)     = colorize('1', t)
    def self.c_dim(t)      = colorize('2', t)
    def self.c_red(t)      = colorize('0;31', t)
    def self.c_green(t)    = colorize('0;32', t)
    def self.c_yellow(t)   = colorize('1;33', t)
    def self.c_blue(t)     = colorize('0;34', t)
    def self.c_cyan(t)     = colorize('0;36', t)
    def self.c_bold_red(t) = colorize('1;31', t)

    # 10-level gradient from deep red (0) to grey (9).
    # Priorities > 9 return nil (default terminal color).
    PRIORITY_COLORS = [
      '38;5;196', # 0 - deep red
      '38;5;160', # 1 - red
      '38;5;202', # 2 - orange-red
      '38;5;208', # 3 - orange
      '38;5;214', # 4 - dark yellow
      '38;5;220', # 5 - yellow
      '38;5;148', # 6 - yellow-green
      '38;5;108', # 7 - muted green
      '38;5;250', # 8 - light grey
      '38;5;245'  # 9 - grey
    ].freeze

    def self.priority_color(priority)
      return nil if priority.nil?

      pri = priority.is_a?(String) ? priority.to_i : priority
      PRIORITY_COLORS[pri]
    end

    # ── Text helpers ──────────────────────────────────────────────

    def self.desc_max(config)
      (config['desc_max'] || 32).to_i
    end

    def self.truncate(str, max)
      return str if str.length <= max

      "#{str[0, max - 3]}..."
    end

    # ── Output helpers ────────────────────────────────────────────

    def self.print_subcmd_help(subcmd, usage, description, options = [], examples = [])
      puts "#{c_bold('todo')} #{subcmd} - #{description}"
      puts
      puts "usage: #{usage}"
      unless options.empty?
        puts
        puts 'Options:'
        options.each { |flag, desc| printf "  %-28s %s\n", flag, desc }
      end
      unless examples.empty?
        puts
        puts 'Examples:'
        examples.each { |ex| puts "  #{ex}" }
      end
      puts
    end

    def self.fmt_task_line(id, priority, description, right_label, tags, status: 'pending', config: {})
      dmax = desc_max(config)
      pri_str = priority.to_s
      checkbox = status == 'done' ? '[x]' : '[ ]'
      badge = pri_str.empty? ? '      ' : format('[%4s]', pri_str)
      desc_truncated = format("%-#{dmax}s", truncate(description, dmax))
      core = format('%s %-3s %s %s', checkbox, id, badge, desc_truncated)

      right_plain = right_label.to_s.empty? ? '' : "  #{right_label}"
      tags_plain = tags.empty? ? '' : tags.map { |t| "  ##{t}" }.join

      right_str = right_label.to_s.empty? ? '' : "  #{c_dim(right_label)}"
      tags_str = tags.empty? ? '' : tags.map { |t| "  #{c_cyan("##{t}")}" }.join

      visible_width = 2 + core.length + right_plain.length + tags_plain.length
      @max_line_width = visible_width if visible_width > @max_line_width

      line_color = if status == 'done'
                     '0;32'
                   else
                     pri_str.empty? ? nil : priority_color(priority)
                   end

      if line_color && !NO_COLOR
        puts "  \033[#{line_color}m#{core}\033[0m#{right_str}#{tags_str}"
      else
        puts "  #{core}#{right_str}#{tags_str}"
      end
    end

    def self.fmt_header(right_column = 'Category', extra_column = 'Tags', config: {})
      dmax = desc_max(config)
      header = format("%-3s %-3s %-6s %-#{dmax}s  %s  %s", ' ', 'ID', 'Pri', 'Description', right_column, extra_column)
      puts "  #{c_dim(header)}"
      puts "  #{c_dim('-' * header.rstrip.length)}"
    end

    def self.fmt_footer(count, label)
      label = label.sub(/s\z/, '') if count == 1
      width = [@max_line_width, 45].max
      @max_line_width = 0
      puts "\n#{c_dim("#{count} #{label}").rjust(width)}"
    end
  end
end
