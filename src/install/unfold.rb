# frozen_string_literal: true

require "fileutils"
require "find"
require "json"
require "open3"
require "time"
require_relative "errors"

module Installer
  # Keeps shared directories in $HOME real instead of letting stow fold them.
  #
  # Stow "folds" a directory that does not exist in $HOME yet into a single
  # symlink pointing into the repo. After that, every file a tool writes there
  # (installed skills, sessions, credentials) lands in the repo and has to be
  # gitignored. A directory in the stow package that contains a `.stow-unfold`
  # marker is created as a real directory in $HOME before stow runs, so stow
  # links its children one by one and anything else in it stays out of the repo.
  module Unfold
    MARKER = ".stow-unfold"
    PRUNE = %w[.git node_modules].freeze

    module_function

    # Paths, relative to package_dir, of directories holding a marker. Parents first.
    def marker_dirs(package_dir)
      found = []
      Find.find(package_dir) do |path|
        name = File.basename(path)
        if PRUNE.include?(name) && File.directory?(path) && !File.symlink?(path)
          Find.prune
        elsif name == MARKER
          found << relative(File.dirname(path), package_dir)
        end
      end
      found.sort_by { |rel| [rel.count("/"), rel] }
    end

    # Creates every marker directory in home so stow descends into it instead of folding it.
    # Raises when a marker directory, or one of its parents, is a symlink: that is a folded
    # tree from before markers existed and needs the one-time migration.
    def prepare_targets!(package_dir, home)
      marker_dirs(package_dir).each do |rel|
        link = symlinked_component(home, rel)
        if link
          raise Installer::Error,
                "#{link} is a symlink, so files tools write there would land in the repo. " \
                "Convert it with: ruby src/scripts/unfold-home.rb (see docs/architecture.md)"
        end

        FileUtils.mkdir_p(File.join(home, rel))
      end
    end

    # First path from home down to rel that is a symlink, or nil.
    def symlinked_component(home, rel)
      parts = rel.split("/")
      (1..parts.size).each do |n|
        path = File.join(home, *parts.first(n))
        return path if File.symlink?(path)
      end
      nil
    end

    def relative(path, base)
      return "" if path == base

      path.delete_prefix("#{base}/")
    end

    AGENT_COMMANDS = %w[pi claude].freeze

    # Uses the full process list: macOS pgrep leaves out the caller's ancestors,
    # so it would miss a pi session that runs this migration from its own shell.
    def default_running_agents
      out, status = Open3.capture2("ps", "-A", "-o", "pid=,comm=")
      raise Installer::Error, "ps failed; cannot check for running agents" unless status.success?

      out.lines.filter_map do |line|
        pid, command = line.strip.split(/\s+/, 2)
        name = File.basename(command.to_s)
        "#{name} (pid #{pid})" if AGENT_COMMANDS.include?(name)
      end
    end

    def default_manifest_path
      state_home = ENV.fetch("XDG_STATE_HOME", File.join(ENV.fetch("HOME"), ".local/state"))
      File.join(state_home, "shell", "unfold-manifest.json")
    end

    # One-time conversion of folded stow trees into real directories.
    #
    # For every marker directory, children tracked in git stay in the repo (stow
    # links them), children that are entirely gitignored move out of the repo into
    # the real directory in home, and anything untracked but not ignored stops the
    # migration so in-progress work is never moved by accident. EVICT lists whole
    # top-level directories the repo should stop owning entirely.
    class Migration
      EVICT = %w[.claude].freeze

      Step = Struct.new(:action, :path, :link_target, keyword_init: true) do
        def to_h = { "action" => action.to_s, "path" => path, "link_target" => link_target }.compact

        def self.from_h(hash) = new(action: hash.fetch("action").to_sym, path: hash.fetch("path"), link_target: hash["link_target"])
      end

      Plan = Struct.new(:steps, :kept, :errors, keyword_init: true)

      attr_reader :repo_dir, :package_dir, :home, :manifest_path

      def initialize(repo_dir:, home:, manifest_path: Unfold.default_manifest_path, evict: EVICT,
                     running_agents: -> { Unfold.default_running_agents }, out: $stdout)
        @repo_dir = repo_dir
        @package_dir = File.join(repo_dir, "home")
        @home = home
        @manifest_path = manifest_path
        @evict = evict
        @running_agents = running_agents
        @out = out
      end

      def plan
        @tracked = git_paths("ls-files")
        @untracked = git_paths("ls-files", "--others", "--exclude-standard")
        markers = Unfold.marker_dirs(package_dir)
        steps = []
        kept = []
        errors = []
        unfolding = []

        markers.each do |rel|
          plan_marker_dir(rel, unfolding, steps, errors)
          next unless File.directory?(File.join(package_dir, rel))

          Dir.children(File.join(package_dir, rel)).sort.each do |name|
            next if name == MARKER

            child = rel.empty? ? name : "#{rel}/#{name}"
            next if markers.include?(child)

            if tracked?(child)
              kept << child
            elsif untracked?(child)
              errors << "#{child} is untracked but not ignored; commit it, gitignore it, or move it before migrating"
            else
              plan_move(child, unfolding, steps, errors)
            end
          end
        end

        @evict.each do |rel|
          next unless File.exist?(File.join(package_dir, rel))

          if tracked?(rel) || untracked?(rel)
            errors << "#{rel} still has files that are not ignored; it cannot be evicted"
          else
            plan_move(rel, unfolding, steps, errors)
          end
        end

        errors << "#{package_dir} and #{home} are on different filesystems; moves would copy data" unless same_device?
        Plan.new(steps: steps, kept: kept, errors: errors)
      end

      def dry_run
        result = plan
        print_plan(result)
        agents = @running_agents.call
        @out.puts "\nRunning agents that must be closed before --apply: #{agents.join(', ')}" unless agents.empty?
        result
      end

      def apply!(stow:)
        raise Installer::Error, "A previous migration manifest exists at #{manifest_path}; revert or remove it first" if File.exist?(manifest_path)

        agents = @running_agents.call
        raise Installer::Error, "Close these first, they write into the directories being moved: #{agents.join(', ')}" unless agents.empty?

        result = plan
        unless result.errors.empty?
          print_plan(result)
          raise Installer::Error, "Migration blocked by #{result.errors.size} problem(s); nothing was changed"
        end

        manifest = { "version" => 1, "repo_dir" => repo_dir, "home" => home, "created_at" => Time.now.utc.iso8601,
                     "steps" => result.steps.map(&:to_h), "completed" => 0 }
        write_manifest(manifest)
        result.steps.each_with_index do |step, index|
          execute(step)
          manifest["completed"] = index + 1
          write_manifest(manifest)
        end

        stow.call
        verify!(result)
        @out.puts "Migrated: #{result.steps.count { |s| s.action == :move }} item(s) moved out of the repo; manifest at #{manifest_path}"
        result
      end

      def revert!
        raise Installer::Error, "No migration manifest at #{manifest_path}" unless File.exist?(manifest_path)

        agents = @running_agents.call
        raise Installer::Error, "Close these first: #{agents.join(', ')}" unless agents.empty?

        manifest = JSON.parse(File.read(manifest_path))
        steps = manifest.fetch("steps").first(manifest.fetch("completed")).map { |h| Step.from_h(h) }
        steps.reverse_each { |step| undo(step) }
        File.delete(manifest_path)
        @out.puts "Reverted #{steps.size} step(s). Run `task stow` to restore any links stow manages outside these directories."
      end

      private

      # Markers arrive parents first, so a folded parent is already in `unfolding`.
      def plan_marker_dir(rel, unfolding, steps, errors)
        return if rel.empty?

        target = File.join(home, rel)
        parent_link = Unfold.symlinked_component(home, File.dirname(rel) == "." ? "" : File.dirname(rel))
        if parent_link && unfolding.none? { |u| File.join(home, u) == parent_link }
          errors << "#{parent_link} is a folded symlink but has no #{MARKER} marker; add one so it can be unfolded"
        elsif File.symlink?(target)
          if same_path?(target, File.join(package_dir, rel))
            steps << Step.new(action: :unfold, path: rel, link_target: File.readlink(target))
            unfolding << rel
          else
            errors << "#{target} is a symlink that does not point at #{File.join(package_dir, rel)}"
          end
        elsif parent_link || !File.exist?(target)
          steps << Step.new(action: :mkdir, path: rel)
        elsif !File.directory?(target)
          errors << "#{target} exists but is not a directory"
        end
      end

      def plan_move(rel, unfolding, steps, errors)
        src = File.join(package_dir, rel)
        dest = File.join(home, rel)
        under_unfold = unfolding.any? { |u| rel.start_with?("#{u}/") }

        if !under_unfold && File.symlink?(dest)
          unless same_path?(dest, src)
            errors << "#{dest} is a symlink that does not point at #{src}"
            return
          end
          steps << Step.new(action: :unlink, path: rel, link_target: File.readlink(dest))
        elsif !under_unfold && File.exist?(dest)
          errors << "#{rel} exists both in the repo and at #{dest}; resolve it by hand"
          return
        end

        escaping = escaping_symlinks(src)
        errors.concat(escaping.map { |link| "#{link} is a relative symlink that would break when moved" })
        steps << Step.new(action: :move, path: rel)
      end

      def execute(step)
        target = File.join(home, step.path)
        case step.action
        when :unfold
          raise Installer::Error, "#{target} is no longer a symlink" unless File.symlink?(target)

          File.unlink(target)
          Dir.mkdir(target)
        when :mkdir
          Dir.mkdir(target)
        when :unlink
          raise Installer::Error, "#{target} is no longer a symlink" unless File.symlink?(target)

          File.unlink(target)
        when :move
          raise Installer::Error, "#{target} already exists" if File.exist?(target) || File.symlink?(target)

          File.rename(File.join(package_dir, step.path), target)
        end
        @out.puts "  #{step.action} #{step.path}"
      end

      def undo(step)
        target = File.join(home, step.path)
        case step.action
        when :unfold
          remove_package_links(target)
          Dir.rmdir(target)
          File.symlink(step.link_target, target)
        when :mkdir
          remove_package_links(target)
          Dir.rmdir(target)
        when :unlink
          File.symlink(step.link_target, target)
        when :move
          src = File.join(package_dir, step.path)
          raise Installer::Error, "#{src} already exists; cannot move #{target} back" if File.exist?(src) || File.symlink?(src)

          File.rename(target, src)
        end
        @out.puts "  undo #{step.action} #{step.path}"
      rescue Errno::ENOTEMPTY
        raise Installer::Error, "#{target} has new entries (#{Dir.children(target).join(', ')}); move them back by hand and rerun --revert"
      end

      # Stow links inside a directory that point into the package; created by stow after unfolding.
      def remove_package_links(dir)
        return unless File.directory?(dir)

        Dir.children(dir).each do |name|
          path = File.join(dir, name)
          next unless File.symlink?(path)

          resolved = File.expand_path(File.readlink(path), dir)
          File.unlink(path) if resolved.start_with?("#{File.realpath(package_dir)}/") || resolved.start_with?("#{package_dir}/")
        end
      end

      def verify!(result)
        problems = []
        Unfold.marker_dirs(package_dir).each do |rel|
          target = File.join(home, rel)
          problems << "#{target} is not a real directory" if File.symlink?(target) || !File.directory?(target)
        end
        result.kept.each do |rel|
          path = File.join(home, rel)
          next if File.symlink?(path) && same_path?(path, File.join(package_dir, rel))
          # A tracked directory that already existed for real in home (like ~/.config/nvim): stow links inside it.
          next if File.directory?(path) && !File.symlink?(path) && File.directory?(File.join(package_dir, rel))

          problems << "#{path} is not linked into the repo"
        end
        result.steps.select { |s| s.action == :move }.each do |step|
          dest = File.join(home, step.path)
          problems << "#{step.path} did not arrive in #{home}" unless File.exist?(dest) || File.symlink?(dest)
        end
        raise Installer::Error, "Migration finished with problems:\n  #{problems.join("\n  ")}" unless problems.empty?
      end

      def print_plan(result)
        @out.puts "Unfold plan for #{home} (repo #{repo_dir})"
        result.steps.each { |s| @out.puts "  #{s.action.to_s.ljust(6)} #{s.path}" }
        @out.puts "  (#{result.kept.size} tracked item(s) stay in the repo and are linked by stow)"
        return if result.errors.empty?

        @out.puts "Problems:"
        result.errors.each { |e| @out.puts "  - #{e}" }
      end

      def write_manifest(manifest)
        FileUtils.mkdir_p(File.dirname(manifest_path))
        tmp = "#{manifest_path}.tmp"
        File.write(tmp, JSON.pretty_generate(manifest))
        File.rename(tmp, manifest_path)
      end

      def git_paths(*args)
        out, status = Open3.capture2("git", "-C", repo_dir, *args, "-z", "--", "home")
        raise Installer::Error, "git #{args.join(' ')} failed in #{repo_dir}" unless status.success?

        out.split("\0").map { |p| p.delete_prefix("home/").delete_suffix("/") }.reject { |p| File.basename(p) == MARKER }
      end

      def tracked?(rel) = @tracked.any? { |p| p == rel || p.start_with?("#{rel}/") }

      def untracked?(rel) = @untracked.any? { |p| p == rel || p.start_with?("#{rel}/") }

      def same_path?(link, expected)
        File.exist?(link) && File.exist?(expected) && File.realpath(link) == File.realpath(expected)
      end

      def same_device?
        File.stat(package_dir).dev == File.stat(home).dev
      end

      # Relative symlinks under root whose target resolves outside root.
      def escaping_symlinks(root)
        if File.symlink?(root)
          return File.readlink(root).start_with?("/") ? [] : [root]
        end
        return [] unless File.directory?(root)

        out, = Open3.capture2("find", root, "-type", "l")
        out.split("\n").reject do |link|
          target = File.readlink(link)
          resolved = File.expand_path(target, File.dirname(link))
          target.start_with?("/") || resolved == root || resolved.start_with?("#{root}/")
        end
      end
    end
  end
end
