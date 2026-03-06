# frozen_string_literal: true

module Todo
  module Commands
    module Search
      COMPLETIONS = {
        description: 'Search tasks',
        positional: :text,
        options: [
          { long: '--all', short: '-a', desc: 'Include completed tasks' }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('search', 'todo search <term> [options]', 'Search tasks by description, category, or tags',
                              [['--all, -a', 'Include completed tasks in results']])
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

        if term.nil? || term.empty?
          $stderr.puts 'Error: search term required'
          exit 1
        end

        config = store.load_config
        re = Regexp.new(term, Regexp::IGNORECASE)

        results = store.all_tasks(include_done: search_all).select do |t|
          re.match?(t['description']) || re.match?(t['category']) || (t['tags'] || []).any? { |tag| re.match?(tag) }
        end

        if results.empty?
          puts "No tasks matching '#{term}' found."
          return
        end

        fmt.fmt_header('Status', 'Tags', config: config)
        results.each do |t|
          fmt.fmt_task_line(t['id'], t['priority'], t['description'], t['status'], t['tags'] || [], status: t['status'], config: config)
        end
        fmt.fmt_footer(results.size, 'results')
      end
    end
  end
end
