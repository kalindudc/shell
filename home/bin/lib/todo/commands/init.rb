# frozen_string_literal: true

module Todo
  module Commands
    module Init
      DEFINITION = {
        name: 'init', aliases: [],
        description: 'Initialize configuration'
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('init', 'todo init', 'Initialize todo configuration directory')
      end

      def self.run(args, store:, fmt: nil)
        fmt ||= Todo::Formatter
        return help(fmt) if %w[-h --help].include?(args&.first)

        store.init!
        puts "Initialized todo configuration at #{store.conf_dir}"
      end
    end
  end
end
