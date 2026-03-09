#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'fileutils'
require 'tmpdir'
require_relative '../../lib/todo/store'

class TestStore < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('todo_store_test')
    @store = Todo::Store.new(@dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # ── Init ────────────────────────────────────────────────────────────

  def test_init_creates_structure
    @store.init!

    assert_path_exists File.join(@dir, '.meta.json')
    assert_path_exists File.join(@dir, 'config.json')
    assert Dir.exist?(File.join(@dir, 'general'))
    assert_path_exists File.join(@dir, 'general', '.category.json')
    assert_path_exists File.join(@dir, 'general', 'todos.json')
  end

  def test_initialized_returns_false_before_init
    refute_predicate @store, :initialized?
  end

  def test_initialized_returns_true_after_init
    @store.init!

    assert_predicate @store, :initialized?
  end

  def test_init_is_idempotent
    @store.init!
    @store.save_task({ 'id' => 1, 'description' => 'Keep me', 'category' => 'general', 'status' => 'pending', 'tags' => [] }, 'general')
    @store.init!

    assert_equal 1, @store.read_canonical_tasks('general').length
  end

  # ── Config ──────────────────────────────────────────────────────────

  def test_load_config_returns_defaults_before_init
    config = @store.load_config

    assert_equal 64, config['desc_max']
  end

  def test_load_config_reads_custom_values
    @store.init!
    File.write(File.join(@dir, 'config.json'), JSON.generate({ 'desc_max' => 50 }))

    assert_equal 50, @store.load_config['desc_max']
  end

  # ── ID generation ───────────────────────────────────────────────────

  def test_next_id_auto_increments
    @store.init!

    assert_equal 1, @store.next_id
    assert_equal 2, @store.next_id
    assert_equal 3, @store.next_id
  end

  # ── Category operations ─────────────────────────────────────────────

  def test_all_categories_after_init
    @store.init!

    assert_equal ['general'], @store.all_categories
  end

  def test_ensure_category_creates_dir
    @store.init!
    @store.ensure_category('work', description: 'Work tasks')

    assert Dir.exist?(File.join(@dir, 'work'))
    meta = @store.category_meta('work')

    assert_equal 'Work tasks', meta['description']
  end

  def test_all_categories_sorted
    @store.init!
    @store.ensure_category('work')
    @store.ensure_category('alpha')

    assert_equal %w[alpha general work], @store.all_categories
  end

  def test_remove_category
    @store.init!
    @store.ensure_category('temp')
    @store.remove_category('temp')

    refute Dir.exist?(File.join(@dir, 'temp'))
  end

  # ── Task CRUD ───────────────────────────────────────────────────────

  def test_save_and_find_task
    @store.init!
    task = { 'id' => 1, 'description' => 'Test', 'category' => 'general', 'status' => 'pending', 'tags' => [] }
    @store.save_task(task, 'general')
    result = @store.find_task(1)

    assert result
    found_task, cat = result

    assert_equal 'Test', found_task['description']
    assert_equal 'general', cat
  end

  def test_save_task_updates_existing
    @store.init!
    task = { 'id' => 1, 'description' => 'Old', 'category' => 'general', 'status' => 'pending', 'tags' => [] }
    @store.save_task(task, 'general')
    task['description'] = 'New'
    @store.save_task(task, 'general')

    assert_equal 1, @store.read_canonical_tasks('general').length
    assert_equal 'New', @store.read_canonical_tasks('general').first['description']
  end

  def test_remove_task
    @store.init!
    @store.save_task({ 'id' => 1, 'description' => 'Gone', 'category' => 'general', 'status' => 'pending', 'tags' => [] }, 'general')

    assert @store.remove_task(1)
    assert_equal 0, @store.read_canonical_tasks('general').length
  end

  def test_remove_task_returns_false_for_missing
    @store.init!

    refute @store.remove_task(999)
  end

  # ── all_tasks ───────────────────────────────────────────────────────

  def test_all_tasks_excludes_done_by_default
    @store.init!
    @store.save_task({ 'id' => 1, 'description' => 'Active', 'category' => 'general', 'status' => 'pending', 'tags' => [] }, 'general')
    @store.save_task({ 'id' => 2, 'description' => 'Done', 'category' => 'general', 'status' => 'done', 'tags' => [] }, 'general')

    assert_equal 1, @store.all_tasks.length
    assert_equal 'Active', @store.all_tasks.first['description']
  end

  def test_all_tasks_includes_done_when_requested
    @store.init!
    @store.save_task({ 'id' => 1, 'description' => 'Active', 'category' => 'general', 'status' => 'pending', 'tags' => [] }, 'general')
    @store.save_task({ 'id' => 2, 'description' => 'Done', 'category' => 'general', 'status' => 'done', 'tags' => [] }, 'general')

    assert_equal 2, @store.all_tasks(include_done: true).length
  end

  def test_all_tasks_across_categories
    @store.init!
    @store.ensure_category('work')
    @store.save_task({ 'id' => 1, 'description' => 'A', 'category' => 'general', 'status' => 'pending', 'tags' => [] }, 'general')
    @store.save_task({ 'id' => 2, 'description' => 'B', 'category' => 'work', 'status' => 'pending', 'tags' => [] }, 'work')

    assert_equal 2, @store.all_tasks.length
  end

  # ── Auto-discovery ──────────────────────────────────────────────────

  def test_auto_discover_external_json
    @store.init!
    @store.ensure_category('work')
    # Drop an external file
    external = [{ 'id' => 999, 'description' => 'External', 'category' => 'work', 'status' => 'pending', 'tags' => [] }]
    File.write(File.join(@dir, 'work', 'backlog.json'), JSON.generate(external))
    tasks = @store.read_category_tasks('work')

    assert_equal 1, tasks.length
    assert_equal 'External', tasks.first['description']
  end

  def test_find_task_across_external_files
    @store.init!
    @store.ensure_category('work')
    File.write(File.join(@dir, 'work', 'sprint.json'),
               JSON.generate([{ 'id' => 42, 'description' => 'Sprint task', 'category' => 'work', 'status' => 'pending', 'tags' => [] }]))
    result = @store.find_task(42)

    assert result
    assert_equal 'Sprint task', result[0]['description']
  end
end
