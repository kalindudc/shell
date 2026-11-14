# frozen_string_literal: true

require 'fileutils'

module Journal
  # The house style's kit, shared with every other page the house builds: its stylesheets, script,
  # fonts and seal, plus the journal's own paper styles in assets/. A site gets the files beside its
  # pages; the briefing in bb's frame cannot load sibling files, so it gets them inline.
  module Kit
    DIR = File.expand_path('../../../.agents/skills/house-style', __dir__)
    ASSETS = File.expand_path('assets', __dir__)
    STYLES = %w[palette.css base.css components.css].freeze
    SEAL = 'M'

    module_function

    def read(name, dir = DIR) = Journal.read(File.join(dir, name))

    def fonts = Dir[File.join(DIR, 'fonts', '*.woff2')]

    # The kit under out/kit and the paper's own files beside the pages.
    def copy(out)
      FileUtils.mkdir_p(File.join(out, 'kit', 'fonts'))
      (STYLES + ['site.js']).each { |name| FileUtils.cp(File.join(DIR, name), File.join(out, 'kit', name)) }
      (fonts + [File.join(DIR, 'fonts', 'LICENSE.md')]).each { |path| FileUtils.cp(path, File.join(out, 'kit', 'fonts')) }
      %w[journal.css journal.js].each { |name| FileUtils.cp(File.join(ASSETS, name), File.join(out, name)) }
    end

    # Every stylesheet in one, with the fonts it names embedded, for a page that has no siblings.
    def inline_css
      css = (STYLES.map { |name| read(name) } + [read('journal.css', ASSETS)]).join("\n")
      css.gsub(%r{url\("fonts/([\w.-]+\.woff2)"\)}) do
        %(url("data:font/woff2;base64,#{[File.binread(File.join(DIR, 'fonts', Regexp.last_match(1)))].pack('m0')}"))
      end
    end

    def script = read('journal.js', ASSETS)

    # The seal's inline SVG for the header; with favicon:, the same seal filled, as the site's icon.
    def seal(favicon: nil)
      args = ['python3', File.join(DIR, 'scripts', 'mark.py'), SEAL]
      args += ['--favicon', favicon] if favicon
      out, err, status = Open3.capture3(*args)
      raise "mark.py failed: #{err.strip}" unless status.success?

      out.strip
    end
  end
end
