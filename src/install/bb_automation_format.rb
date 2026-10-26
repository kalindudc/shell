# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "errors"

module Installer
  # Converts between a bb automation record and its folder in a repo: automation.yml with the
  # fields that carry over to another machine, plus prompt.md or the script. Ids, run history and
  # stored paths are dropped; projects are named and paths start at ~.
  module BbAutomationFormat
    class Unportable < Installer::Error; end

    Entry = Struct.new(:slug, :config, :body_file, :body, :dir, keyword_init: true)

    CONFIG_FILE = "automation.yml"
    PROMPT_FILE = "prompt.md"
    HEADER = "# bb automation, saved by `task bb:automations:export` and restored by `task bb:automations`.\n"
    RECORD_KEYS = %w[id projectId name enabled trigger execution origin createdByThreadId nextRunAt lastRunAt runCount
                     lastRunStatus lastRunThreadId lastError createdAt updatedAt].freeze
    AGENT_KEYS = %w[mode prompt providerId model reasoningLevel serviceTier permissionMode environment targetThreadId].freeze
    SCRIPT_KEYS = %w[mode script scriptFile interpreter timeoutMs env workingDirectory storedScriptPath resolvedWorkingDirectory].freeze
    CONFIG_KEYS = {
      nil => %w[name project enabled schedule agent script],
      "schedule" => %w[cron timezone],
      "agent" => %w[provider model reasoning service_tier permission_mode environment new_environment base_branch],
      "script" => %w[file interpreter timeout_ms working_directory env]
    }.freeze
    INLINE_EXTENSIONS = { "bash" => ".sh", "sh" => ".sh", "node" => ".js", "python3" => ".py" }.freeze

    module_function

    def normalize(record, projects:, environment_path:, script_body:)
      name = record.fetch("name")
      raise Unportable, "#{name}: bb reports a damaged record (#{record["problem"]})" if record.key?("problem")

      strict!(record, RECORD_KEYS, name)
      trigger = record.fetch("trigger")
      raise Unportable, "#{name}: only recurring automations are saved, this one runs once" unless trigger["triggerType"] == "schedule"

      execution = record.fetch("execution")
      config = {
        "name" => name,
        "project" => projects.fetch(record.fetch("projectId")),
        "enabled" => record.fetch("enabled"),
        "schedule" => { "cron" => trigger.fetch("cron"), "timezone" => trigger.fetch("timezone") }
      }
      if execution.fetch("mode") == "agent"
        agent_entry(config, execution, environment_path)
      else
        script_entry(config, execution, script_body)
      end
    end

    def agent_entry(config, execution, environment_path)
      strict!(execution, AGENT_KEYS, config["name"])
      raise Unportable, "#{config["name"]}: it re-prompts one thread, which exists only on this machine" if execution["targetThreadId"]

      agent = {
        "provider" => execution.fetch("providerId"),
        "model" => execution.fetch("model"),
        "reasoning" => execution.fetch("reasoningLevel"),
        "service_tier" => execution["serviceTier"],
        "permission_mode" => execution.fetch("permissionMode")
      }.compact.merge(environment(execution.fetch("environment"), environment_path, config["name"]))
      body = execution.fetch("prompt")
      Entry.new(slug: slug(config["name"]), config: config.merge("agent" => agent), body_file: PROMPT_FILE, body: body)
    end

    def script_entry(config, execution, script_body)
      strict!(execution, SCRIPT_KEYS, config["name"])
      script = {
        "file" => execution["scriptFile"],
        "interpreter" => execution["interpreter"],
        "timeout_ms" => execution.fetch("timeoutMs"),
        "working_directory" => working_directory(execution.fetch("workingDirectory")),
        "env" => execution["env"]
      }.compact
      body = execution["script"] || script_body.call(execution.fetch("storedScriptPath"))
      config = config.merge("script" => script)
      Entry.new(slug: slug(config["name"]), config: config, body_file: body_file(config), body: body)
    end

    def environment(value, environment_path, name)
      case value.fetch("type")
      when "project-default" then {}
      when "reuse" then { "environment" => tilde(environment_path.call(value.fetch("environmentId"))) }
      when "host" then workspace(value.fetch("workspace"), name)
      else raise Unportable, "#{name}: unknown environment type #{value["type"]}"
      end
    end

    def workspace(value, name)
      case value.fetch("type")
      when "unmanaged"
        raise Unportable, "#{name}: its workspace has no path or pins a branch" if value["path"].nil? || value["branch"]

        { "environment" => tilde(value["path"]) }
      when "managed-worktree"
        base = value.fetch("baseBranch")
        { "new_environment" => "worktree", "base_branch" => base["kind"] == "named" ? base.fetch("name") : nil }.compact
      else raise Unportable, "#{name}: workspace type #{value["type"]} is not saved"
      end
    end

    def working_directory(value)
      value.fetch("type") == "path" ? tilde(value.fetch("path")) : value.fetch("type")
    end

    def strict!(hash, known, name)
      unknown = hash.keys - known
      return if unknown.empty?

      raise Installer::Error, "#{name}: bb returned fields this backup does not know: #{unknown.join(", ")}; " \
                              "teach src/install/bb_automation_format.rb about them"
    end

    def slug(name)
      name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end

    def tilde(path)
      home = Dir.home
      return "~" if path == home

      path.start_with?("#{home}/") ? "~/#{path.delete_prefix("#{home}/")}" : path
    end

    def body_file(config)
      return PROMPT_FILE if config.key?("agent")

      script = config.fetch("script")
      script["file"] || "script#{INLINE_EXTENSIONS.fetch(script["interpreter"], ".txt")}"
    end

    def render(entry)
      body = entry.body.end_with?("\n") ? entry.body : "#{entry.body}\n"
      { CONFIG_FILE => HEADER + YAML.dump(entry.config).delete_prefix("---\n"), entry.body_file => body }
    end

    def write_entry(dir, entry)
      FileUtils.mkdir_p(dir)
      config_path = File.join(dir, CONFIG_FILE)
      if File.file?(config_path)
        previous = body_file(YAML.safe_load_file(config_path))
        FileUtils.rm_f(File.join(dir, previous)) unless previous == entry.body_file
      end
      render(entry).each { |file, content| File.write(File.join(dir, file), content) }
      File.chmod(0o755, File.join(dir, entry.body_file)) if entry.config.key?("script")
    end

    def load_root(root)
      return [] unless File.directory?(root)

      Dir.children(root).sort.filter_map do |slug|
        dir = File.join(root, slug)
        config_path = File.join(dir, CONFIG_FILE)
        next unless File.file?(config_path)

        config = YAML.safe_load_file(config_path)
        validate!(config, config_path)
        file = body_file(config)
        Entry.new(slug: slug, config: config, body_file: file, body: File.read(File.join(dir, file), encoding: "UTF-8"), dir: dir)
      end
    end

    def validate!(config, path)
      CONFIG_KEYS.each do |section, known|
        values = section ? config[section] : config
        next if values.nil?

        unknown = values.keys - known
        raise Installer::Error, "#{path}: unknown keys #{unknown.join(", ")}" unless unknown.empty?
      end
      modes = %w[agent script].select { |mode| config.key?(mode) }
      raise Installer::Error, "#{path}: needs exactly one of agent or script" unless modes.size == 1
      raise Installer::Error, "#{path}: needs name, project, enabled and schedule" unless %w[name project enabled schedule].all? { config.key?(it) }
    end
  end
end
