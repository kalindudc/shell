# frozen_string_literal: true

require 'open3'
require 'tempfile'
require_relative 'store'
require_relative 'task_renderer'

module Todo
  # Unified interactive module replacing Picker + Prompt.
  # Provides consistent API and graceful degradation: fzf → gum → bare stdin.
  module Interactive # rubocop:disable Metrics/ModuleLength
    # ── High-level API (used by commands) ────────────────────────────

    # Single-select a task via fzf. Delegates to browse with standard keybinds.
    def self.select(store:, source: :active, prompt: 'Select> ')
      filters = { include_done: source != :active, done_only: source == :done }
      browse(store: store, filters: filters, prompt: prompt)
    end

    # Interactive toggle loop via fzf. Returns array of toggled task IDs.
    def self.multi_toggle(store:, filter_cat: nil, filter_tag: nil, prompt: 'Mark> ')
      return [] unless fzf_tty?

      lines = fzf_task_lines(store, include_done: true, filter_cat: filter_cat, filter_tag: filter_tag)
      return [] if lines.empty?

      toggled = Set.new
      cursor_pos = 1

      result = fzf_loop(store, prompt: prompt,
                               key_handlers: {
                                 'w' => ->(_id) { throw(:fzf_loop_done, toggled.to_a) },
                                 's' => ->(_id) { throw(:fzf_loop_done, toggled.to_a) }
                               },
                               on_enter: lambda { |id|
                                 cursor_pos = find_cursor_pos(lines, id)
                                 toggled.include?(id) ? toggled.delete(id) : toggled.add(id)
                                 :next
                               }) do
        display = build_toggled_display(lines, toggled)
        { lines: display,
          header: 'Enter: toggle    w/s: save    ESC/q: cancel',
          extra_args: ['--bind', "load:pos(#{cursor_pos})"] }
      end

      result.is_a?(Array) ? result : []
    end

    # Read-only browse via fzf with toggleable --all filter.
    # Enter selects a task and returns its ID (caller can then show detail).
    # a: toggles include_done (show all / active only). q/ESC exits, returning nil.
    def self.browse(store:, filters: {}, prompt: 'List> ')
      return nil unless fzf_tty?

      current_filters = filters.dup

      fzf_loop(store, prompt: prompt,
                      key_handlers: {
                        'a' => lambda { |_id|
                          current_filters[:include_done] = !current_filters[:include_done]
                          current_filters[:done_only] = false if current_filters[:include_done]
                          :next
                        }
                      },
                      on_enter: ->(id) { throw(:fzf_loop_done, id) }) do
        lines = fzf_task_lines(store, **current_filters)
        throw(:fzf_loop_done, nil) if lines.empty?

        show_all = current_filters[:include_done] || current_filters[:done_only]
        count = lines.count("\n") + 1
        status = "#{TaskRenderer.render_footer(count, 'tasks')}  |  "
        toggle_hint = "a: #{show_all ? 'active only' : 'show all'}"
        { lines: lines,
          header: "#{status}Enter: show    #{toggle_hint}    q/ESC: close" }
      end
    end

    # Fuzzy search via fzf. Delegates to browse with standard keybinds.
    def self.search(store:, prompt: 'Search> ')
      browse(store: store, filters: { include_done: true }, prompt: prompt)
    end

    # Text input via fzf → fallback. Returns string or nil.
    def self.input(label, default: nil, placeholder: nil, header: nil)
      return nil unless $stdin.tty?

      if fzf_available?
        fzf_input(label, default: default, placeholder: placeholder, header: header)
      else
        fallback_input(label, default: default)
      end
    end

    # Filterable list via fzf → fallback. Returns string or nil.
    def self.filter(items, prompt: '> ', header: nil, allow_custom: false)
      return nil unless $stdin.tty?

      if fzf_available?
        fzf_filter(items, prompt: prompt, header: header, allow_custom: allow_custom)
      else
        fallback_input(prompt, default: items.first)
      end
    end

    # Yes/no confirmation via fzf → fallback. Returns boolean.
    def self.confirm(message, default: false)
      return default unless $stdin.tty?

      if fzf_available?
        fzf_confirm(message, default: default)
      else
        fallback_confirm(message, default: default)
      end
    end

    # Parse first arg as ID, fall back to .select() if missing.
    def self.require_task_id(args, store:, source: :active, prompt: 'Select> ')
      task_id = args.first&.to_i
      return task_id if task_id&.positive?

      task_id = self.select(store: store, source: source, prompt: prompt)
      return task_id if task_id

      $stderr.puts 'Error: task ID required' unless $stdin.tty?
      exit($stdin.tty? ? 0 : 1)
    end

    # ── Public helpers (for testability) ─────────────────────────────

    # Generate sorted, filtered fzf-formatted lines via Store.query_tasks.
    # Overrides desc_max with a dynamically computed value that fits within the
    # fzf list pane (60% of terminal after the preview panel).
    def self.fzf_task_lines(store, **query_opts)
      tasks = store.query_tasks(**query_opts)
      config = store.load_config.merge('desc_max' => TaskRenderer.fzf_desc_max)
      tasks.map { |t| TaskRenderer.render_fzf(t, config: config) }.join("\n")
    end

    # Flip checkboxes for toggled IDs.
    def self.build_toggled_display(original_lines, toggled)
      original_lines.each_line.map do |line|
        stripped = line.chomp
        task_id = extract_task_id(stripped)
        if task_id && toggled.include?(task_id)
          stripped = if stripped.include?('[x]')
                       stripped.sub('[x]', '[ ]')
                     else
                       stripped.sub('[ ]', '[x]')
                     end
        end
        stripped
      end.join("\n")
    end

    # Bare stdin text input fallback.
    def self.fallback_input(label, default: nil)
      return nil unless $stdin.tty?

      suffix = default ? " [#{default}]" : ''
      print "#{label}#{suffix}: "
      value = $stdin.gets&.chomp
      return default if value.nil? || value.empty?

      value
    end

    # Bare stdin y/n prompt.
    def self.fallback_confirm(message, default: false)
      return default unless $stdin.tty?

      hint = default ? '[Y/n]' : '[y/N]'
      print "#{message} #{hint}: "
      value = $stdin.gets&.chomp&.downcase
      return default if value.nil? || value.empty?

      value.start_with?('y')
    end

    # Base fzf args shared by all fzf invocations. Extracted for testability.
    # --tabstop=9999 pushes the hidden full-description (after TAB) off-screen
    # while keeping it searchable.
    def self.fzf_base_args
      ['fzf', '--exact', '--no-sort', '--tabstop=9999', '--cycle', '--bind=tab:down,shift-tab:up']
    end

    def self.fzf_available?
      @fzf_available = system('command -v fzf > /dev/null 2>&1') if @fzf_available.nil?
      @fzf_available
    end

    def self.reset_cache!
      @fzf_available = nil
    end

    # ── Private helpers ──────────────────────────────────────────────

    # Shared fzf loop engine. Uses mark's visual style as the standard:
    # --height=50%, --layout=reverse, preview panel, --sync with cursor.
    #
    # Starts in navigation mode (--disabled --no-input): single-letter
    # keybinds are active, search input is hidden. Press / to enter search
    # mode (input shown, typing filters). Press ESC in search mode to return
    # to nav. Press q or ESC in nav mode to quit.
    #
    # key_handlers: Hash of key => lambda(task_id). Return :next to loop,
    #               or throw(:fzf_loop_done, value) to exit with a result.
    # on_enter:     lambda(task_id) called when Enter is pressed.
    #               Return :next to loop, or throw(:fzf_loop_done, value).
    # block:        yields each iteration, returns { lines:, header:, extra_args:[] }.
    #
    # Returns the value thrown via :fzf_loop_done, or nil on q/ESC.
    def self.fzf_loop(store, prompt:, key_handlers: {}, on_enter: nil)
      esc_script = nil

      catch(:fzf_loop_done) do # rubocop:disable Metrics/BlockLength
        loop do # rubocop:disable Metrics/BlockLength
          iteration = yield
          return nil unless iteration

          lines = iteration[:lines]
          header = iteration[:header]
          extra = iteration[:extra_args] || []

          # Rebuild keybinds each iteration (header may change)
          esc_script&.close!
          esc_script = build_esc_script(key_handlers.keys, header)
          keybinds = build_fzf_keybinds(key_handlers.keys, header, esc_script.path)

          selected, status = run_fzf(store, lines,
                                     prompt: prompt, height: '50%',
                                     sync: true,
                                     extra_args: keybinds + extra)

          # ESC/q in nav mode → exit 130; fzf error → exit != 0
          return nil unless status.success?

          output = selected.strip
          return nil if output.empty?

          # Key action: "KEY_a" from --bind 'a:print(KEY_a)+accept'
          if output.start_with?('KEY_')
            key = output.delete_prefix('KEY_').split("\n").first
            handler = key_handlers[key]
            next handler.call(nil) == :next if handler

            return nil
          end

          # Enter: normal selection
          task_id = extract_task_id(output)
          next unless task_id&.positive?

          if on_enter
            result = on_enter.call(task_id)
            next if result == :next
          end

          return nil
        end
      end
    ensure
      esc_script&.close!
    end

    NAV_HEADER_PREFIX = '/: search    '
    SEARCH_HEADER = 'type to filter, ESC: back'

    # Build the ESC transform shell script as a tempfile.
    # In nav mode (input hidden) → abort. In search mode → exit search, return to nav.
    def self.build_esc_script(custom_keys, header)
      nav_keys_csv = (custom_keys + ['q']).uniq.join(',')
      nav_header = "#{NAV_HEADER_PREFIX}#{header}"

      script = Tempfile.new(['fzf_esc', '.sh'])
      script.write(<<~SH)
        if [ "$FZF_INPUT_STATE" = "hidden" ]; then
          echo "abort"
        else
          echo "disable-search+hide-input+clear-query+search()+rebind(#{nav_keys_csv},/)+change-header(#{nav_header})"
        fi
      SH
      script.close
      script
    end

    # Build --bind and --disabled/--no-input args for the nav/search mode toggle.
    def self.build_fzf_keybinds(custom_keys, header, esc_script_path)
      nav_keys = (custom_keys + ['q']).uniq
      nav_keys_csv = nav_keys.join(',')
      nav_header = "#{NAV_HEADER_PREFIX}#{header}"

      args = ['--disabled', '--no-input', '--header', nav_header]

      # / → enter search mode
      args += ['--bind', "/:enable-search+show-input+clear-query+unbind(#{nav_keys_csv})" \
                         "+change-header(#{SEARCH_HEADER})"]

      # ESC → transform checks FZF_INPUT_STATE to decide nav-quit vs exit-search
      args += ['--bind', "esc:transform(bash #{esc_script_path})"]

      # q → quit (nav mode only, unbound during search)
      args += ['--bind', 'q:abort']

      # Custom key handlers: print a marker and accept (unbound during search)
      custom_keys.each do |key|
        args += ['--bind', "#{key}:print(KEY_#{key})+accept"]
      end

      args
    end

    # Single-shot fzf invocation. Assembles args and calls Open3.capture2.
    def self.run_fzf(store, input, **opts)
      args = [*fzf_base_args, '--layout=reverse', "--height=#{opts.fetch(:height, '50%')}",
              "--prompt=#{opts[:prompt]}"]
      args << "--header=#{opts[:header]}" if opts[:header]
      args << '--header-first' if opts[:header_first]
      args << '--sync' if opts[:sync]
      args += ["--preview=#{preview_cmd(store)}", '--preview-window=right:40%:wrap']
      args += opts[:extra_args] if opts[:extra_args]
      Open3.capture2(*args, stdin_data: input)
    end

    def self.preview_cmd(store)
      bin = todo_bin_path(store)
      "#{bin} show $(echo {} | grep -oE '\\]\\s+[0-9]+' | grep -oE '[0-9]+')"
    end

    def self.fzf_tty?
      $stdin.tty? && fzf_available?
    end

    def self.todo_bin_path(store)
      ENV['TODO_CONF_DIR'] ||= store.conf_dir
      File.expand_path('../../todo', __dir__)
    end

    # Extract task ID from a render_fzf formatted line.
    def self.extract_task_id(line)
      match = line&.match(/\[.\]\s+(\d+)/)
      match && match[1].to_i
    end

    def self.find_cursor_pos(lines, task_id)
      lines.each_line.with_index(1) do |line, idx|
        return idx if extract_task_id(line) == task_id
      end
      1
    end

    # fzf as a single-line text input (--disabled turns off filtering).
    # --print-query returns the typed text. Empty stdin so fzf shows no list.
    # The header line serves as the hint/placeholder (fzf has no placeholder flag).
    def self.fzf_input(label, default: nil, placeholder: nil, header: nil)
      hint = header || placeholder || label
      hint = "#{hint} (current: #{default})" if default && !header

      args = ['fzf', '--disabled', '--print-query',
              '--prompt', "  #{label} > ",
              '--header', "  #{hint}",
              '--height=3', '--layout=reverse', '--no-info',
              '--color=header:italic:dim,prompt:green:bold']
      args.push('--query', default) if default

      selected, status = Open3.capture2(*args, stdin_data: '')
      # fzf exits 1 when no match, but --print-query still outputs the query
      return nil unless status.success? || status.exitstatus == 1

      value = selected.split("\n").first&.strip
      value.nil? || value.empty? ? nil : value
    end

    # fzf as a filterable list with optional custom input.
    # --print-query outputs [query, selected]. We take the selected line if present,
    # otherwise the query (for custom/new values when allow_custom is true).
    def self.fzf_filter(items, prompt: '> ', header: '', allow_custom: false)
      args = ['fzf', '--print-query', '--cycle',
              '--prompt', "  #{prompt}",
              '--header', "  #{header}",
              '--height=10', '--layout=reverse', '--no-info',
              '--bind=tab:down,shift-tab:up',
              '--color=header:italic:dim,prompt:green:bold,pointer:green']

      input = items.join("\n")
      selected, status = Open3.capture2(*args, stdin_data: input)

      lines = selected.split("\n")
      query = lines[0]&.strip
      picked = lines[1]&.strip

      # ESC (exit 130) = cancelled
      return nil if status.exitstatus == 130

      # If an item was selected, use it; otherwise use the typed query if custom allowed
      if picked && !picked.empty?
        picked
      elsif allow_custom && query && !query.empty?
        query
      end
    end

    # fzf as a yes/no confirmation. Presents Yes/No as selectable list items.
    def self.fzf_confirm(message, default: false)
      ordered = default ? %w[Yes No] : %w[No Yes]

      args = ['fzf', '--no-sort', '--cycle', '--disabled',
              '--prompt', '  Confirm > ',
              '--query', ordered.first,
              '--header', "  #{message}",
              '--height=5', '--layout=reverse', '--no-info',
              '--bind=tab:down,shift-tab:up',
              '--bind=focus:transform-query(echo {})',
              '--color=header:italic:dim,prompt:green:bold,pointer:green']

      selected, status = Open3.capture2(*args, stdin_data: ordered.join("\n"))
      return default unless status.success?

      selected.strip == 'Yes'
    end

    private_class_method :todo_bin_path, :find_cursor_pos, :fzf_input, :fzf_filter, :fzf_confirm,
                         :run_fzf, :preview_cmd, :fzf_tty?, :fzf_loop,
                         :build_esc_script, :build_fzf_keybinds
  end
end
