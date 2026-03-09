# frozen_string_literal: true

require 'json'
require_relative '../interactive'
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
          { long: '--json', short: '-J' },
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
                               ['--json, -J',            'JSON output'],
                               ['--done-only',           'Show only completed tasks'],
                               ['--from <YYYY-MM-DD>',   'Show tasks after date'],
                               ['--to <YYYY-MM-DD>',     'Show tasks before date']])
        puts 'Aliases: l, ls, h'
        puts
      end

      def self.run(args, store:, fmt:)
        opts = parse_args(args, fmt)
        return unless opts

        return print_json_list(store, opts) if opts[:json]
        return print_plain_list(store, opts) if opts[:plain]
        return run_interactive(store, opts, fmt) if $stdin.tty? && Interactive.fzf_available?

        print_formatted_list(store, opts)
      end

      def self.run_interactive(store, opts, fmt)
        task_id = Interactive.browse(
          store: store,
          filters: query_filters(opts)
        )
        return unless task_id

        Commands::Show.run([task_id.to_s], store: store, fmt: fmt)
      end

      def self.print_json_list(store, opts)
        todos = store.query_tasks(**query_filters(opts))
        payload = { 'count' => todos.size, 'tasks' => todos.map { |t| TaskRenderer.task_to_hash(t) } }
        puts JSON.generate(payload)
      end

      def self.print_plain_list(store, opts)
        todos = store.query_tasks(**query_filters(opts))
        config = store.load_config
        todos.each { |t| puts TaskRenderer.render_plain(t, config: config) }
      end

      def self.print_formatted_list(store, opts)
        todos = store.query_tasks(**query_filters(opts))

        if todos.empty?
          label = opts[:done_only] ? 'No completed tasks found.' : 'No tasks found.'
          puts label
          return
        end

        config = store.load_config
        puts TaskRenderer.render_header(config: config)
        puts "  #{Formatter.c_dim('-' * 60)}"
        todos.each { |t| puts TaskRenderer.render_line(t, config: config) }
        puts
        puts TaskRenderer.render_footer(todos.size, 'tasks')
      end

      # Convert parsed CLI opts to Store.query_tasks keyword args.
      def self.query_filters(opts)
        { include_done: opts[:include_all], done_only: opts[:done_only],
          filter_cat: opts[:filter_cat], filter_pri: opts[:filter_pri],
          filter_tag: opts[:filter_tag], date_from: opts[:from], date_to: opts[:to] }
      end

      def self.parse_args(args, fmt)
        opts = { filter_cat: nil, filter_pri: nil, filter_tag: nil,
                 include_all: false, plain: false, json: false, done_only: false,
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
          when '-J', '--json' then opts[:json] = true
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
    end
  end
end
