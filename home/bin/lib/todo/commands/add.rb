# frozen_string_literal: true

module Todo
  module Commands
    module Add
      COMPLETIONS = {
        description: 'Add a new task',
        positional: :text,
        options: [
          { long: '--category', short: '-c', desc: 'Task category', arg: :category },
          { long: '--priority', short: '-p', desc: 'Task priority (0=highest)', arg: :text },
          { long: '--tag', short: '-t', desc: 'Task tag', arg: :text, repeat: true }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('add', 'todo add <description> [options]', 'Add a new task',
                              [['--category, -c <name>', 'Assign a category (auto-created if new)'],
                               ['--priority, -p <0-9999>', 'Set priority (0=highest)'],
                               ['--tag, -t <tag>',       'Add a tag (repeatable)']],
                              ['todo add "Buy groceries"',
                               'todo add "Fix login bug" -c work -p 0 -t urgent',
                               'todo a "Quick note"'])
      end

      def self.run(args, store:, fmt:)
        description = nil
        category = ''
        priority = ''
        tags = []

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return
          when '-c', '--category' then category = args.shift
          when '-p', '--priority' then priority = args.shift
          when '-t', '--tag' then tags << args.shift
          else
            if description.nil?
              description = arg
            else
              $stderr.puts "Unknown argument: #{arg}"
              exit 1
            end
          end
        end

        if description.nil? || description.empty?
          $stderr.puts 'Error: description is required'
          exit 1
        end

        category = Todo::Store::DEFAULT_CATEGORY if category.empty?
        category = category.downcase
        store.ensure_category(category)

        unless priority.empty?
          unless priority.match?(/\A\d+\z/) && priority.to_i.between?(0, 9999)
            $stderr.puts 'Error: priority must be a number 0-9999 (0=highest)'
            exit 1
          end
          priority = priority.to_i
        end

        id = store.next_id
        task = {
          'id' => id,
          'description' => description,
          'category' => category,
          'priority' => priority,
          'status' => 'pending',
          'created' => store.today,
          'modified' => store.today,
          'tags' => tags
        }
        store.save_task(task, category)

        puts "Added task ##{id}: #{description}"
      end
    end
  end
end
