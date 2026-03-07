# frozen_string_literal: true

require_relative '../task_renderer'

module Todo
  module Commands
    module List
      DEFINITION = {
        name: 'list', aliases: %w[l ls h],
        description: 'List tasks with optional filters',
        options: [
          { long: '--category', short: '-c', arg: :category },
          { long: '--priority', short: '-p', arg: :text },
          { long: '--tag', short: '-t', arg: :text },
          { long: '--all', short: '-a' },
          { long: '--plain', short: '-P' },
          { long: '--done-only' },
          { long: '--from', arg: :text },
          { long: '--to', arg: :text }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('list', 'todo list [options]', 'List tasks with optional filters',
                              [['--category, -c <name>', 'Filter by category'],
                               ['--priority, -p <0-9999>', 'Filter by priority'],
                               ['--tag, -t <tag>',       'Filter by tag'],
                               ['--all, -a',             'Include completed tasks'],
                               ['--plain, -P',           'Machine-readable tab-delimited output'],
                               ['--done-only',           'Show only completed tasks'],
                               ['--from <YYYY-MM-DD>',   'Show tasks after date'],
                               ['--to <YYYY-MM-DD>',     'Show tasks before date']])
        puts 'Aliases: l, ls, h'
        puts
      end

      def self.run(args, store:, fmt:)
        opts = parse_args(args, fmt)
        return unless opts

        todos = fetch_tasks(store, opts)

        if todos.empty?
          label = opts[:done_only] ? 'No completed tasks found.' : 'No tasks found.'
          puts label unless opts[:plain]
          return
        end

        config = store.load_config
        opts[:plain] ? print_plain(todos, config) : print_formatted(todos, config)
      end

      def self.parse_args(args, fmt)
        opts = { filter_cat: nil, filter_pri: nil, filter_tag: nil,
                 include_all: false, plain: false, done_only: false,
                 from: nil, to: nil }

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return nil
          when '-c', '--category' then opts[:filter_cat] = args.shift
          when '-p', '--priority' then opts[:filter_pri] = args.shift
          when '-t', '--tag' then opts[:filter_tag] = args.shift
          when '-a', '--all' then opts[:include_all] = true
          when '-P', '--plain' then opts[:plain] = true
          when '--done-only' then opts[:done_only] = true
          when '--from' then opts[:from] = args.shift
          when '--to' then opts[:to] = args.shift
          else $stderr.puts "Unknown argument: #{arg}"
               exit 1
          end
        end
        opts[:include_all] = true if opts[:done_only]
        opts
      end

      def self.fetch_tasks(store, opts)
        todos = store.all_tasks(include_done: opts[:include_all])
        todos = todos.select { |t| t['status'] == 'done' } if opts[:done_only]
        todos = todos.select { |t| t['category'] == opts[:filter_cat] } if opts[:filter_cat]
        todos = todos.select { |t| t['priority'].to_s == opts[:filter_pri] } if opts[:filter_pri]
        todos = todos.select { |t| t['tags']&.include?(opts[:filter_tag]) } if opts[:filter_tag]
        todos = filter_by_date(todos, opts[:from], opts[:to])
        todos.sort_by { |t| TaskRenderer.task_sort_key(t) }
      end

      def self.filter_by_date(todos, date_from, date_to)
        return todos unless date_from || date_to

        todos.select do |t|
          date = t['status'] == 'done' ? t['completed'] : t['created']
          next false if date.nil?

          (!date_from || date >= date_from) && (!date_to || date <= date_to)
        end
      end

      def self.print_plain(todos, config)
        todos.each { |t| puts TaskRenderer.render_plain(t, config: config) }
      end

      def self.print_formatted(todos, config)
        puts TaskRenderer.render_header(config: config)
        puts "  #{Formatter.c_dim('-' * 60)}"
        todos.each { |t| puts TaskRenderer.render_line(t, config: config) }
        puts
        puts TaskRenderer.render_footer(todos.size, 'tasks')
      end
    end
  end
end
