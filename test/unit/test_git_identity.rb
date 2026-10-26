# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'erb'
require 'open3'
require 'tmpdir'

require_relative '../../src/install/utils'
require_relative '../../src/install/errors'
require_relative '../../src/install/post_setup'

# The generated .gitconfig gives repos of the personal GitHub account the personal email and
# signing key, and every other repo the main (work) identity.
class TestGitIdentity < Minitest::Test
  SHELL_DIR = File.expand_path('../..', __dir__)
  WORK = 'jane@work.example'
  PERSONAL = 'jane@home.example'
  ENV_KEYS = %w[HOME GIT_NAME GIT_EMAIL GIT_SIGNING_KEY GIT_PERSONAL_EMAIL GIT_PERSONAL_SIGNING_KEY GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM].freeze

  def with_env(values)
    saved = ENV_KEYS.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  # Renders like src/generate_tempate.rb, in process so the ENV set by with_env applies.
  def render(template, output)
    contents = ERB.new(File.read(File.join(SHELL_DIR, 'src/templates', template)), trim_mode: '-').result
    File.write(output, contents)
    contents
  end

  # Renders both files into a fake home and returns `git config <key>` for a repo set up by the block.
  def config_in_repo(identity, key)
    Dir.mktmpdir do |home|
      with_env(identity.merge('HOME' => home, 'GIT_CONFIG_GLOBAL' => File.join(home, '.gitconfig'), 'GIT_CONFIG_NOSYSTEM' => '1')) do
        render('.gitconfig.erb', File.join(home, '.gitconfig'))
        render('.gitconfig-personal.erb', File.join(home, '.gitconfig-personal'))
        repo = yield(home)
        system('git', 'init', '-q', repo, exception: true) unless File.directory?(File.join(repo, '.git'))
        out, = Open3.capture3('git', '-C', repo, 'config', key)
        out.strip
      end
    end
  end

  def identity
    { 'GIT_NAME' => 'Jane Doe', 'GIT_EMAIL' => WORK, 'GIT_SIGNING_KEY' => 'WORKKEY', 'GIT_PERSONAL_EMAIL' => PERSONAL,
      'GIT_PERSONAL_SIGNING_KEY' => 'HOMEKEY' }
  end

  def test_a_repo_with_a_personal_remote_uses_the_personal_identity
    %w[https://github.com/kalindudc/shell.git git@github.com:kalindudc/shell.git].each do |url|
      email = config_in_repo(identity, 'user.email') do |home|
        repo = File.join(home, 'elsewhere/shell')
        system('git', 'init', '-q', repo, exception: true)
        system('git', '-C', repo, 'remote', 'add', 'origin', url, exception: true)
        repo
      end

      assert_equal PERSONAL, email, url
    end
  end

  def test_a_repo_under_the_personal_folder_uses_the_personal_key
    key = config_in_repo(identity, 'user.signingkey') { |home| File.join(home, 'src/github.com/kalindudc/new-idea') }

    assert_equal 'HOMEKEY', key
  end

  def test_every_other_repo_keeps_the_main_identity
    email = config_in_repo(identity, 'user.email') do |home|
      repo = File.join(home, 'src/github.com/Example/app')
      system('git', 'init', '-q', repo, exception: true)
      system('git', '-C', repo, 'remote', 'add', 'origin', 'https://github.com/Example/app.git', exception: true)
      repo
    end

    assert_equal WORK, email
  end

  def test_no_personal_email_means_no_include
    Dir.mktmpdir do |home|
      with_env(identity.merge('HOME' => home, 'GIT_PERSONAL_EMAIL' => '')) do
        refute_match(/includeIf/, render('.gitconfig.erb', File.join(home, '.gitconfig')))
      end
    end
  end

  def test_personal_commits_are_not_signed_with_the_main_key_when_there_is_no_personal_key
    sign = config_in_repo(identity.merge('GIT_PERSONAL_SIGNING_KEY' => ''), 'commit.gpgsign') do |home|
      File.join(home, 'src/github.com/kalindudc/new-idea')
    end

    assert_equal 'false', sign
  end

  # setup_personal_gpg_key

  def run_setup(values, generated: 'NEWKEY')
    calls = { generated: [], uploaded: [], configured: [] }
    with_env(values) do
      Installer::Utils.stub(:command?, true) do
        Installer::PostSetup.stub(:signing_key_available?, ->(key) { key == 'HOMEKEY' }) do
          Installer::PostSetup.stub(:ensure_gpg_signing_key, lambda { |email|
            calls[:generated] << email
            generated
          }) do
            Installer::PostSetup.stub(:upload_gpg_key_to_github, ->(key) { calls[:uploaded] << key }) do
              Installer::PostSetup.stub(:configure_git_signing, ->(key) { calls[:configured] << key }) do
                capture_io { Installer::PostSetup.setup_personal_gpg_key }
              end
            end
          end
        end
      end
      calls[:key] = ENV.fetch('GIT_PERSONAL_SIGNING_KEY', nil)
    end
    calls
  end

  def test_setup_personal_gpg_key_finds_or_creates_a_key_for_the_personal_email
    calls = run_setup(identity.merge('GIT_PERSONAL_SIGNING_KEY' => ''))

    assert_equal [PERSONAL], calls[:generated]
    assert_equal ['NEWKEY'], calls[:uploaded]
    assert_equal 'NEWKEY', calls[:key]
    assert_empty calls[:configured], 'the personal key must not become the global signing key'
  end

  def test_setup_personal_gpg_key_keeps_a_configured_key_that_exists
    calls = run_setup(identity)

    assert_empty calls[:generated]
    assert_equal ['HOMEKEY'], calls[:uploaded]
  end

  def test_setup_personal_gpg_key_does_nothing_without_a_separate_personal_email
    [identity.merge('GIT_PERSONAL_EMAIL' => ''), identity.merge('GIT_PERSONAL_EMAIL' => WORK)].each do |values|
      calls = run_setup(values)

      assert_empty calls[:generated]
      assert_empty calls[:uploaded]
    end
  end
end
