# frozen_string_literal: true

module Todo
  module Commands
    module Delete
      COMPLETIONS = {
        description: 'Delete a task permanently',
        positional: :task_id
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('delete', 'todo delete <id>', 'Permanently delete a task (not moved to history)')
        puts 'Aliases: rm'
        puts
      end

      def self.run(args, store:, fmt:)
        return help(fmt) if ['-h', '--help'].include?(args.first)

        if args.empty?
          $stderr.puts 'Error: task ID required'
          exit 1
        end

        task_id = args.first.to_i
        unless store.remove_task(task_id)
          $stderr.puts "Error: task ##{task_id} not found"
          exit 1
        end

        puts "Deleted task ##{task_id}"
      end
    end
  end
end
