# frozen_string_literal: true

require_relative 'store'
require_relative 'formatter'
require_relative 'task_renderer'
require_relative 'arg_parser'
require_relative 'interactive'
require_relative 'completions'
require_relative 'commands/init'
require_relative 'commands/add'
require_relative 'commands/list'
require_relative 'commands/edit'
require_relative 'commands/delete'
require_relative 'commands/search'
require_relative 'commands/category'
require_relative 'commands/show'
require_relative 'commands/mark'

module Todo
  module CLI
    # All command modules. COMMANDS is derived from each module's DEFINITION.
    COMMAND_MODULES = [
      Commands::Add,
      Commands::List,
      Commands::Mark,
      Commands::Edit,
      Commands::Delete,
      Commands::Search,
      Commands::Category,
      Commands::Show,
      Commands::Init
    ].freeze

    # Build COMMANDS hash from DEFINITION constants.
    COMMANDS = COMMAND_MODULES.each_with_object({}) do |mod, hash|
      defn = mod::DEFINITION
      hash[defn[:name]] = { mod: mod, aliases: defn[:aliases] || [] }
    end.freeze

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
      COMMANDS.each do |name, entry|
        defn = entry[:mod]::DEFINITION
        aliases = defn[:aliases] || []
        label = ([name] + aliases).join(', ')
        printf "  %-30s %s\n", label, defn[:description]
      end
      printf "  %-30s %s\n", 'help, --help, -h', 'Show this help'
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
    rescue Interrupt
      $stderr.puts
      exit 130
    end
  end
end
