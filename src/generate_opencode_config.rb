#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Generates ~/.config/opencode/opencode.json from src/templates/opencode.json.erb.
#
# When the output file already exists the generated config is DEEP-MERGED into it:
#   - Template values win on scalar conflicts  (propagates corrections/additions)
#   - User-only keys at any depth are preserved (e.g. "_launch": true on models)
#   - Arrays are unioned: template entries not already present are appended
#     (e.g. watcher.ignore entries you added manually are kept)
#
# The live file is NEVER touched during --print or --validate runs.
# A .bak copy is written alongside the output before any in-place update.
#
# Profile-driven via env vars:
#   OPENCODE_PROFILE=personal  (default) — Anthropic account, cost-optimised,
#                                          Groq critics when GROQ_API_KEY is set
#   OPENCODE_PROFILE=work
#
# Other env vars (all optional):
#   GROQ_API_KEY     — enables Groq provider block (personal profile only)
#   OLLAMA_HOST      — Ollama base URL, default http://127.0.0.1:11434
#   OLLAMA_MODELS    — space-separated model tags, default "qwen3:8b llama4:scout"
#                      set to "" to omit the ollama provider block entirely
#
# Usage:
#   ruby src/generate_opencode_config.rb [options]
#
# Options:
#   -o, --output=PATH   output path (default: ~/.config/opencode/opencode.json)
#   -i, --input=PATH    template path (default: src/templates/opencode.json.erb)
#       --print         write merged result to STDOUT, do NOT touch any file
#       --debug         verbose logging
#       --validate      validate the merged JSON and exit (non-zero on error)

require 'erb'
require 'json'
require 'fileutils'
require 'optparse'
require 'logger'

DEFAULT_OUTPUT = File.expand_path('~/.config/opencode/opencode.json').freeze
DEFAULT_TEMPLATE = File.expand_path(
  'templates/opencode.json.erb', __dir__
).freeze

# ---------------------------------------------------------------------------
# Deep merge: template wins on scalar conflict, arrays are unioned,
# user-only keys at any nesting depth are preserved.
# ---------------------------------------------------------------------------
def deep_merge(existing, incoming)
  return incoming if existing.nil?
  return existing if incoming.nil?

  # Both are Hashes — recurse key by key
  if existing.is_a?(Hash) && incoming.is_a?(Hash)
    result = existing.dup
    incoming.each do |key, inc_val|
      result[key] = if result.key?(key)
                      deep_merge(result[key], inc_val)
                    else
                      # Key is new in the template — add it
                      inc_val
                    end
    end
    return result
  end

  # Both are Arrays — union (preserve order: existing first, then new)
  return existing + (incoming - existing) if existing.is_a?(Array) && incoming.is_a?(Array)

  # Scalar conflict or type mismatch — template wins
  incoming
end

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
def init
  @options = {
    output: DEFAULT_OUTPUT,
    template: DEFAULT_TEMPLATE,
    debug: false,
    print: false,
    validate: false
  }

  OptionParser.new do |opt|
    opt.banner = 'Usage: generate_opencode_config.rb [options]'
    opt.on('-oPATH', '--output=PATH',
           "Output path (default: #{DEFAULT_OUTPUT})") { |v| @options[:output] = v }
    opt.on('-iPATH', '--input=PATH',
           "Template path (default: #{DEFAULT_TEMPLATE})") { |v| @options[:template] = v }
    opt.on('--print',    'Write merged result to STDOUT, do not touch any file') { @options[:print] = true }
    opt.on('--debug',    'Verbose logging')                                       { @options[:debug] = true }
    opt.on('--validate', 'Validate merged JSON and exit (non-zero on error)')     { @options[:validate] = true }
  end.parse!

  raise "Template not found: #{@options[:template]}" unless File.file?(@options[:template])

  unless @options[:print] || @options[:validate]
    output_dir = File.dirname(@options[:output])
    raise "Output directory does not exist: #{output_dir}" unless File.directory?(output_dir)
  end

  @logger = Logger.new($stdout)
  @logger.level = @options[:debug] ? Logger::DEBUG : Logger::INFO
  @logger.formatter = proc { |_sev, _dt, _prog, msg| "#{msg}\n" }
end

# ---------------------------------------------------------------------------
# Render template → fresh JSON hash
# ---------------------------------------------------------------------------
def render_template
  @logger.debug("Profile:       #{ENV.fetch('OPENCODE_PROFILE', 'personal')}")
  @logger.debug("GROQ_API_KEY:  #{ENV.key?('GROQ_API_KEY') ? 'set' : 'not set'}")
  @logger.debug("OLLAMA_MODELS: #{ENV.fetch('OLLAMA_MODELS', 'qwen3:8b llama4:scout')}")
  @logger.info("Rendering #{@options[:template]}")

  template = File.read(@options[:template])
  rendered = ERB.new(template, trim_mode: '-').result(binding)
  JSON.parse(rendered)
end

# ---------------------------------------------------------------------------
# Load existing file if present
# ---------------------------------------------------------------------------
def load_existing
  path = @options[:output]
  return nil unless File.file?(path)

  @logger.info("Existing config found at #{path} — merging")
  JSON.parse(File.read(path))
rescue JSON::ParserError => e
  @logger.warn("Existing config is not valid JSON (#{e.message}) — using template only")
  nil
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main
  init

  template_hash = render_template
  existing_hash = @options[:print] || @options[:validate] ? nil : load_existing

  merged = if existing_hash
             @logger.debug('Running deep merge (template wins on scalar conflicts)')
             deep_merge(existing_hash, template_hash)
           else
             template_hash
           end

  output_json = JSON.pretty_generate(merged)

  begin
    JSON.parse(output_json)
  rescue JSON::ParserError => e
    @logger.error("Merged result is not valid JSON: #{e.message}")
    exit 1
  end

  @logger.info('JSON is valid') if @options[:validate]

  exit 0 if @options[:validate]

  if @options[:print]
    puts "\n========================================\n\n"
    puts output_json
    puts "\n========================================\n"
    return
  end

  # Write backup before touching the live file
  backup_path = "#{@options[:output]}.bak"
  if File.file?(@options[:output])
    FileUtils.cp(@options[:output], backup_path)
    @logger.debug("Backup written to #{backup_path}")
  end

  File.write(@options[:output], "#{output_json}\n")
  @logger.info("Written to #{@options[:output]}")
  @logger.info("Previous version backed up to #{backup_path}") if File.file?(backup_path)
end

main
