# frozen_string_literal: true

require_relative '../interactive'
require_relative '../task_renderer'

module Todo
  module Commands
    module Search
      DEFINITION = {
        name: 'search', aliases: %w[find f],
        description: 'Search tasks',
        positional: { name: :term, type: :text },
        options: [
          { long: '--all', short: '-a' }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('search', 'todo search [term] [options]', 'Search tasks by description, category, or tags',
                              [['--all, -a', 'Include completed tasks in results']],
                              ['todo search',           'Interactive fuzzy search (fzf)',
                               'todo search "bug"',     'Search for tasks matching "bug"',
                               'todo find -a deploy',   'Search all tasks including done'])
        puts 'Aliases: find, f'
        puts
      end

      def self.run(args, store:, fmt:)
        term = nil
        search_all = false

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return
          when '-a', '--all' then search_all = true
          else
            if term.nil?
              term = arg
            else
              $stderr.puts "Unknown argument: #{arg}"
              exit 1
            end
          end
        end

        # Interactive mode: no term + TTY → launch fzf search across all tasks
        return run_interactive(store: store, fmt: fmt) if (term.nil? || term.empty?) && $stdin.tty?

        if term.nil? || term.empty?
          $stderr.puts 'Error: search term required'
          exit 1
        end

        run_text_search(term, search_all: search_all, store: store)
      end

      def self.run_interactive(store:, fmt:)
        task_id = Interactive.search(store: store, prompt: 'Search> ')
        return unless task_id

        Commands::Show.run([task_id.to_s], store: store, fmt: fmt)
      end

      def self.run_text_search(term, search_all:, store:)
        config = store.load_config
        re = Regexp.new(term, Regexp::IGNORECASE)

        results = store.all_tasks(include_done: search_all).select do |t|
          re.match?(t['description']) || re.match?(t['category']) || (t['tags'] || []).any? { |tag| re.match?(tag) }
        end

        if results.empty?
          puts "No tasks matching '#{term}' found."
          return
        end

        puts TaskRenderer.render_header(config: config)
        puts "  #{Formatter.c_dim('-' * 60)}"
        results.each { |t| puts TaskRenderer.render_line(t, config: config) }
        puts
        puts TaskRenderer.render_footer(results.size, 'results')
      end
    end
  end
end
