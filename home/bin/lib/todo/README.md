# todo - CLI Task Tracker

A modular Ruby CLI tool for managing tasks with categories, priorities, tags, and search.

## Usage

```
todo add "Fix login bug" -c work -p 0 -t urgent
todo list
todo mark 1
todo list --done-only
todo show 1
```

Run `todo --help` for full usage, or `todo <command> -h` for command-specific options.

## Architecture

```
home/bin/
  todo                    # Entrypoint (8 lines)
  lib/todo/
    cli.rb                # Dispatch table + main help
    store.rb              # Store class - all filesystem/JSON operations
    formatter.rb          # Formatter module - colors, output formatting
    task_renderer.rb      # TaskRenderer - single source of truth for task line formatting
    interactive.rb        # Interactive module - unified fzf/gum/stdin interaction
    arg_parser.rb         # ArgParser - declarative argument parser
    completions.rb        # Zsh completion script generator
    commands/
      init.rb             # Initialize configuration
      add.rb              # Add tasks
      list.rb             # List tasks with filters (also: --done-only replaces history)
      mark.rb             # Toggle task status (done/pending)
      edit.rb             # Edit task fields
      delete.rb           # Delete tasks (with confirmation)
      search.rb           # Search across tasks
      category.rb         # Manage categories
      show.rb             # View task details
```

### Module responsibilities

- **Store** (`Todo::Store`) - The only code that touches the filesystem. Handles category directories, task CRUD, auto-discovery of external JSON files, ID generation, and config loading.
- **Formatter** (`Todo::Formatter`) - Color helpers and ANSI output utilities. `NO_COLOR` compliant.
- **TaskRenderer** (`Todo::TaskRenderer`) - Single source of truth for task line formatting. Used by list (terminal), list --plain (scripts), and mark (fzf input).
- **Interactive** (`Todo::Interactive`) - Unified interactive layer replacing the old Picker + Prompt modules. Provides fzf-based selection/toggle/search, gum-based text input/filter, and bare stdin fallbacks.
- **ArgParser** (`Todo::ArgParser`) - Declarative argument parser. Each command defines a `DEFINITION` hash; ArgParser handles parsing, validation, and help detection.
- **Commands** (`Todo::Commands::*`) - Each command is a module with `DEFINITION`, `run(args, store:, fmt:)`, and `help(fmt)`. Commands parse their own arguments, call Store for data, and TaskRenderer/Formatter for output.
- **CLI** (`Todo::CLI`) - Dispatch table derived from each command's `DEFINITION`. Resolves commands and aliases, routes to the correct module.
- **Completions** (`Todo::Completions::Zsh`) - Generates the `_todo` zsh completion script from `DEFINITION` metadata declared in each command module.

### Adding a new command

1. Create `home/bin/lib/todo/commands/mycommand.rb`:

```ruby
module Todo
  module Commands
    module MyCommand
      DEFINITION = {
        name: 'mycommand', aliases: %w[mc],
        description: 'Do something',
        positional: { name: :text, type: :text },
        options: [
          { long: '--flag', short: '-f', arg: :text }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('mycommand', 'todo mycommand [options]', 'Do something',
          [['--flag, -f <value>', 'A flag']])
      end

      def self.run(args, store:, fmt:)
        # Parse args, call store methods, output via TaskRenderer
      end
    end
  end
end
```

2. Add to `cli.rb` COMMAND_MODULES array and regenerate completions: `task generate:zsh`

### Interactive tool dependencies

- **fzf** (optional) - Used for task selection, multi-toggle, and fuzzy search
- **gum** (optional) - Used for text input and filterable lists
- Both degrade gracefully to bare stdin prompts when unavailable

### Storage layout

Tasks are stored as JSON in a directory-per-category structure:

```
~/conf/todo/
  .meta.json                 # Global ID counter
  config.json                # Display settings (desc_max, etc.)
  general/
    .category.json           # Category metadata
    todos.json               # Active + completed tasks
  work/
    .category.json
    todos.json
    backlog.json             # Auto-discovered external file
```

Any `.json` file in a category directory (except `.category.json`) is auto-discovered and its tasks appear in listings. The tool only writes to `todos.json` -- external files are read-only.

Note: The `category` field is not stored in task JSON -- it is derived from the directory name at read time.

## Development

```
task up              # Install dev dependencies (bundle install)
task test:bin        # Run all tests (BATS + Ruby)
task style           # ShellCheck + RuboCop with auto-correct
task generate:zsh    # Regenerate .zshrc + completions
```

### Tests

```
home/bin/test/
  bats/
    test_cli_common.bats      # Bash shared library tests
  todo/
    test_store.rb              # Store unit tests
    test_formatter.rb          # Formatter unit tests
    test_task_renderer.rb      # TaskRenderer unit tests
    test_arg_parser.rb         # ArgParser unit tests
    test_interactive.rb        # Interactive module tests
    test_completions.rb        # Completions generation tests
    test_commands.rb           # CLI integration tests (in-process)
```

All Ruby tests run in a single process via `bundle exec ruby` with auto-discovery.
