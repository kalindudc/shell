# frozen_string_literal: true

module Todo
  module Commands
    module List
      COMPLETIONS = {
        description: 'List tasks with optional filters',
        options: [
          { long: '--category', short: '-c', desc: 'Filter by category', arg: :category },
          { long: '--priority', short: '-p', desc: 'Filter by priority', arg: :text },
          { long: '--tag', short: '-t', desc: 'Filter by tag', arg: :text },
          { long: '--all', short: '-a', desc: 'Include completed tasks' }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('list', 'todo list [options]', 'List active tasks with optional filters',
                              [['--category, -c <name>', 'Filter by category'],
                               ['--priority, -p <0-9999>', 'Filter by priority'],
                               ['--tag, -t <tag>',       'Filter by tag'],
                               ['--all, -a',             'Include completed tasks']])
        puts 'Aliases: l, ls'
        puts
      end

      def self.run(args, store:, fmt:)
        filter_cat = nil
        filter_pri = nil
        filter_tag = nil
        include_all = false

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return
          when '-c', '--category' then filter_cat = args.shift
          when '-p', '--priority' then filter_pri = args.shift
          when '-t', '--tag' then filter_tag = args.shift
          when '-a', '--all' then include_all = true
          else $stderr.puts "Unknown argument: #{arg}"
               exit 1
          end
        end

        config = store.load_config
        todos = store.all_tasks(include_done: include_all)
        todos = todos.select { |t| t['category'] == filter_cat } if filter_cat
        todos = todos.select { |t| t['priority'].to_s == filter_pri } if filter_pri
        todos = todos.select { |t| t['tags']&.include?(filter_tag) } if filter_tag
        todos = todos.sort_by { |t| [t['status'] == 'done' ? 1 : 0, t['priority'].to_s.empty? ? 10_000 : t['priority'].to_i, t['created']] }

        if todos.empty?
          puts 'No tasks found.'
          return
        end

        fmt.fmt_header('Category', 'Tags', config: config)
        todos.each do |t|
          fmt.fmt_task_line(t['id'], t['priority'], t['description'], t['category'], t['tags'] || [], status: t['status'], config: config)
        end
        fmt.fmt_footer(todos.size, 'tasks')
      end
    end
  end
end
