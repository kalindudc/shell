# frozen_string_literal: true

require 'json'
require 'date'
require 'fileutils'

module Todo
  class Store
    DEFAULT_CONFIG = { 'desc_max' => 64 }.freeze
    DEFAULT_CATEGORY = 'general'

    attr_reader :conf_dir

    def initialize(conf_dir)
      @conf_dir = conf_dir
    end

    # ── Paths ───────────────────────────────────────────────────────

    def meta_path    = File.join(@conf_dir, '.meta.json')
    def config_path  = File.join(@conf_dir, 'config.json')

    def category_dir(name)
      File.join(@conf_dir, name)
    end

    # ── JSON helpers ────────────────────────────────────────────────

    def read_json(path)
      JSON.parse(File.read(path))
    end

    def write_json(path, data)
      File.write(path, JSON.pretty_generate(data))
    end

    # ── Config ──────────────────────────────────────────────────────

    def load_config
      return DEFAULT_CONFIG.dup unless File.exist?(config_path)

      saved = JSON.parse(File.read(config_path))
      DEFAULT_CONFIG.merge(saved)
    rescue JSON::ParserError
      DEFAULT_CONFIG.dup
    end

    # ── Init ────────────────────────────────────────────────────────

    def init!
      FileUtils.mkdir_p(@conf_dir)
      write_json(meta_path, { 'next_id' => 1 }) unless File.exist?(meta_path)
      write_json(config_path, DEFAULT_CONFIG) unless File.exist?(config_path)
      ensure_category(DEFAULT_CATEGORY, description: 'General tasks')
    end

    def initialized?
      Dir.exist?(@conf_dir) && File.exist?(meta_path)
    end

    # ── ID generation ───────────────────────────────────────────────

    def next_id
      meta = read_json(meta_path)
      id = meta['next_id']
      meta['next_id'] = id + 1
      write_json(meta_path, meta)
      id
    end

    def today
      Date.today.to_s
    end

    # ── Category operations ─────────────────────────────────────────

    def all_categories
      return [] unless Dir.exist?(@conf_dir)

      Dir.children(@conf_dir)
         .select { |e| File.directory?(File.join(@conf_dir, e)) && !e.start_with?('.') }
         .sort
    end

    def ensure_category(name, description: '')
      dir = category_dir(name)
      FileUtils.mkdir_p(dir)
      cat_meta_path = File.join(dir, '.category.json')
      write_json(cat_meta_path, { 'description' => description }) unless File.exist?(cat_meta_path)
      todos_path = File.join(dir, 'todos.json')
      write_json(todos_path, []) unless File.exist?(todos_path)
    end

    def category_meta(name)
      path = File.join(category_dir(name), '.category.json')
      return { 'description' => '', 'color' => '' } unless File.exist?(path)

      read_json(path)
    rescue JSON::ParserError
      { 'description' => '', 'color' => '' }
    end

    def remove_category(name)
      FileUtils.rm_rf(category_dir(name))
    end

    # ── Task operations ─────────────────────────────────────────────

    def read_category_tasks(name)
      dir = category_dir(name)
      return [] unless Dir.exist?(dir)

      files = Dir.glob(File.join(dir, '*.json')).reject { |f| File.basename(f) == '.category.json' }
      tasks = []
      files.each do |f|
        data = read_json(f)
        arr = data.is_a?(Array) ? data : [data]
        arr.each { |t| t['category'] = name }
        tasks.concat(arr)
      rescue JSON::ParserError
        $stderr.puts "Warning: skipping malformed file #{f}"
      end
      tasks
    end

    def write_category_tasks(name, tasks)
      dir = category_dir(name)
      FileUtils.mkdir_p(dir)
      write_json(File.join(dir, 'todos.json'), tasks)
    end

    def read_canonical_tasks(name)
      path = File.join(category_dir(name), 'todos.json')
      return [] unless File.exist?(path)

      read_json(path)
    rescue JSON::ParserError
      []
    end

    def all_tasks(include_done: false)
      tasks = []
      all_categories.each do |cat|
        cat_tasks = read_category_tasks(cat)
        cat_tasks = cat_tasks.reject { |t| t['status'] == 'done' } unless include_done
        tasks.concat(cat_tasks)
      end
      tasks
    end

    def find_task(id)
      all_categories.each do |cat|
        read_category_tasks(cat).each do |t|
          return [t, cat] if t['id'] == id
        end
      end
      nil
    end

    def save_task(task, category)
      # Remove redundant 'category' key before persisting (derived from directory)
      clean = task.except('category')
      tasks = read_canonical_tasks(category)
      idx = tasks.index { |t| t['id'] == clean['id'] }
      if idx
        tasks[idx] = clean
      else
        tasks << clean
      end
      write_category_tasks(category, tasks)
    end

    def remove_task(id)
      all_categories.each do |cat|
        tasks = read_canonical_tasks(cat)
        before = tasks.length
        tasks.reject! { |t| t['id'] == id }
        if tasks.length < before
          write_category_tasks(cat, tasks)
          return true
        end
      end
      false
    end
  end
end
