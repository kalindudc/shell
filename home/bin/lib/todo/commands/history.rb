# frozen_string_literal: true

module Todo
  module Commands
    module History
      COMPLETIONS = {
        description: 'Browse completed tasks',
        options: [
          { long: '--category', short: '-c', desc: 'Filter by category', arg: :category },
          { long: '--from', desc: 'Start date', arg: :text },
          { long: '--to', desc: 'End date', arg: :text }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('history', 'todo history [options]', 'Browse completed tasks',
                              [['--category, -c <name>',   'Filter by category'],
                               ['--from <YYYY-MM-DD>',     'Show tasks completed after date'],
                               ['--to <YYYY-MM-DD>',       'Show tasks completed before date']])
        puts 'Aliases: h'
        puts
      end

      def self.run(args, store:, fmt:)
        filter_cat = nil
        date_from = nil
        date_to = nil

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return
          when '-c', '--category' then filter_cat = args.shift
          when '--from' then date_from = args.shift
          when '--to' then date_to = args.shift
          else $stderr.puts "Unknown argument: #{arg}"
               exit 1
          end
        end

        config = store.load_config
        items = store.all_tasks(include_done: true).select { |t| t['status'] == 'done' }
        items = items.select { |t| t['category'] == filter_cat } if filter_cat
        items = items.select { |t| t['completed'] && t['completed'] >= date_from } if date_from
        items = items.select { |t| t['completed'] && t['completed'] <= date_to } if date_to
        items = items.sort_by { |t| t['completed'] || '' }

        if items.empty?
          puts 'No completed tasks found.'
          return
        end

        fmt.fmt_header('Category / Completed', 'Tags', config: config)
        items.each do |t|
          right = [t['category'], t['completed']].reject { |s| s.nil? || s.empty? }.join('  ')
          fmt.fmt_task_line(t['id'], t['priority'], t['description'], right, t['tags'] || [], status: t['status'], config: config)
        end
        fmt.fmt_footer(items.size, 'tasks')
      end
    end
  end
end
