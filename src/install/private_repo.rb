# frozen_string_literal: true

module Installer
  # The private companion repo holds what this public repo must not: work-specific bb automations,
  # the helpers they call, overlays such as disk-audit's, and the leak check's denylist.
  module PrivateRepo
    DEFAULT_DIR = File.join(Dir.home, "src/github.com/kalindudc/shell-private")
    REMOTE = "https://github.com/kalindudc/shell-private.git"

    module_function

    def dir
      ENV.fetch("SHELL_PRIVATE_DIR", DEFAULT_DIR)
    end

    def present?
      File.directory?(dir)
    end
  end
end
