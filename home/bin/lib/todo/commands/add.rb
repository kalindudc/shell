# frozen_string_literal: true

require_relative '../interactive'

module Todo
  module Commands
    module Add
      DEFINITION = {
        name: 'add', aliases: %w[a],
        description: 'Add a new task',
        positional: { name: :description, type: :text, required: true },
        options: [
          { long: '--category', short: '-c', arg: :category },
          { long: '--priority', short: '-p', arg: :text },
          { long: '--tag', short: '-t', arg: :text, repeat: true }
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
        return help(fmt) if ['-h', '--help'].include?(args.first)

        # Interactive mode: no args at all + TTY
        return run_interactive(store: store) if args.empty? && $stdin.tty?

        description, category, priority, tags = parse_args(args, fmt)
        return unless description

        create_task(description, category, priority, tags, store: store)
      end

      def self.run_interactive(store:)
        description = Interactive.input('Description', placeholder: 'Task description (required)',
                                                       header: 'Enter the task name or description')
        if description.nil? || description.empty?
          $stderr.puts 'Error: description is required'
          exit 1
        end

        category = Interactive.filter(store.all_categories, prompt: 'Category> ',
                                                            header: 'Select or type a new category. ESC to skip.',
                                                            allow_custom: true)
        category ||= Todo::Store::DEFAULT_CATEGORY

        priority = Interactive.input('Priority', placeholder: '0-9 (0=highest), Enter to skip',
                                                 header: 'Task priority (optional)')

        tags_input = Interactive.input('Tags', placeholder: 'Comma-separated, Enter to skip',
                                               header: 'Task tags (optional)')
        tags = tags_input ? tags_input.split(',').map(&:strip).reject(&:empty?) : []

        create_task(description, category, priority, tags, store: store)
      end

      def self.parse_args(args, fmt)
        description = nil
        category = ''
        priority = nil
        tags = []

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return [nil, nil, nil, nil]
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

        [description, category, priority, tags]
      end

      def self.create_task(description, category, priority, tags, store:)
        category = Todo::Store::DEFAULT_CATEGORY if category.nil? || category.empty?
        category = category.downcase
        store.ensure_category(category)

        if priority
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
