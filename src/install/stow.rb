# frozen_string_literal: true

require_relative "errors"
require_relative "unfold"
require_relative "setup"

module Installer
  # Links home/ into $HOME.
  module Stow
    SHELL_DIR = File.expand_path("../..", __dir__)
    HOME = ENV["HOME"]

    module_function

    def run!
      raise Installer::CommandFailed, "stow is required to install dotfiles" unless Installer::Utils.command?("stow")

      Installer::Utils.log("Stowing dotfiles...")
      # Directories marked with .stow-unfold must exist as real directories first,
      # otherwise stow folds them into one symlink and tool files land in the repo.
      Installer::Unfold.prepare_targets!(File.join(SHELL_DIR, "home"), HOME)
      Installer::Setup.ensure_gpg_home_permissions!
      Installer::Utils.run!("stow", "home", "-d", SHELL_DIR, "-t", HOME, "--adopt")
    end
  end
end
