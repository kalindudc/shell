# frozen_string_literal: true

require_relative '../interactive'

module Todo
  module Commands
    module Delete
      DEFINITION = {
        name: 'delete', aliases: %w[rm],
        description: 'Delete a task permanently',
        positional: { name: :task_id, type: :integer },
        options: [
          { long: '--force', short: '-f' }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('delete', 'todo delete <id> [options]', 'Permanently delete a task',
                              [['--force, -f', 'Skip confirmation prompt']])
        puts 'Aliases: rm'
        puts
      end

      def self.run(args, store:, fmt:)
        return help(fmt) if ['-h', '--help'].include?(args.first)

        force = args.delete('--force') || args.delete('-f')

        task_id = Interactive.require_task_id(args, store: store, source: :all, prompt: 'Delete> ')

        # Confirmation prompt (only when TTY and not --force)
        if !force && $stdin.tty?
          result = store.find_task(task_id)
          if result
            task, _cat = result
            unless Interactive.confirm("Delete task ##{task_id}: #{task['description']}?")
              puts 'Cancelled.'
              return
            end
          end
        end

        unless store.remove_task(task_id)
          $stderr.puts "Error: task ##{task_id} not found"
          exit 1
        end

        puts "Deleted task ##{task_id}"
      end
    end
  end
end
