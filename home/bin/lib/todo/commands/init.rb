# frozen_string_literal: true

module Todo
  module Commands
    module Init
      COMPLETIONS = {
        description: 'Initialize configuration'
      }.freeze

      def self.help(_fmt)
        puts 'Initialize todo configuration directory.'
      end

      def self.run(_args, store:, fmt: nil)
        store.init!
        puts "Initialized todo configuration at #{store.conf_dir}"
      end
    end
  end
end
