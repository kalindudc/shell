# frozen_string_literal: true

require "fileutils"
require "json"

module Installer
  class State
    DEFAULT_PATH = File.join(
      ENV.fetch("XDG_STATE_HOME", File.join(ENV.fetch("HOME"), ".local/state")),
      "shell",
      "install.json"
    )

    def initialize(path = DEFAULT_PATH)
      @path = path
      @data = load_data
    end

    attr_reader :path

    def data
      @data
    end

    def mark_phase_complete(name)
      data["phases"][name.to_s] = true
      save!
    end

    def phase_complete?(name)
      data.fetch("phases", {}).fetch(name.to_s, false)
    end

    def require_reboot(reason)
      reasons = data["reboot_required"]
      reasons << reason unless reasons.include?(reason)
      save!
    end

    def reboot_required?
      !data.fetch("reboot_required", []).empty?
    end

    def clear_reboot!
      data["reboot_required"] = []
      save!
    end

    private

    def load_data
      raw = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      {
        "phases" => raw.fetch("phases", {}),
        "reboot_required" => raw.fetch("reboot_required", [])
      }
    rescue JSON::ParserError
      { "phases" => {}, "reboot_required" => [] }
    end

    def save!
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(data))
    end
  end
end
