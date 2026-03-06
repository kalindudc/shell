# frozen_string_literal: true

module Todo
  module Commands
    module Category
      COMPLETIONS = {
        description: 'Manage categories',
        subcommands: [
          { name: 'list', aliases: %w[l], desc: 'List categories' },
          { name: 'add', aliases: %w[a], desc: 'Add category' },
          { name: 'delete', aliases: %w[rm], desc: 'Delete category' }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('category', 'todo category <subcommand> [options]', 'Manage task categories')
        puts 'Subcommands:'
        printf "  %-20s %s\n", 'list, l', 'List all categories'
        printf "  %-20s %s\n", 'add, a <name> [opts]', 'Add a category (--description, --color)'
        printf "  %-20s %s\n", 'delete, rm <name>', 'Delete a category (--force to delete with tasks)'
        puts
        puts 'Aliases: cat'
        puts
      end

      def self.run(args, store:, fmt:)
        return help(fmt) if ['-h', '--help'].include?(args.first)

        if args.empty?
          $stderr.puts 'Error: subcommand required (list, add, delete)'
          exit 1
        end

        subcmd = args.shift

        case subcmd
        when 'list', 'l'
          cats = store.all_categories
          if cats.empty?
            puts 'No categories defined.'
            return
          end
          cats.each do |name|
            meta = store.category_meta(name)
            desc = meta['description'] || ''
            puts "  #{fmt.c_bold(name)}  #{fmt.c_dim(desc)}"
          end
          puts
        when 'add', 'a'
          if args.empty?
            $stderr.puts 'Error: category name required'
            exit 1
          end
          name = args.shift.downcase
          cdesc = ''
          ccolor = ''
          while (arg = args.shift)
            case arg
            when '-d', '--description' then cdesc = args.shift
            when '--color' then ccolor = args.shift
            else $stderr.puts "Unknown argument: #{arg}"
                 exit 1
            end
          end
          store.ensure_category(name, description: cdesc, color: ccolor)
          puts "Added category '#{name}'"
        when 'delete', 'rm'
          if args.empty?
            $stderr.puts 'Error: category name required'
            exit 1
          end
          name = args.shift.downcase
          force = args.include?('--force')
          dir = store.category_dir(name)
          unless Dir.exist?(dir)
            $stderr.puts "Error: category '#{name}' does not exist"
            exit 1
          end
          tasks = store.read_category_tasks(name)
          if tasks.any? && !force
            $stderr.puts "Error: category '#{name}' has #{tasks.length} task(s). Use --force to delete."
            exit 1
          end
          store.remove_category(name)
          puts "Deleted category '#{name}'"
        else
          $stderr.puts "Unknown subcommand: #{subcmd}"
          exit 1
        end
      end
    end
  end
end
