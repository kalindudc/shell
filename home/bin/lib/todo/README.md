# todo - CLI Task Tracker

A modular Ruby CLI tool for managing tasks with categories, priorities, tags, and search.

## Usage

```
todo add "Fix login bug" -c work -p 0 -t urgent
todo list
todo done 1
todo history
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
    completions.rb        # Zsh completion script generator
    commands/
      init.rb             # Initialize configuration
      add.rb              # Add tasks
      list.rb             # List tasks with filters
      done.rb             # Mark tasks complete
      edit.rb             # Edit task fields
      delete.rb           # Delete tasks
      search.rb           # Search across tasks
      category.rb         # Manage categories
      history.rb          # Browse completed tasks
      show.rb             # View task details
```

### Module responsibilities

- **Store** (`Todo::Store`) - The only code that touches the filesystem. Handles category directories, task CRUD, auto-discovery of external JSON files, ID generation, and config loading.
- **Formatter** (`Todo::Formatter`) - The only code that outputs ANSI colors. Handles task line formatting, headers, footers, truncation, and `NO_COLOR` compliance.
- **Commands** (`Todo::Commands::*`) - Each command is a module with `run(args, store:, fmt:)` and `help(fmt)` methods. Commands parse their own arguments, call Store for data, and Formatter for output.
- **CLI** (`Todo::CLI`) - Dispatch table mapping command names and aliases to modules. Resolves commands and routes to the correct module.
- **Completions** (`Todo::Completions::Zsh`) - Generates the `_todo` zsh completion script from structured `COMPLETIONS` metadata declared in each command module.

### Adding a new command

1. Create `home/bin/lib/todo/commands/mycommand.rb`:

```ruby
module Todo
  module Commands
    module MyCommand
      COMPLETIONS = {
        description: 'Do something',
        positional: :text,          # or :task_id, or omit
        options: [
          { long: '--flag', short: '-f', desc: 'A flag', arg: :text }
        ]
      }.freeze

      def self.help(fmt)
        fmt.print_subcmd_help('mycommand', 'todo mycommand [options]', 'Do something',
          [['--flag, -f <value>', 'A flag']])
      end

      def self.run(args, store:, fmt:)
        # Parse args, call store methods, output via fmt
      end
    end
  end
end
```

2. Add to `cli.rb`:

```ruby
require_relative 'commands/mycommand'

COMMANDS = {
  # ...
  'mycommand' => { mod: Commands::MyCommand, aliases: %w[mc] },
}
```

3. Regenerate completions: `task generate:zsh`

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
    test_store.rb              # Store unit tests (direct require, fast)
    test_formatter.rb          # Formatter unit tests (direct require, fast)
    test_commands.rb           # CLI integration tests (in-process, fast)
```

All Ruby tests run in a single process via `bundle exec ruby` with auto-discovery. Total runtime: ~0.1s for 103 tests.
