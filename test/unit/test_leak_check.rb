# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/leak_check'
require_relative '../../src/install/private_copies'

class TestLeakCheck < Minitest::Test
  SHELL_DIR = File.expand_path('../..', __dir__)
  LeakCheck = Installer::LeakCheck
  Copies = Installer::PrivateCopies

  def labels(text, denylist = [])
    LeakCheck.scan(text, denylist).map { |finding| finding[:label] }
  end

  def test_scan_flags_personal_ids_paths_and_tokens
    assert_equal ['email address'], labels('mail me at jane@example.com')
    assert_equal ['home directory path'], labels('cd /Users/jane/src')
    assert_equal ['bb id'], labels('bb automation runs auto_abcde_fgh-i')
    assert_equal ['Slack id'], labels('DM U0ABCDEF12')
    assert_equal ['token'], labels('export GH=ghp_0123456789abcdefghijABCDEFGHIJ')
  end

  def test_scan_allows_paths_every_mac_has
    assert_empty labels('du -xk -d1 /Users/Shared /private/tmp "$HOME/.bb"')
  end

  def test_scan_reports_the_line_of_each_finding
    findings = LeakCheck.scan("fine\nthe Acme monorepo\n", [/acme/i])

    assert_equal [{ line: 2, label: 'denylist /acme/i', match: 'Acme' }], findings
  end

  def test_denylist_reads_one_case_insensitive_pattern_per_line
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'leak-denylist.txt')
      File.write(path, "# work terms\n\nacme\n\\bwidget co\\b\n")

      assert_equal [/acme/i, /\bwidget co\b/i], LeakCheck.denylist(path)
      assert_empty LeakCheck.denylist(File.join(dir, 'missing.txt'))
    end
  end

  def test_check_paths_scans_every_file_under_a_directory
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'bb/automations/report'))
      File.write(File.join(dir, 'bb/automations/report/prompt.md'), "ok\nask jane@example.com\n")
      File.write(File.join(dir, 'clean.sh'), "echo ok\n")

      findings = LeakCheck.check_paths(%w[bb/automations clean.sh missing], root: dir, denylist: [])

      assert_equal([['bb/automations/report/prompt.md', 2, 'email address']], findings.map { |f| [f[:file], f[:line], f[:label]] })
    end
  end

  def test_the_public_automation_files_have_no_generic_leaks
    assert_empty LeakCheck.check_paths(LeakCheck::PUBLIC_PATHS, root: SHELL_DIR, denylist: [])
  end

  # Private copies

  def test_save_mirrors_the_listed_paths_and_skips_bytecode
    Dir.mktmpdir do |dir|
      source = File.join(dir, 'helper')
      FileUtils.mkdir_p(File.join(source, 'bin/__pycache__'))
      FileUtils.mkdir_p(File.join(source, 'state'))
      File.write(File.join(source, 'README.md'), "readme\n")
      File.write(File.join(source, 'bin/tool.py'), "print(1)\n")
      File.write(File.join(source, 'bin/__pycache__/tool.cpython-313.pyc'), 'x')
      File.write(File.join(source, 'state/ledger.json'), '{}')
      destination = File.join(dir, 'private/helpers/helper')
      FileUtils.mkdir_p(File.join(destination, 'bin'))
      File.write(File.join(destination, 'bin/removed.py'), 'old')

      copy = { 'from' => source, 'to' => 'helpers/helper', 'include' => %w[README.md bin] }
      Copies.save!(copy, File.join(dir, 'private'))

      files = Dir.glob('**/*', base: destination).select { |path| File.file?(File.join(destination, path)) }.sort

      assert_equal %w[README.md bin/tool.py], files
    end
  end

  def test_restore_copies_back_only_the_files_that_are_missing
    Dir.mktmpdir do |dir|
      private_dir = File.join(dir, 'private')
      FileUtils.mkdir_p(File.join(private_dir, 'helpers/helper/bin'))
      File.write(File.join(private_dir, 'helpers/helper/README.md'), "saved\n")
      File.write(File.join(private_dir, 'helpers/helper/bin/tool.py'), "saved\n")
      target = File.join(dir, 'helper')
      FileUtils.mkdir_p(target)
      File.write(File.join(target, 'README.md'), "local edit\n")

      copy = { 'from' => target, 'to' => 'helpers/helper', 'include' => %w[README.md bin] }
      restored = Copies.restore!(copy, private_dir)

      assert_equal [File.join(target, 'bin/tool.py')], restored
      assert_equal "local edit\n", File.read(File.join(target, 'README.md'))
      assert_equal "saved\n", File.read(File.join(target, 'bin/tool.py'))
    end
  end

  def test_copies_are_read_from_the_private_backup_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'backup.yml'), "copies:\n  - from: ~/x\n    to: helpers/x\n    include: [bin]\n")

      assert_equal [{ 'from' => File.expand_path('~/x'), 'to' => 'helpers/x', 'include' => ['bin'] }], Copies.load(dir)
      assert_empty Copies.load(File.join(dir, 'missing'))
    end
  end
end
