# frozen_string_literal: true

require_relative '../interactive'

module Todo
  module Commands
    module Mark
      DEFINITION = {
        name: 'mark', aliases: %w[m],
        description: 'Toggle task status (done/pending)',
        positional: { name: :task_ids, type: :integer, repeat: true },
        options: [
          { long: '--category', short: '-c', arg: :category },
          { long: '--tag', short: '-t', arg: :text }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('mark', 'todo mark [ids...] [options]',
                              'Toggle task status between done and pending',
                              [['--category, -c <name>', 'Filter picker by category'],
                               ['--tag, -t <tag>',       'Filter picker by tag']],
                              ['todo mark',                  'Interactive multi-select (Enter to toggle, w/s to save)',
                               'todo mark 1 2 3',            'Toggle tasks #1, #2, #3',
                               'todo mark -c work',          'Pick from work category only',
                               'todo mark -t urgent',        'Pick from tasks tagged urgent'])
        puts 'Aliases: m'
        puts
      end

      def self.run(args, store:, fmt:)
        return help(fmt) if ['-h', '--help'].include?(args.first)

        task_ids, filter_cat, filter_tag = parse_args(args)

        task_ids = Interactive.multi_toggle(store: store, filter_cat: filter_cat, filter_tag: filter_tag) if task_ids.empty? && $stdin.tty?

        if task_ids.empty?
          $stderr.puts 'Error: no tasks selected' unless $stdin.tty?
          exit($stdin.tty? ? 0 : 1)
        end

        toggle_tasks(task_ids, store: store)
      end

      def self.parse_args(args)
        ids = []
        filter_cat = nil
        filter_tag = nil

        while (arg = args.shift)
          case arg
          when '-c', '--category' then filter_cat = args.shift
          when '-t', '--tag' then filter_tag = args.shift
          else
            id = arg.to_i
            if id.positive?
              ids << id
            else
              $stderr.puts "Unknown argument: #{arg}"
              exit 1
            end
          end
        end

        [ids, filter_cat, filter_tag]
      end

      def self.toggle_tasks(task_ids, store:)
        toggled_done = []
        toggled_pending = []

        task_ids.each do |task_id|
          result = store.find_task(task_id)
          unless result
            $stderr.puts "Warning: task ##{task_id} not found, skipping"
            next
          end

          task, cat = result
          if task['status'] == 'done'
            task['status'] = 'pending'
            task.delete('completed')
            toggled_pending << task_id
          else
            task['status'] = 'done'
            task['completed'] = store.today
            toggled_done << task_id
          end
          task['modified'] = store.today
          store.save_task(task, cat)
        end

        print_summary(toggled_done, toggled_pending)
      end

      def self.print_summary(done_ids, pending_ids)
        done_ids.each { |id| puts "Completed task ##{id}" }
        pending_ids.each { |id| puts "Reopened task ##{id}" }
      end
    end
  end
end
