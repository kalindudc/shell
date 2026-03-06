# frozen_string_literal: true

module Todo
  module Commands
    module Edit
      COMPLETIONS = {
        description: 'Edit task fields',
        positional: :task_id,
        options: [
          { long: '--description', short: '-d', desc: 'Update description', arg: :text },
          { long: '--category', short: '-c', desc: 'Change category', arg: :category },
          { long: '--priority', short: '-p', desc: 'Change priority', arg: :text },
          { long: '--tag', short: '-t', desc: 'Add a tag', arg: :text, repeat: true },
          { long: '--remove-tag', short: '-rt', desc: 'Remove a tag', arg: :text, repeat: true }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('edit', 'todo edit <id> [options]', 'Edit fields of an existing task',
                              [['--description, -d <text>', 'Update description'],
                               ['--category, -c <name>',    'Change category'],
                               ['--priority, -p <0-9999>',  'Change priority'],
                               ['--tag, -t <tag>',          'Add a tag (repeatable)'],
                               ['--remove-tag, -rt <tag>',  'Remove a tag (repeatable)']])
        puts 'Aliases: e'
        puts
      end

      def self.run(args, store:, fmt:)
        return help(fmt) if ['-h', '--help'].include?(args.first)

        if args.empty?
          $stderr.puts 'Error: task ID required'
          exit 1
        end

        task_id = args.shift.to_i
        new_desc = nil
        new_cat = nil
        new_pri = nil
        add_tags = []
        rm_tags = []

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return
          when '-d', '--description' then new_desc = args.shift
          when '-c', '--category' then new_cat = args.shift
          when '-p', '--priority' then new_pri = args.shift
          when '-t', '--tag' then add_tags << args.shift
          when '--remove-tag', '-rt' then rm_tags << args.shift
          else $stderr.puts "Unknown argument: #{arg}"
               exit 1
          end
        end

        result = store.find_task(task_id)
        unless result
          $stderr.puts "Error: task ##{task_id} not found"
          exit 1
        end

        task, old_cat = result

        task['description'] = new_desc if new_desc
        if new_pri
          unless new_pri.match?(/\A\d+\z/) && new_pri.to_i.between?(0, 9999)
            $stderr.puts 'Error: priority must be a number 0-9999 (0=highest)'
            exit 1
          end
          task['priority'] = new_pri.to_i
        end
        task['tags'] = (task['tags'] || []) + add_tags unless add_tags.empty?
        task['tags'] = (task['tags'] || []) - rm_tags unless rm_tags.empty?
        task['modified'] = store.today

        if new_cat && new_cat.downcase != old_cat
          new_cat = new_cat.downcase
          store.ensure_category(new_cat)
          store.remove_task(task_id)
          task['category'] = new_cat
          store.save_task(task, new_cat)
        else
          task['category'] = old_cat
          store.save_task(task, old_cat)
        end

        puts "Updated task ##{task_id}"
      end
    end
  end
end
