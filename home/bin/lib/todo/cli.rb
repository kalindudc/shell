# frozen_string_literal: true

require_relative 'store'
require_relative 'formatter'
require_relative 'completions'
require_relative 'commands/init'
require_relative 'commands/add'
require_relative 'commands/list'
require_relative 'commands/done'
require_relative 'commands/edit'
require_relative 'commands/delete'
require_relative 'commands/search'
require_relative 'commands/category'
require_relative 'commands/history'
require_relative 'commands/show'

module Todo
  module CLI
    COMMANDS = {
      'add' => { mod: Commands::Add, aliases: %w[a] },
      'list' => { mod: Commands::List,      aliases: %w[l ls] },
      'done' => { mod: Commands::Done,      aliases: %w[d] },
      'edit' => { mod: Commands::Edit,      aliases: %w[e] },
      'delete' => { mod: Commands::Delete,    aliases: %w[rm] },
      'search' => { mod: Commands::Search,    aliases: %w[find f] },
      'category' => { mod: Commands::Category, aliases: %w[cat] },
      'history' => { mod: Commands::History, aliases: %w[h] },
      'show' => { mod: Commands::Show,      aliases: %w[s v] },
      'init' => { mod: Commands::Init,      aliases: [] }
    }.freeze

    def self.resolve_command(name)
      return COMMANDS[name] if COMMANDS.key?(name)

      COMMANDS.each_value do |entry|
        return entry if entry[:aliases].include?(name)
      end
      nil
    end

    def self.help_main(fmt)
      puts "#{fmt.c_bold('todo')} - CLI task tracker"
      puts
      puts 'usage: todo <command> [options]'
      puts
      puts 'Available commands:'
      cmds = [
        ['add, a <desc> [opts]',       'Add a new task'],
        ['list, l, ls [opts]',         'List tasks with optional filters'],
        ['done, d <id>',               'Mark task as complete'],
        ['edit, e <id> [opts]',        'Edit task fields'],
        ['delete, rm <id>',            'Permanently delete a task'],
        ['search, find, f <term>',     'Search tasks'],
        ['category, cat <sub>',        'Manage categories (sub: list/add/delete)'],
        ['history, h [opts]',          'Browse completed tasks'],
        ['show, s, v <id>',            'View detailed task info'],
        ['init',                       'Initialize configuration'],
        ['help, --help, -h',           'Show this help']
      ]
      cmds.each { |cmd, desc| printf "  %-30s %s\n", cmd, desc }
      puts
      puts "Run #{fmt.c_bold('todo <command> -h')} to see options for a specific command."
      puts
    end

    def self.run(argv)
      fmt = Todo::Formatter
      cmd_name = argv.shift || ''

      case cmd_name
      when 'help', '--help', '-h', ''
        help_main(fmt)
        return
      when '--completions'
        shell = argv.shift
        case shell
        when 'zsh'
          print Completions::Zsh.generate(COMMANDS)
        else
          $stderr.puts "Unknown shell: #{shell || '(none)'}. Supported: zsh"
          exit 1
        end
        return
      end

      conf_dir = ENV['TODO_CONF_DIR'] || File.join(Dir.home, 'conf', 'todo')
      store = Todo::Store.new(conf_dir)

      entry = resolve_command(cmd_name)

      # init doesn't require existing config
      if entry && entry[:mod] == Commands::Init
        entry[:mod].run(argv.dup, store: store, fmt: fmt)
        return
      end

      unless store.initialized?
        $stderr.puts "Configuration directory not found: #{conf_dir}"
        $stderr.puts "configuration not found, run 'todo init'"
        exit 1
      end

      unless entry
        $stderr.puts "Error: unknown command '#{cmd_name}'"
        $stderr.puts
        help_main(fmt)
        exit 1
      end

      args = argv.dup
      argv.clear
      entry[:mod].run(args, store: store, fmt: fmt)
    end
  end
end
