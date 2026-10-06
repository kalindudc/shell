#!/usr/bin/env ruby
# frozen_string_literal: true

# One-time migration from folded stow trees to real directories in $HOME.
#
# Before markers existed, stow replaced ~/.pi, ~/.agents and
# ~/.config/zsh with single symlinks into this repo, so every file tools wrote
# there landed in the repo. This script turns those symlinks into real
# directories, moves the gitignored runtime files out of the repo into them,
# and restows so only tracked files are linked. See docs/architecture.md.
#
#   ruby src/scripts/unfold-home.rb            # dry run: print the plan, change nothing
#   ruby src/scripts/unfold-home.rb --apply    # migrate (close every pi session first)
#   ruby src/scripts/unfold-home.rb --revert   # undo a migration using the saved manifest

require_relative "../install/utils"
require_relative "../install/unfold"
require_relative "../install/post_setup"

mode = ARGV.first || "--dry-run"
unless %w[--dry-run --apply --revert].include?(mode)
  warn "Usage: #{$PROGRAM_NAME} [--dry-run|--apply|--revert]"
  exit 2
end

repo_dir = File.expand_path("../..", __dir__)
migration = Installer::Unfold::Migration.new(repo_dir: repo_dir, home: ENV.fetch("HOME"))

begin
  case mode
  when "--dry-run"
    result = migration.dry_run
    exit(result.errors.empty? ? 0 : 1)
  when "--apply"
    migration.apply!(stow: -> { Installer::PostSetup.stow_dotfiles! })
  when "--revert"
    migration.revert!
  end
rescue Installer::Error => e
  warn "Error: #{e.message}"
  exit 1
end
