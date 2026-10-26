# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "errors"

module Installer
  # Helper files that private automations depend on but that live outside any repo, listed in the
  # private repo's backup.yml. Saving mirrors the listed paths into the private repo; restoring
  # copies back only files that are missing, so it never overwrites local edits.
  module PrivateCopies
    BACKUP_FILE = "backup.yml"
    SKIP = %r{(?:\A|/)(?:__pycache__|\.DS_Store)(?:/|\z)|\.pyc\z}

    module_function

    def load(private_dir)
      path = File.join(private_dir, BACKUP_FILE)
      return [] unless File.file?(path)

      Array(YAML.safe_load_file(path)["copies"]).map do |copy|
        missing = %w[from to include] - copy.keys
        raise Installer::Error, "#{path}: a copy needs from, to and include, missing #{missing.join(", ")}" unless missing.empty?

        copy.merge("from" => File.expand_path(copy.fetch("from")))
      end
    end

    # Returns the listed items missing from the source; their saved copy is kept, not deleted.
    def save!(copy, private_dir)
      destination = File.join(private_dir, copy.fetch("to"))
      missing, present = copy.fetch("include").partition { |item| !File.exist?(File.join(copy.fetch("from"), item)) }
      present.each do |item|
        source = File.join(copy.fetch("from"), item)
        FileUtils.rm_rf(File.join(destination, item))
        files(source).each do |relative|
          target = join(destination, item, relative)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(join(source, relative), target, preserve: true)
        end
      end
      missing
    end

    def restore!(copy, private_dir)
      source = File.join(private_dir, copy.fetch("to"))
      copy.fetch("include").flat_map do |item|
        files(File.join(source, item)).filter_map do |relative|
          target = join(copy.fetch("from"), item, relative)
          next if File.exist?(target)

          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(join(source, item, relative), target, preserve: true)
          target
        end
      end
    end

    def join(*parts)
      File.join(*parts.reject(&:empty?))
    end

    # Paths relative to `path`; a file yields "" so callers can join it unchanged.
    def files(path)
      return [""] if File.file?(path)
      return [] unless File.directory?(path)

      Dir.glob("**/*", File::FNM_DOTMATCH, base: path)
         .grep_v(SKIP)
         .select { |relative| File.file?(File.join(path, relative)) }
         .sort
    end
  end
end
