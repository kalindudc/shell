# frozen_string_literal: true

module Todo
  module ArgParser
    # Parse command-line arguments against a declarative DEFINITION hash.
    #
    # Returns a hash with:
    #   - Named positional value(s) under their :name key
    #   - Option values under their normalized key (--done-only → :done_only)
    #   - { help: true } when -h/--help is detected
    #   - { error: "message" } on validation failure
    def self.parse(definition, args)
      args = args.dup
      result = {}

      # Early help detection
      return { help: true } if args.include?('-h') || args.include?('--help')

      options = definition[:options] || []
      positional = definition[:positional]

      # Build lookup tables for options
      opt_by_flag = {}
      options.each do |opt|
        opt_by_flag[opt[:long]] = opt if opt[:long]
        opt_by_flag[opt[:short]] = opt if opt[:short]

        # Initialize repeat options as empty arrays
        next unless opt[:repeat]

        key = option_key(opt)
        result[key] = []
      end

      # Initialize variadic positional as empty array
      result[positional[:name]] = [] if positional && positional[:repeat]

      # Parse arguments
      until args.empty?
        arg = args.shift

        # Check if it's an option
        if (opt = opt_by_flag[arg])
          parsed = parse_option(opt, args, arg)
          return parsed if parsed[:error]

          key = option_key(opt)
          if opt[:repeat]
            result[key] << parsed[:value]
          else
            result[key] = parsed[:value]
          end
        elsif arg.start_with?('-')
          return { error: "Unknown option: #{arg}" }
        elsif positional
          # It's a positional argument
          parsed = parse_positional(positional, arg, result, args)
          return parsed if parsed[:error]

          result.merge!(parsed)
        else
          return { error: "Unknown argument: #{arg}" }
        end
      end

      # Validate required positional
      return { error: "#{positional[:name]} is required" } if positional && positional[:required] && !result.key?(positional[:name])

      result
    end

    # ── Internal helpers ─────────────────────────────────────────────

    def self.option_key(opt)
      # --done-only → :done_only, --category → :category
      opt[:long].sub(/\A--/, '').tr('-', '_').to_sym
    end

    def self.parse_option(opt, args, flag)
      if opt[:arg]
        # Option requires a value
        value = args.shift
        return { error: "#{flag} requires a value" } if value.nil?

        if opt[:arg] == :integer
          return { error: "#{flag}: expected integer, got '#{value}'" } unless value.match?(/\A\d+\z/)

          int_val = value.to_i
          return { error: "#{flag}: #{int_val} out of range #{opt[:range]}" } if opt[:range] && !opt[:range].include?(int_val)

          { value: int_val }
        else
          { value: value }
        end
      else
        # Boolean flag
        { value: true }
      end
    end

    def self.parse_positional(positional, arg, result, _args)
      if positional[:repeat]
        # Variadic: collect this and remaining non-option args
        values = result[positional[:name]] || []

        if positional[:type] == :integer
          return { error: "Invalid integer for #{positional[:name]}: '#{arg}'" } unless arg.match?(/\A\d+\z/)

          values << arg.to_i
        else
          values << arg
        end

        { positional[:name] => values }
      elsif result.key?(positional[:name])
        # Already have a positional, this is extra
        { error: "Unknown argument: #{arg}" }
      elsif positional[:type] == :integer
        # Single positional
        return { error: "Invalid integer for #{positional[:name]}: '#{arg}'" } unless arg.match?(/\A\d+\z/)

        { positional[:name] => arg.to_i }
      else
        { positional[:name] => arg }
      end
    end

    private_class_method :option_key, :parse_option, :parse_positional
  end
end
