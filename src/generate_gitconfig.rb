#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "install/utils"
require_relative "install/post_setup"

Installer::PostSetup.load_env_file
Installer::PostSetup.load_git_config_fallbacks
Installer::PostSetup.setup_gpg_key
Installer::PostSetup.generate_git_config
