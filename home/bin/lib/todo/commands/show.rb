# frozen_string_literal: true

require 'json'
require_relative '../interactive'
require_relative '../task_renderer'

module Todo
  module Commands
    module Show
      DEFINITION = {
        name: 'show', aliases: %w[s v],
        description: 'View detailed task info',
        positional: { name: :task_id, type: :integer },
        options: [
          { long: '--json', short: '-J' }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('show', 'todo show <id> [options]', 'View detailed information for a task (active or completed)',
                              [['--json, -J', 'JSON output']])
        puts 'Aliases: s, v'
        puts
      end

      def self.run(args, store:, fmt:)
        return help(fmt) if ['-h', '--help'].include?(args.first)

        json = false
        clean_args = args.reject { |a| json = true if ['-J', '--json'].include?(a) }

        task_id = Interactive.require_task_id(clean_args, store: store, source: :all, prompt: 'Show> ')
        result = store.find_task(task_id)

        unless result
          $stderr.puts "Error: task ##{task_id} not found"
          exit 1
        end

        task, _cat = result

        if json
          puts JSON.generate(TaskRenderer.task_to_hash(task))
          return
        end

        print_detail(task, task_id, fmt)
      end

      def self.print_detail(task, task_id, fmt)
        status_str = task['status'] == 'done' ? fmt.c_green(task['status']) : fmt.c_yellow(task['status'])
        raw_pri = task['priority']
        pri_display = raw_pri.to_s
        unless pri_display.empty?
          color_code = fmt.priority_color(raw_pri)
          pri_display = "\033[#{color_code}m#{pri_display}\033[0m" if color_code && !Todo::Formatter::NO_COLOR
        end
        tags_str = (task['tags'] || []).map { |t| fmt.c_cyan("##{t}") }.join(', ')

        puts
        puts "  #{fmt.c_bold("Task ##{task_id}")}"
        puts "  #{fmt.c_dim('Description')}  #{task['description']}"
        puts "  #{fmt.c_dim('Status')}       #{status_str}"
        puts "  #{fmt.c_dim('Priority')}     #{pri_display}" unless pri_display.empty?
        puts "  #{fmt.c_dim('Category')}     #{task['category']}" unless task['category'].to_s.empty?
        puts "  #{fmt.c_dim('Tags')}         #{tags_str}" unless tags_str.empty?
        puts "  #{fmt.c_dim('Created')}      #{task['created']}"
        puts "  #{fmt.c_dim('Modified')}     #{task['modified']}"
        puts "  #{fmt.c_dim('Completed')}    #{task['completed']}" if task['completed']
        puts
      end
    end
  end
end
