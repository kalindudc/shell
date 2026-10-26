# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'erb'
require 'fileutils'
require 'open3'
require 'tmpdir'

# The generated .gitconfig gives every repo the main identity (GIT_EMAIL, GIT_SIGNING_KEY) and
# then includes git/gitconfig from the private repo, whose conditional includes switch work
# repos to the work identity. The work rules stay private because they name work systems.
class TestGitIdentity < Minitest::Test
  SHELL_DIR = File.expand_path('../..', __dir__)
  TEMPLATE = File.join(SHELL_DIR, 'src/templates/.gitconfig.erb')
  MAIN = 'jane@home.example'
  WORK = 'jane@work.example'
  ENV_KEYS = %w[HOME GIT_NAME GIT_EMAIL GIT_SIGNING_KEY SHELL_PRIVATE_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM].freeze

  WORK_RULES = <<~CONFIG
    [includeIf "hasconfig:remote.*.url:https://github.com/example-corp*/**"]
    \tpath = work.gitconfig
    [includeIf "gitdir:~/src/mirror-*/"]
    \tpath = work.gitconfig
  CONFIG
  WORK_IDENTITY = "[user]\n\temail = #{WORK}\n\tsigningkey = WORKKEY\n"

  def with_env(values)
    saved = ENV_KEYS.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  # Renders the template like src/generate_tempate.rb into a fake home, with or without the
  # private repo's work rules, and yields the home directory.
  def with_home(private_rules: true)
    Dir.mktmpdir do |home|
      private_dir = File.join(home, 'private')
      if private_rules
        FileUtils.mkdir_p(File.join(private_dir, 'git'))
        File.write(File.join(private_dir, 'git/gitconfig'), WORK_RULES)
        File.write(File.join(private_dir, 'git/work.gitconfig'), WORK_IDENTITY)
      end
      identity = { 'GIT_NAME' => 'Jane Doe', 'GIT_EMAIL' => MAIN, 'GIT_SIGNING_KEY' => 'MAINKEY' }
      with_env(identity.merge('HOME' => home, 'SHELL_PRIVATE_DIR' => private_dir,
                              'GIT_CONFIG_GLOBAL' => File.join(home, '.gitconfig'), 'GIT_CONFIG_NOSYSTEM' => '1')) do
        File.write(File.join(home, '.gitconfig'), ERB.new(File.read(TEMPLATE), trim_mode: '-').result)
        yield home
      end
    end
  end

  def repo(home, path, remote = nil)
    dir = File.join(home, path)
    system('git', 'init', '-q', dir, exception: true)
    system('git', '-C', dir, 'remote', 'add', 'origin', remote, exception: true) if remote
    dir
  end

  def config(dir, key)
    out, err, status = Open3.capture3('git', '-C', dir, 'config', key)
    assert status.success?, "git config #{key} failed in #{dir}: #{err}"
    out.strip
  end

  def test_every_other_repo_uses_the_main_identity
    with_home do |home|
      [repo(home, 'src/mine', 'https://github.com/jane/mine.git'),
       repo(home, 'src/fork', 'https://github.com/someone/project.git'),
       repo(home, 'src/scratch')].each do |dir|
        assert_equal MAIN, config(dir, 'user.email'), dir
        assert_equal 'MAINKEY', config(dir, 'user.signingkey'), dir
      end
    end
  end

  def test_the_private_rules_give_work_remotes_the_work_identity
    with_home do |home|
      %w[https://github.com/example-corp/app.git https://github.com/example-corp-labs/tool.git].each_with_index do |url, index|
        dir = repo(home, "elsewhere/work-#{index}", url)

        assert_equal WORK, config(dir, 'user.email'), url
        assert_equal 'WORKKEY', config(dir, 'user.signingkey'), url
      end
    end
  end

  def test_the_private_rules_cover_work_folders_without_a_remote
    with_home do |home|
      assert_equal WORK, config(repo(home, 'src/mirror-routing'), 'user.email')
    end
  end

  def test_without_the_private_repo_every_repo_uses_the_main_identity
    with_home(private_rules: false) do |home|
      dir = repo(home, 'src/work', 'https://github.com/example-corp/app.git')

      assert_equal MAIN, config(dir, 'user.email')
    end
  end

  def test_the_public_template_holds_no_repo_rules
    refute_match(/includeIf/, File.read(TEMPLATE))
  end
end
