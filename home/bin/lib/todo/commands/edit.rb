# frozen_string_literal: true

require_relative '../interactive'

module Todo
  module Commands
    module Edit # rubocop:disable Metrics/ModuleLength
      DEFINITION = {
        name: 'edit', aliases: %w[e],
        description: 'Edit task fields',
        positional: { name: :task_id, type: :integer },
        options: [
          { long: '--description', short: '-d', arg: :text },
          { long: '--category', short: '-c', arg: :category },
          { long: '--priority', short: '-p', arg: :text },
          { long: '--tag', short: '-t', arg: :text, repeat: true },
          { long: '--remove-tag', short: '-rt', arg: :text, repeat: true }
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
        return run_interactive(store: store) if args.empty? && $stdin.tty?

        task_id = Interactive.require_task_id(args, store: store, source: :active, prompt: 'Edit> ')
        args.shift if args.first&.to_i == task_id
        edits = parse_args(args, fmt)
        return unless edits

        apply_edits(task_id, edits, store: store)
      end

      def self.run_interactive(store:)
        task_id = Interactive.require_task_id([], store: store, source: :active, prompt: 'Edit> ')
        result = store.find_task(task_id)
        unless result
          $stderr.puts "Error: task ##{task_id} not found"
          exit 1
        end
        task, _cat = result
        puts "Editing task ##{task_id}: #{task['description']}"
        puts 'Press Enter to keep current value.'
        puts
        edits = prompt_fields(task, store)
        apply_edits(task_id, edits, store: store)
      end

      def self.prompt_fields(task, store)
        new_desc = Interactive.input('Description', default: task['description'],
                                                    header: 'Edit description (Enter to keep)')
        new_desc = nil if new_desc == task['description']

        new_cat = Interactive.filter(store.all_categories, prompt: 'Category> ',
                                                           header: 'Change category (ESC to keep)',
                                                           allow_custom: true)
        new_cat = nil if new_cat == task['category']

        current_pri = task['priority'].to_s
        pri_default = current_pri.empty? ? nil : current_pri
        new_pri = Interactive.input('Priority', default: pri_default,
                                                placeholder: '0-9 (0=highest), Enter to keep',
                                                header: 'Edit priority (Enter to keep)')
        new_pri = nil if new_pri == current_pri

        current_tags = (task['tags'] || []).join(', ')
        tags_default = current_tags.empty? ? nil : current_tags
        tags_input = Interactive.input('Tags', default: tags_default,
                                               placeholder: 'Comma-separated (replaces existing), Enter to keep',
                                               header: 'Edit tags (Enter to keep)')
        new_tags = tags_input.split(',').map(&:strip).reject(&:empty?) if tags_input && tags_input != current_tags

        { new_desc: new_desc, new_cat: new_cat, new_pri: new_pri, new_tags: new_tags, add_tags: [], rm_tags: [] }
      end

      def self.parse_args(args, fmt)
        edits = { new_desc: nil, new_cat: nil, new_pri: nil, new_tags: nil, add_tags: [], rm_tags: [] }

        while (arg = args.shift)
          case arg
          when '-h', '--help' then help(fmt)
                                   return nil
          when '-d', '--description' then edits[:new_desc] = args.shift
          when '-c', '--category' then edits[:new_cat] = args.shift
          when '-p', '--priority' then edits[:new_pri] = args.shift
          when '-t', '--tag' then edits[:add_tags] << args.shift
          when '--remove-tag', '-rt' then edits[:rm_tags] << args.shift
          else $stderr.puts "Unknown argument: #{arg}"
               exit 1
          end
        end
        edits
      end

      def self.apply_edits(task_id, edits, store:)
        result = store.find_task(task_id)
        unless result
          $stderr.puts "Error: task ##{task_id} not found"
          exit 1
        end

        task, old_cat = result

        task['description'] = edits[:new_desc] if edits[:new_desc]
        apply_priority(task, edits[:new_pri]) if edits[:new_pri]
        task['tags'] = edits[:new_tags] if edits[:new_tags]
        task['tags'] = (task['tags'] || []) + edits[:add_tags] unless edits[:add_tags].empty?
        task['tags'] = (task['tags'] || []) - edits[:rm_tags] unless edits[:rm_tags].empty?
        task['modified'] = store.today

        save_with_category(task, task_id, edits[:new_cat], old_cat, store: store)
        puts "Updated task ##{task_id}"
      end

      def self.apply_priority(task, new_pri)
        if new_pri.nil? || new_pri.empty?
          task['priority'] = nil
          return
        end

        unless new_pri.match?(/\A\d+\z/) && new_pri.to_i.between?(0, 9999)
          $stderr.puts 'Error: priority must be a number 0-9999 (0=highest)'
          exit 1
        end
        task['priority'] = new_pri.to_i
      end

      def self.save_with_category(task, task_id, new_cat, old_cat, store:)
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
      end
    end
  end
end
