#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'stringio'
require 'tmpdir'

require_relative '../../src/install/unfold'

# Exercises the .stow-unfold markers and the one-time migration against a scratch
# repo and home built to look like the real layout: folded ~/.pi, ~/.agents and
# ~/.claude, plus a real ~/.config holding a folded zsh directory.
class TestUnfold < Minitest::Test
  REAL_STOW_IGNORE = File.expand_path('../../home/.stow-local-ignore', __dir__)

  TRACKED = {
    '.zshrc' => 'zshrc',
    '.pi/agent/extensions/mine/index.ts' => 'mine',
    '.pi/agent/themes/dark.json' => '{}',
    '.agents/skills/myskill/SKILL.md' => 'skill',
    '.config/app/conf' => 'conf'
  }.freeze

  IGNORED = {
    '.pi/pkg/pi/bin' => 'pi',
    '.pi/agent/auth.json' => 'secret',
    '.pi/agent/sessions/a/s1.jsonl' => '{}',
    '.pi/agent/extensions/toolext/index.ts' => 'tool',
    '.agents/skills/myskill/SKILL_NOTES.md' => 'notes',
    '.agents/skills/toolskill/SKILL.md' => 'tool skill',
    '.config/zsh/completions/_x' => 'compdef',
    '.claude/settings.json' => '{}'
  }.freeze

  MARKERS = %w[.pi .pi/agent .pi/agent/extensions .agents .agents/skills .config].freeze

  GITIGNORE = <<~IGNORE
    home/.pi/*
    !home/.pi/agent/
    home/.pi/agent/*
    !home/.pi/agent/extensions/
    !home/.pi/agent/themes/
    home/.pi/agent/extensions/toolext
    home/.pi/agent/extensions/linked
    home/.agents/skills/toolskill/
    home/.agents/skills/*/SKILL_NOTES.md
    home/.config/zsh/
    home/.claude/
    !.stow-unfold
  IGNORE

  def setup
    skip 'stow is not installed' unless system('command -v stow >/dev/null 2>&1')

    @root = File.realpath(Dir.mktmpdir('unfold'))
    @repo = File.join(@root, 'repo')
    @pkg = File.join(@repo, 'home')
    @home = File.join(@root, 'home')
    @manifest = File.join(@root, 'state', 'unfold-manifest.json')
    FileUtils.mkdir_p([@pkg, @home, File.join(@root, 'nix-ext')])
    build_repo
  end

  def teardown
    FileUtils.rm_rf(@root) if @root
  end

  def test_marker_dirs_lists_parents_first
    assert_equal %w[.agents .config .pi .agents/skills .pi/agent .pi/agent/extensions], Installer::Unfold.marker_dirs(@pkg)
  end

  # macOS pgrep hides the caller's ancestors, which would miss a pi that runs the migration itself.
  def test_running_agents_come_from_full_process_list
    ps_output = "  1 pi\n  2 /usr/local/bin/claude\n  3 -zsh\n  4 pipx\n"
    success = Object.new.tap { |s| s.define_singleton_method(:success?) { true } }

    Open3.stub(:capture2, [ps_output, success]) do
      assert_equal ['pi (pid 1)', 'claude (pid 2)'], Installer::Unfold.default_running_agents
    end
  end

  def test_fresh_home_links_tracked_items_one_by_one
    git('clean', '-fdXq') # a fresh clone has no gitignored runtime files
    stow_with_markers

    assert_real_dir '.pi'
    assert_real_dir '.pi/agent/extensions'
    assert_linked '.pi/agent/extensions/mine'
    assert_linked '.pi/agent/themes'
    assert_linked '.agents/skills/myskill'
    refute path_present?(File.join(@home, '.pi', Installer::Unfold::MARKER)), 'markers must not be linked into home'

    write(File.join(@home, '.agents/skills/newtool/SKILL.md'), 'installed by a tool')

    refute path_present?(File.join(@pkg, '.agents/skills/newtool')), 'tool installs must stay out of the repo'
  end

  def test_prepare_targets_refuses_folded_tree
    legacy_stow

    error = assert_raises(Installer::Error) { Installer::Unfold.prepare_targets!(@pkg, @home) }
    assert_match(/\.agents is a symlink/, error.message)
  end

  def test_plan_on_legacy_layout
    legacy_stow
    plan = migration.plan

    assert_empty plan.errors
    steps = plan.steps.map { |s| "#{s.action} #{s.path}" }

    [
      'unfold .pi', 'unfold .agents', 'mkdir .pi/agent', 'mkdir .pi/agent/extensions', 'mkdir .agents/skills',
      'move .pi/pkg', 'move .pi/agent/auth.json', 'move .pi/agent/sessions', 'move .pi/agent/extensions/toolext',
      'move .pi/agent/extensions/linked', 'move .agents/skills/toolskill',
      'unlink .config/zsh', 'move .config/zsh', 'unlink .claude', 'move .claude'
    ].each { |step| assert_includes steps, step }
    assert_equal steps.index('unfold .pi') + 1, steps.index('move .pi/pkg'), 'a folded dir is unfolded before its children move'
    %w[.pi/agent/extensions/mine .pi/agent/themes .agents/skills/myskill .config/app].each { |rel| assert_includes plan.kept, rel }
  end

  def test_apply_moves_ignored_files_out_and_links_tracked_ones
    legacy_stow
    migration.apply!(stow: -> { stow_with_markers })

    MARKERS.each { |rel| assert_real_dir rel }
    %w[.pi/agent/extensions/mine .pi/agent/themes .agents/skills/myskill .config/app .zshrc].each { |rel| assert_linked rel }
    %w[.pi/pkg/pi/bin .pi/agent/auth.json .pi/agent/sessions/a/s1.jsonl .pi/agent/extensions/toolext/index.ts
       .agents/skills/toolskill/SKILL.md .config/zsh/completions/_x .claude/settings.json].each do |rel|
      assert File.file?(File.join(@home, rel)), "#{rel} should live in home"
      refute path_present?(File.join(@pkg, rel)), "#{rel} should have left the repo"
    end
    assert_equal File.join(@root, 'nix-ext'), File.readlink(File.join(@home, '.pi/agent/extensions/linked'))
    refute File.symlink?(File.join(@home, '.config/zsh'))
    refute File.symlink?(File.join(@home, '.claude'))
    assert File.file?(File.join(@pkg, '.agents/skills/myskill/SKILL_NOTES.md')), 'ignored files inside tracked dirs stay put'
    assert_path_exists @manifest
  end

  # Like ~/.config/nvim: a tracked dir that was already real in home, so stow links the files inside it.
  def test_apply_accepts_tracked_dirs_that_are_already_real
    FileUtils.mkdir_p(File.join(@home, '.config/app'))
    legacy_stow
    migration.apply!(stow: -> { stow_with_markers })

    assert_real_dir '.config/app'
    assert_linked '.config/app/conf'
  end

  def test_apply_refuses_while_agents_run
    legacy_stow
    running = migration(running_agents: -> { ['pi (pid 1)'] })

    assert_raises(Installer::Error) { running.apply!(stow: -> { flunk 'must not stow' }) }
    assert File.symlink?(File.join(@home, '.pi')), 'nothing may change'
    refute_path_exists @manifest
  end

  def test_untracked_work_blocks_the_migration
    legacy_stow
    write(File.join(@pkg, '.pi/agent/extensions/wip/index.ts'), 'not committed yet')

    assert(migration.plan.errors.any? { |e| e.include?('.pi/agent/extensions/wip is untracked') })
    assert_raises(Installer::Error) { migration.apply!(stow: -> { flunk 'must not stow' }) }
    assert File.symlink?(File.join(@home, '.pi')), 'nothing may change'
  end

  def test_conflicting_destination_blocks_the_migration
    legacy_stow
    File.unlink(File.join(@home, '.config/zsh'))
    write(File.join(@home, '.config/zsh/other'), 'already here')

    assert(migration.plan.errors.any? { |e| e.include?('.config/zsh exists both in the repo and at') })
  end

  def test_revert_restores_the_folded_layout
    legacy_stow
    before = %w[.pi .agents .claude .config/zsh].to_h { |rel| [rel, File.readlink(File.join(@home, rel))] }
    migration.apply!(stow: -> { stow_with_markers })
    migration.revert!

    before.each { |rel, target| assert_equal target, File.readlink(File.join(@home, rel)), "#{rel} should be a folded link again" }
    IGNORED.each_key { |rel| assert File.file?(File.join(@pkg, rel)), "#{rel} should be back in the repo" }
    refute_path_exists @manifest
  end

  private

  def migration(running_agents: -> { [] })
    Installer::Unfold::Migration.new(repo_dir: @repo, home: @home, manifest_path: @manifest,
                                     running_agents: running_agents, out: StringIO.new)
  end

  def build_repo
    FileUtils.cp(REAL_STOW_IGNORE, File.join(@pkg, '.stow-local-ignore'))
    File.write(File.join(@repo, '.gitignore'), GITIGNORE)
    TRACKED.merge(IGNORED).each { |rel, body| write(File.join(@pkg, rel), body) }
    MARKERS.each { |rel| write(File.join(@pkg, rel, Installer::Unfold::MARKER), 'marker') }
    File.symlink(File.join(@root, 'nix-ext'), File.join(@pkg, '.pi/agent/extensions/linked'))
    File.symlink(File.join(@home, '.agents/skills'), File.join(@pkg, '.claude/skills'))
    git('init', '-q')
    git('add', '-A')
    git('-c', 'user.email=t@example.com', '-c', 'user.name=t', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'fixture')
  end

  # Stow as it ran before markers existed: ~/.config already real, everything else folds.
  def legacy_stow
    FileUtils.mkdir_p(File.join(@home, '.config'))
    run!('stow', 'home', '-d', @repo, '-t', @home)

    assert File.symlink?(File.join(@home, '.pi')), 'fixture should start folded'
  end

  def stow_with_markers
    Installer::Unfold.prepare_targets!(@pkg, @home)
    run!('stow', 'home', '-d', @repo, '-t', @home, '--adopt')
  end

  def git(*args)
    run!('git', '-C', @repo, *args, env: { 'GIT_CONFIG_GLOBAL' => File::NULL, 'GIT_CONFIG_NOSYSTEM' => '1' })
  end

  def run!(*cmd, env: {})
    out, status = Open3.capture2e(env, *cmd)

    assert_predicate status, :success?, "#{cmd.join(' ')} failed:\n#{out}"
  end

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def path_present?(path) = File.exist?(path) || File.symlink?(path)

  def assert_real_dir(rel)
    path = File.join(@home, rel)

    assert File.directory?(path) && !File.symlink?(path), "#{rel} should be a real directory"
  end

  def assert_linked(rel)
    path = File.join(@home, rel)

    assert File.symlink?(path), "#{rel} should be a stow link"
    assert_equal File.realpath(File.join(@pkg, rel)), File.realpath(path)
  end
end
