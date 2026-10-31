#!/usr/bin/env ruby
# frozen_string_literal: true

# Lists the specialist reviewers that apply to a PR, read from the specialist sources in
# a config file, so pr-reviewer can apply their domain checks.
#
#   git diff --name-only <base>...<ref> | ruby --disable-gems specialists.rb --repo owner/name \
#     [--meta pr-title-and-body.txt] [--ref refs/pr-review/12-abc] [--config sources.json]
#
# The config is --config, else $PR_REVIEWER_SPECIALISTS, else
# ~/.config/pr-reviewer/specialists.json:
#
#   {"sources": [{
#     "name": "team-reviewers",              label for the output
#     "checkouts": ["~/src/reviewers"],      globs of local git checkouts; the first one
#                                            holding the registry (or discover dir) at ref wins
#     "ref": "origin/main",                  default HEAD
#     "registry": "review/specialists.yaml", YAML file in that checkout (optional)
#     "candidates": "specialists",           dotted key of the candidate list, default "candidates"
#     "skill_root": "review",                prefix for each candidate's skill.path, default ""
#     "discover": {"dir": "review/skills", "match": {"targets": "actor"}},
#                                            skill folders judged on their SKILL.md frontmatter
#                                            description; "match" filters on frontmatter values
#     "exemptions": "review/EXEMPTIONS.md"   practices the critics must not flag (optional)
#   }]}
#
# A registry candidate looks like:
#
#   - id: ci-pinning
#     skill_name: ci-pinning
#     skill: {path: skills/ci-pinning/SKILL.md}
#     selector:
#       type: glob                           glob runs when the filters pass; llm means judge
#       filters: {repo: owner/name, file_patterns: [".github/workflows/*.yml"],
#                 regexes: ["\\bmcp\\b"], regex_file_size_limit: 2097152}
#     description: ..., when_to_run: ..., skip_critics: false
#
# Every filter that is set must pass. Globs use globstar rules: `*` stays in one path
# segment, `**` spans segments, a trailing `**` means everything below, hidden names match
# only a pattern that spells the dot, and `!(a|b)` excludes names. Regexes are one
# case-insensitive alternation over --meta, then the changed files' contents at --ref;
# without either, a regex filter fails closed.
#
# Prints JSON lines: one per source (its checkout and commit, or an error), then one per
# specialist with select "run" (filters passed) or "judge" (decide from its description
# and when_to_run).

require "json"
require "open3"
require "optparse"
require "yaml"

DEFAULT_SIZE_LIMIT = 2 * 1024 * 1024
# PR text and file names are UTF-8 whatever the shell's locale says.
Encoding.default_external = Encoding::UTF_8

opts = {}
OptionParser.new do |o|
  o.on("--repo REPO") { |v| opts[:repo] = v }
  o.on("--meta FILE") { |v| opts[:meta] = File.read(v).scrub }
  o.on("--ref REF") { |v| opts[:ref] = v }
  o.on("--config FILE") { |v| opts[:config] = v }
end.parse!
abort("--repo is required") unless opts[:repo]
changed = $stdin.read.scrub.split("\n").map(&:strip).reject(&:empty?)

config_path = File.expand_path(opts[:config] || ENV["PR_REVIEWER_SPECIALISTS"] || "~/.config/pr-reviewer/specialists.json")
unless File.file?(config_path)
  puts JSON.generate(source: nil, error: "no specialist sources configured at #{config_path}")
  exit 0
end
sources = JSON.parse(File.read(config_path)).fetch("sources")

# One `git cat-file --batch` process per repository, so dozens of reads stay fast.
class Blobs
  def initialize(dir)
    @in, @out, @thread = Open3.popen2("git", "-C", dir, "cat-file", "--batch")
  end

  def read(spec)
    @in.puts(spec)
    @in.flush
    header = @out.gets or return nil
    return nil if header.end_with?("missing\n")
    size = header.split.last.to_i
    body = @out.read(size).force_encoding(Encoding::UTF_8).scrub
    @out.read(1)
    [body, size]
  end
end

def glob_match?(pattern, path)
  pattern = pattern.sub(%r{(\A|/)\*\*\z}, '\1**/*')
  if (m = pattern.match(/!\(([^)]*)\)/))
    return false unless glob_match?(m.pre_match + "*" + m.post_match, path)
    return m[1].split("|").none? { |alt| glob_match?(m.pre_match + alt + m.post_match, path) }
  end
  File.fnmatch?(pattern, path, File::FNM_PATHNAME)
end

def frontmatter(text)
  return {} unless text&.start_with?("---")
  YAML.safe_load(text.split(/^---\s*$/, 3)[1]) || {}
end

content_blobs = opts[:ref] && Blobs.new(Dir.pwd)
regex_hit = lambda do |regexes, limit|
  combined = Regexp.new(regexes.map { |r| "(?:#{r})" }.join("|"), Regexp::IGNORECASE)
  next true if opts[:meta]&.match?(combined)
  next false unless content_blobs
  changed.any? do |path|
    body, size = content_blobs.read("#{opts[:ref]}:#{path}")
    body && size <= limit && body.match?(combined)
  end
end

passes = lambda do |filters|
  return [true, "no filters"] if filters.nil? || filters.empty?
  return [false, nil] if filters["repo"] && filters["repo"].casecmp(opts[:repo]) != 0
  if (patterns = filters["file_patterns"])
    hit = changed.find { |path| patterns.any? { |p| glob_match?(p, path) } }
    return [false, nil] unless hit
  end
  if (regexes = filters["regexes"])
    return [false, nil] unless regex_hit.call(regexes, filters["regex_file_size_limit"] || DEFAULT_SIZE_LIMIT)
  end
  [true, [hit && "file #{hit}", regexes && "regex"].compact.join(", ")]
rescue RegexpError => e
  [true, "regex not checked (#{e.message}); decide by hand"]
end

sources.each do |source|
  name = source.fetch("name")
  ref = source["ref"] || "HEAD"
  probe = source["registry"] || source.dig("discover", "dir")
  dirs = Array(source["checkouts"]).flat_map { |glob| Dir[File.expand_path(glob)] }
  checkout = probe && dirs.find do |dir|
    system("git", "-C", dir, "cat-file", "-e", "#{ref}:#{probe}", out: File::NULL, err: File::NULL)
  end
  unless checkout
    puts JSON.generate(source: name, error: "no checkout in #{source["checkouts"].inspect} has #{probe.inspect} at #{ref}")
    next
  end
  blobs = Blobs.new(checkout)
  commit, date = Open3.capture2("git", "-C", checkout, "log", "-1", "--format=%h %cs", ref).first.split
  exemptions = source["exemptions"] if source["exemptions"] && blobs.read("#{commit}:#{source["exemptions"]}")
  puts JSON.generate(source: name, checkout:, ref:, commit:, committed: date, exemptions:)

  configured = []
  if source["registry"]
    registry = YAML.safe_load(blobs.read("#{commit}:#{source["registry"]}").first, aliases: true)
    candidates = (source["candidates"] || "candidates").split(".").reduce(registry) { |node, key| node.is_a?(Hash) ? node[key] : nil }
    Array(candidates).each do |c|
      next unless c["skill"] && c.dig("skill", "path")
      configured << (c["skill_name"] || File.basename(File.dirname(c.dig("skill", "path"))))
      selector = c["selector"] || {}
      ok, why = passes.call(selector["filters"])
      next unless ok
      puts JSON.generate(
        source: name,
        select: selector["type"] == "llm" ? "judge" : "run",
        id: c["id"],
        skill: [source["skill_root"], c.dig("skill", "path")].compact.reject(&:empty?).join("/"),
        why:,
        skip_critics: c["skip_critics"] == true,
        description: c["description"],
        when_to_run: c["when_to_run"],
      )
    end
  end

  next unless (dir = source.dig("discover", "dir"))
  match = source.dig("discover", "match") || {}
  names, = Open3.capture2("git", "-C", checkout, "ls-tree", "--name-only", "#{commit}:#{dir}")
  names.split("\n").each do |skill|
    next if configured.include?(skill)
    text, = blobs.read("#{commit}:#{dir}/#{skill}/SKILL.md")
    meta = frontmatter(text)
    next if meta.empty? || match.any? { |key, value| meta[key] != value }
    puts JSON.generate(
      source: name,
      select: "judge",
      id: skill,
      skill: "#{dir}/#{skill}/SKILL.md",
      why: "discovered",
      skip_critics: false,
      description: meta["description"],
      when_to_run: meta["when_to_run"],
    )
  end
end
