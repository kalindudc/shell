# frozen_string_literal: true

module Installer
  # Scans the files that back up bb automations in this public repo for things that must stay
  # private. The generic patterns live here; work terms and people's names live only in the
  # private repo's denylist, because the list itself would leak them.
  module LeakCheck
    PUBLIC_PATHS = %w[bb/automations home/bin/disk-audit].freeze
    DENYLIST_FILE = "leak-denylist.txt"
    PATTERNS = {
      "email address" => /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/,
      # /Users/Shared exists on every Mac and names nobody.
      "home directory path" => %r{/(?:Users|home)/(?!Shared\b)[A-Za-z0-9._-]+},
      "bb id" => /\b(?:proj|thr|env|auto|host|run)_[A-Za-z0-9_-]{6,}/,
      "Slack id" => /\b[UWCDG]0[A-Z0-9]{7,}\b/,
      "token" => /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16})/
    }.freeze

    module_function

    def denylist(path)
      return [] unless File.file?(path)

      File.readlines(path, chomp: true, encoding: "UTF-8")
          .map(&:strip)
          .reject { |line| line.empty? || line.start_with?("#") }
          .map { |line| Regexp.new(line, Regexp::IGNORECASE) }
    end

    def scan(text, denylist)
      patterns = PATTERNS.to_a + denylist.map { |pattern| ["denylist #{pattern.inspect}", pattern] }
      text.each_line.with_index(1).flat_map do |line, number|
        patterns.filter_map do |label, pattern|
          match = line[pattern]
          { line: number, label: label, match: match } if match
        end
      end
    end

    def check_paths(paths, root:, denylist:)
      paths.flat_map { |path| files_under(File.join(root, path)) }.flat_map do |file|
        scan(File.read(file, encoding: "UTF-8"), denylist).map { |finding| finding.merge(file: file.delete_prefix("#{root}/")) }
      end
    end

    def files_under(path)
      return [path] if File.file?(path)
      return [] unless File.directory?(path)

      Dir.glob("**/*", File::FNM_DOTMATCH, base: path).map { |child| File.join(path, child) }.select { |file| File.file?(file) }.sort
    end

    def describe(findings)
      findings.map { |finding| "#{finding[:file]}:#{finding[:line]}: #{finding[:label]} (#{finding[:match]})" }.join("\n")
    end
  end
end
