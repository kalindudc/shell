# frozen_string_literal: true

module Todo
  module Commands
    module Done
      COMPLETIONS = {
        description: 'Mark a task as complete',
        positional: :task_id
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('done', 'todo done <id>', 'Mark a task as complete and move to history')
        puts 'Aliases: d'
        puts
      end

      def self.run(args, store:, fmt:)
        return help(fmt) if ['-h', '--help'].include?(args.first)

        if args.empty?
          $stderr.puts 'Error: task ID required'
          exit 1
        end

        task_id = args.first.to_i
        result = store.find_task(task_id)

        unless result
          $stderr.puts "Error: task ##{task_id} not found"
          exit 1
        end

        task, cat = result
        task['status'] = 'done'
        task['completed'] = store.today
        task['modified'] = store.today
        store.save_task(task, cat)

        puts "Completed task ##{task_id}"
      end
    end
  end
end
