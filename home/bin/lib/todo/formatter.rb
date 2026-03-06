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

    def self.priority_color(priority)
      return nil if priority.nil?

      pri = priority.is_a?(String) ? priority.to_i : priority
      if pri < 10 then '1;31'
      elsif pri < 100 then '1;33'
      elsif pri < 1000 then '0;34'
      end
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
