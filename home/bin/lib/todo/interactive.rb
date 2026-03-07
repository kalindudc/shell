# frozen_string_literal: true

require 'open3'
require_relative 'store'
require_relative 'task_renderer'

module Todo
  # Unified interactive module replacing Picker + Prompt.
  # Provides consistent API and graceful degradation: fzf → gum → bare stdin.
  module Interactive # rubocop:disable Metrics/ModuleLength
    # ── High-level API (used by commands) ────────────────────────────

    # Single-select a task via fzf. Returns task ID or nil.
    def self.select(store:, source: :active, prompt: 'Select> ')
      return nil unless $stdin.tty? && fzf_available?

      input = task_list_string(store, source: source)
      return nil if input.empty?

      todo_bin = todo_bin_path(store)
      preview_cmd = "#{todo_bin} show $(echo {} | grep -oE '\\]\\s+[0-9]+' | grep -oE '[0-9]+')"
      selected, status = Open3.capture2(
        *fzf_base_args, '--layout=reverse', '--height=40%',
        "--prompt=#{prompt}",
        "--preview=#{preview_cmd}",
        '--preview-window=right:40%:wrap',
        stdin_data: input
      )
      return nil unless status.success?

      extract_task_id(selected)
    end

    # Interactive toggle loop via fzf. Returns array of toggled task IDs.
    def self.multi_toggle(store:, filter_cat: nil, filter_tag: nil, prompt: 'Mark> ')
      return [] unless $stdin.tty? && fzf_available?

      lines = task_list_string(store, source: :all, filter_cat: filter_cat, filter_tag: filter_tag)
      return [] if lines.empty?

      toggled = Set.new
      todo_bin = todo_bin_path(store)
      header = 'Enter: toggle    w/s: save    ESC/q: cancel'
      cursor_pos = 1

      loop do
        display = build_toggled_display(lines, toggled)
        preview_cmd = "#{todo_bin} show $(echo {} | grep -oE '\\]\\s+[0-9]+' | grep -oE '[0-9]+')"
        selected, status = Open3.capture2(
          *fzf_base_args, '--layout=reverse', '--height=50%',
          "--prompt=#{prompt}", "--header=#{header}",
          '--expect=w,s,q',
          '--sync', '--bind', "load:pos(#{cursor_pos})",
          "--preview=#{preview_cmd}",
          '--preview-window=right:40%:wrap',
          stdin_data: display
        )

        out_lines = selected.split("\n")
        key = out_lines[0]&.strip
        item = out_lines[1]

        break [] if !status.success? || key == 'q'
        break toggled.to_a if %w[w s].include?(key)

        task_id = item && extract_task_id(item)
        next unless task_id&.positive?

        cursor_pos = find_cursor_pos(lines, task_id)

        if toggled.include?(task_id)
          toggled.delete(task_id)
        else
          toggled.add(task_id)
        end
      end
    end

    # Fuzzy search via fzf. Returns task ID or nil.
    def self.search(store:, prompt: 'Search> ')
      return nil unless $stdin.tty? && fzf_available?

      input = task_list_string(store, source: :all)
      return nil if input.empty?

      todo_bin = todo_bin_path(store)
      preview_cmd = "#{todo_bin} show $(echo {} | grep -oE '\\]\\s+[0-9]+' | grep -oE '[0-9]+')"
      selected, status = Open3.capture2(
        *fzf_base_args, '--layout=reverse', '--height=50%',
        "--prompt=#{prompt}",
        "--preview=#{preview_cmd}",
        '--preview-window=right:40%:wrap',
        stdin_data: input
      )
      return nil unless status.success?

      extract_task_id(selected)
    end

    # Text input: gum → fallback. Returns string or nil.
    def self.input(label, default: nil, placeholder: nil, header: nil)
      return nil unless $stdin.tty?

      if gum_available?
        gum_input(label, default: default, placeholder: placeholder, header: header)
      else
        fallback_input(label, default: default)
      end
    end

    # Filterable list: gum filter → fallback. Returns string or nil.
    def self.filter(items, prompt: '> ', header: nil, allow_custom: false)
      return nil unless $stdin.tty?

      if gum_available?
        gum_filter(items, prompt: prompt, header: header, no_strict: allow_custom)
      else
        fallback_input(prompt, default: items.first)
      end
    end

    # Yes/no confirmation: gum confirm → fallback. Returns boolean.
    def self.confirm(message, default: false)
      return default unless $stdin.tty?

      if gum_available?
        gum_confirm(message, default: default)
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

    # Generate sorted, filtered fzf-formatted lines via TaskRenderer.
    def self.task_list_string(store, source: :active, filter_cat: nil, filter_tag: nil)
      include_done = source != :active
      tasks = store.all_tasks(include_done: include_done)
      tasks = tasks.select { |t| t['status'] == 'done' } if source == :done
      tasks = tasks.select { |t| t['category'] == filter_cat } if filter_cat
      tasks = tasks.select { |t| t['tags']&.include?(filter_tag) } if filter_tag
      tasks = tasks.sort_by { |t| TaskRenderer.task_sort_key(t) }

      config = store.load_config
      tasks.map { |t| TaskRenderer.render_fzf(t, config: config) }.join("\n")
    end

    # Flip checkboxes for toggled IDs.
    def self.build_toggled_display(original_lines, toggled)
      original_lines.each_line.map do |line|
        stripped = line.chomp
        task_id = extract_task_id(stripped)
        if task_id && toggled.include?(task_id)
          # Swap [ ] <-> [x] at the known position (chars 2-4)
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

    # Base fzf args shared by all fzf invocations. Extracted for testability --
    # integration tests use these same args with --filter to validate that
    # search works with the exact flags we use in production.
    # --tabstop=9999 pushes the hidden full-description (after TAB) off-screen
    # while keeping it searchable.
    def self.fzf_base_args
      ['fzf', '--exact', '--no-sort', '--tabstop=9999']
    end

    def self.fzf_available?
      @fzf_available = system('command -v fzf > /dev/null 2>&1') if @fzf_available.nil?
      @fzf_available
    end

    def self.gum_available?
      @gum_available = system('command -v gum > /dev/null 2>&1') if @gum_available.nil?
      @gum_available
    end

    def self.reset_cache!
      @fzf_available = nil
      @gum_available = nil
    end

    # ── Private helpers ──────────────────────────────────────────────

    def self.todo_bin_path(store)
      ENV['TODO_CONF_DIR'] ||= store.conf_dir
      File.expand_path('../../todo', __dir__)
    end

    # Extract task ID from a render_fzf formatted line.
    # Format: "  [ ] ID  [pri]  desc...\tfull_desc"
    # The ID is the first number after the checkbox.
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

    def self.gum_input(label, default: nil, placeholder: nil, header: nil)
      header ||= label
      placeholder ||= default ? "Current: #{default}" : 'Enter to skip'

      args = [
        'gum', 'input',
        '--prompt', "  #{label} > ",
        '--placeholder', placeholder,
        '--header', "  #{header}",
        '--header.foreground', '248',
        '--prompt.foreground', '108',
        '--placeholder.foreground', '245',
        '--cursor.foreground', '108',
        '--width', '60'
      ]
      args.push('--value', default) if default

      selected, status = Open3.capture2(*args)
      return nil unless status.success?

      value = selected.chomp
      value.empty? ? nil : value
    end

    def self.gum_filter(items, prompt: '> ', header: '', no_strict: false)
      args = [
        'gum', 'filter',
        '--prompt', "  #{prompt}",
        '--header', "  #{header}",
        '--header.foreground', '248',
        '--prompt.foreground', '108',
        '--indicator.foreground', '108',
        '--match.foreground', '108',
        '--placeholder.foreground', '245',
        '--height', '8'
      ]
      args.push('--no-strict') if no_strict

      input = items.join("\n")
      selected, status = Open3.capture2(*args, stdin_data: input)
      return nil unless status.success?

      value = selected.chomp
      value.empty? ? nil : value
    end

    def self.gum_confirm(message, default: false)
      args = ['gum', 'confirm', message]
      args.push('--default=false') unless default

      _, status = Open3.capture2(*args)
      status.success?
    end

    private_class_method :todo_bin_path, :find_cursor_pos, :gum_input, :gum_filter, :gum_confirm
  end
end
