# frozen_string_literal: true

module Installer
  class Error < StandardError; end
  class CommandFailed < Error; end
  class RebootRequired < Error; end
end
