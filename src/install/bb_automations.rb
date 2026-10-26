# frozen_string_literal: true

require "json"
require_relative "errors"
require_relative "utils"
require_relative "bb"
require_relative "bb_automation_format"
require_relative "leak_check"
require_relative "private_copies"
require_relative "private_repo"

module Installer
  # Backs up bb automations, which bb keeps in its own database, as folders in two repos. An
  # automation goes to this public repo only if its folder is already tracked here; everything
  # else, including every new automation, goes to the private repo. Restoring creates what is
  # missing and changes an existing automation only when asked; it never deletes one.
  module BbAutomations
    Format = BbAutomationFormat
    PUBLIC_ROOT = File.expand_path("../../bb/automations", __dir__)
    DRIFT_HINT = "save bb's version with `task bb:automations:export`, or make bb match the files with `task bb:automations -- --update`"

    module_function

    def private_root(dir = PrivateRepo.dir)
      File.join(dir, "bb", "automations")
    end

    def export_targets(entries, public_root:, private_root:, denylist:)
      shared = entries.group_by(&:slug).select { |_, group| group.size > 1 }.keys
      raise Installer::Error, "automations share the folder name #{shared.join(", ")}; rename one in bb" unless shared.empty?

      targets = entries.map do |entry|
        public_dir = File.join(public_root, entry.slug)
        private_dir = File.join(private_root, entry.slug)
        tracked = File.file?(File.join(public_dir, Format::CONFIG_FILE))
        raise Installer::Error, "#{entry.slug} is saved in both #{public_root} and #{private_root}; keep one" if tracked && File.exist?(private_dir)

        [tracked ? public_dir : private_dir, entry, tracked]
      end
      leaks = targets.select(&:last).flat_map { |_, entry, _| leaks_in(entry, denylist) }
      unless leaks.empty?
        raise Installer::Error, "refusing to write public automations that would leak:\n#{LeakCheck.describe(leaks)}\n" \
                                "Remove the detail in bb, or move the folder to #{private_root}"
      end

      targets.map { |dir, entry, _| [dir, entry] }
    end

    def leaks_in(entry, denylist)
      Format.render(entry).flat_map do |file, content|
        LeakCheck.scan(content, denylist).map { |finding| finding.merge(file: "#{entry.slug}/#{file}") }
      end
    end

    def plan(desired, live, project_ids:, update:)
      result = { commands: [], drift: [], missing_projects: [] }
      desired.each do |entry|
        project = entry.config.fetch("project")
        project_id = project_ids[project]
        next result[:missing_projects] |= [project] unless project_id

        id, current = live[[project, entry.config.fetch("name")]]
        if current.nil?
          result[:commands] << create_command(entry, project_id)
        elsif !same?(entry, current)
          result[:drift] << entry.slug
          result[:commands].concat(update_commands(entry, current, id, project_id)) if update
        end
      end
      result
    end

    def same?(entry, current)
      entry.config == current.config && entry.body.chomp == current.body.chomp
    end

    def create_command(entry, project_id)
      config = entry.config
      ["bb", "automation", "create", "--project", project_id, "--name", config.fetch("name")] +
        (config.fetch("enabled") ? [] : ["--disabled"]) +
        schedule_args(config) + execution_args(entry)
    end

    def update_commands(entry, current, id, project_id)
      commands = []
      if entry.config.except("enabled") != current.config.except("enabled") || entry.body.chomp != current.body.chomp
        commands << (["bb", "automation", "update", id, "--project", project_id, "--name", entry.config.fetch("name")] +
                     schedule_args(entry.config) + execution_args(entry))
      end
      if entry.config.fetch("enabled") != current.config.fetch("enabled")
        commands << ["bb", "automation", entry.config.fetch("enabled") ? "resume" : "pause", id, "--project", project_id]
      end
      commands
    end

    def schedule_args(config)
      schedule = config.fetch("schedule")
      ["--cron", schedule.fetch("cron"), "--timezone", schedule.fetch("timezone")]
    end

    def execution_args(entry)
      if (agent = entry.config["agent"])
        return agent_args(agent, entry.body)
      end

      script = entry.config.fetch("script")
      body_args = script["file"] ? ["--script-file", File.join(entry.dir, entry.body_file)] : ["--script", entry.body]
      body_args +
        optional("--interpreter", script["interpreter"]) +
        ["--timeout", script.fetch("timeout_ms").to_s] +
        ["--working-directory", expand(script.fetch("working_directory"))] +
        optional("--env-json", script["env"] && JSON.generate(script["env"]))
    end

    def agent_args(agent, prompt)
      ["--prompt", prompt, "--provider", agent.fetch("provider"), "--model", agent.fetch("model"), "--reasoning", agent.fetch("reasoning")] +
        optional("--service-tier", agent["service_tier"]) +
        ["--permission-mode", agent.fetch("permission_mode")] +
        optional("--environment", agent["environment"] && File.expand_path(agent["environment"])) +
        optional("--new-environment", agent["new_environment"]) +
        optional("--base-branch", agent["base_branch"])
    end

    def optional(flag, value)
      value.nil? ? [] : [flag, value]
    end

    def expand(working_directory)
      working_directory.start_with?("~", "/") ? File.expand_path(working_directory) : working_directory
    end

    def bb_ready?
      unless Installer::BbApp.ensure_running!
        Installer::Utils.warn("bb is not installed or did not start; open bb and run the task again")
        return false
      end

      Installer::BbApp.install_cli_command!
      true
    end

    def projects
      Installer::Bb.bb_json("project", "list", "--include-personal")
    end

    # { [project name, automation name] => [automation id, entry] } for every portable automation.
    def live_entries(project_ids, names)
      context = {
        projects: names,
        environment_path: ->(id) { Installer::Bb.bb_json("environment", "show", id).fetch("path") },
        script_body: ->(path) { File.read(path, encoding: "UTF-8") }
      }
      project_ids.each_with_object({}) do |project_id, live|
        Installer::Bb.bb_json("automation", "list", "--project", project_id).each do |record|
          entry = Format.normalize(record, **context)
          key = [entry.config["project"], entry.config["name"]]
          raise Installer::Error, "two automations in #{key[0]} are named #{key[1]}; rename one in bb" if live.key?(key)

          live[key] = [record.fetch("id"), entry]
        rescue Format::Unportable => e
          Installer::Utils.warn("Skipping #{e.message}")
        end
      end
    end

    def export!
      return false unless bb_ready?
      unless PrivateRepo.present?
        raise Installer::Error, "no private repo at #{PrivateRepo.dir}: clone #{PrivateRepo::REMOTE} there or set SHELL_PRIVATE_DIR"
      end

      names = projects.to_h { |project| [project.fetch("id"), project.fetch("name")] }
      entries = live_entries(names.keys, names).values.map(&:last)
      denylist = LeakCheck.denylist(File.join(PrivateRepo.dir, LeakCheck::DENYLIST_FILE))
      targets = export_targets(entries, public_root: PUBLIC_ROOT, private_root: private_root, denylist: denylist)
      targets.each { |dir, entry| Format.write_entry(dir, entry) }

      saved = (Format.load_root(PUBLIC_ROOT) + Format.load_root(private_root)).map(&:dir) - targets.map(&:first)
      saved.each { |dir| Installer::Utils.warn("No longer in bb, left in place: #{dir}") }
      save_copies
      public_count = targets.count { |dir, _| dir.start_with?(PUBLIC_ROOT) }
      private_count = targets.size - public_count
      Installer::Utils.success("Saved #{targets.size} automations: #{public_count} in #{PUBLIC_ROOT}, #{private_count} in #{private_root}")
      true
    end

    def save_copies
      PrivateCopies.load(PrivateRepo.dir).each do |copy|
        PrivateCopies.save!(copy, PrivateRepo.dir).each do |item|
          Installer::Utils.warn("#{File.join(copy["from"], item)} is missing; kept its saved copy")
        end
      end
    end

    def apply!(update: false)
      return false unless bb_ready?

      desired = Format.load_root(PUBLIC_ROOT)
      if PrivateRepo.present?
        desired += Format.load_root(private_root)
      else
        Installer::Utils.warn("No private repo at #{PrivateRepo.dir}: restoring only the public automations")
      end
      repeated = desired.group_by { |entry| entry.config.values_at("project", "name") }.select { |_, group| group.size > 1 }
      raise Installer::Error, "saved more than once: #{repeated.keys.map { |key| key.join(" / ") }.join(", ")}" unless repeated.empty?

      list = projects
      project_ids = list.to_h { |project| [project.fetch("name"), project.fetch("id")] }
      wanted = desired.map { |entry| project_ids[entry.config["project"]] }.compact.uniq
      live = live_entries(wanted, list.to_h { |project| [project.fetch("id"), project.fetch("name")] })
      result = plan(desired, live, project_ids: project_ids, update: update)
      report(result, update)
      result[:commands].each { |command| Installer::Utils.run!(*command) }
      restore_copies if PrivateRepo.present?
      true
    end

    def report(result, update)
      result[:missing_projects].each { |project| Installer::Utils.warn("bb has no project named #{project} here; skipped its automations") }
      Installer::Utils.warn("Differs from bb: #{result[:drift].join(", ")}; #{DRIFT_HINT}") if result[:drift].any? && !update
      if result[:commands].any?
        Installer::Utils.log("Applying #{result[:commands].size} automation changes...")
      elsif result[:drift].empty?
        Installer::Utils.log("bb automations already match the saved ones")
      end
    end

    def restore_copies
      PrivateCopies.load(PrivateRepo.dir).each do |copy|
        PrivateCopies.restore!(copy, PrivateRepo.dir).each { |file| Installer::Utils.log("Restored #{file}") }
      end
    end
  end
end
