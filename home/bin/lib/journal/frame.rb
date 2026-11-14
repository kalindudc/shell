# frozen_string_literal: true

module Journal
  # The house frame around every site page: the header with the seal, the parts and the controls,
  # the foot with the byline, and the page shell that loads the kit.
  module Frame
    # Runs before first paint: the theme the reader picked on an earlier visit, and the class the
    # kit's controls wait for.
    THEME_INIT = 'try{const t=localStorage.getItem("theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch{}' \
                 'document.documentElement.classList.add("js");'
    SWITCH = <<~HTML.tr("\n", '')
      <div class="switch" role="radiogroup" aria-label="Theme">
      <button type="button" role="radio" aria-checked="false" tabindex="-1" data-choice="light" aria-label="Light" title="Light"><svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/></svg></button>
      <button type="button" role="radio" aria-checked="true" tabindex="0" data-choice="system" aria-label="Match System" title="Match System"><svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="8"/><path d="M12 4a8 8 0 0 0 0 16z" fill="currentColor" stroke="none"/></svg></button>
      <button type="button" role="radio" aria-checked="false" tabindex="-1" data-choice="dark" aria-label="Dark" title="Dark"><svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"/></svg></button>
      </div>
    HTML
    KEYS = <<~HTML.tr("\n", '')
      <dialog class="keys" id="keys" aria-labelledby="keys-h"><h2 id="keys-h">Keys</h2><dl>
      <div><dt><kbd>j</kbd></dt><dd>Next part</dd></div><div><dt><kbd>k</kbd></dt><dd>Previous part</dd></div>
      <div><dt><kbd>g</kbd></dt><dd>Top of the page</dd></div><div><dt><kbd>G</kbd></dt><dd>Last part</dd></div>
      <div><dt><kbd>?</kbd></dt><dd>Show or hide this list; Escape closes it</dd></div></dl>
      <form method="dialog"><label class="toggle"><input type="checkbox" data-keys-toggle checked>Character shortcuts</label><button class="btn" type="submit">Close</button></form></dialog>
    HTML

    module_function

    def esc(value) = CGI.escapeHTML(value.to_s)

    def byline = ENV.fetch('JOURNAL_BYLINE', '')

    def header(seal, parts, current)
      pages = [['index.html', 'Today', current == :today], ['archive.html', 'Archive', current == :archive]].map do |href, text, here|
        %(<a href="#{href}"#{' aria-current="page"' if here}>#{text}</a>)
      end
      route = parts.map { |id, text| %(<li><a href="##{id}">#{esc(text)}</a></li>) }.join
      %(<header class="topbar"><div class="inner"><a class="home" href="index.html">#{seal}<span class="name">#{Site::NAME}</span></a>) +
        %(<div class="index"><nav class="pages" aria-label="Pages">#{pages.join}</nav>) +
        %(<nav class="route" aria-label="Parts"><ol>#{route}</ol></nav></div><div class="actions">) +
        %(<button type="button" class="iconbtn" data-open-keys aria-label="Keys" title="Keys (?)"><kbd>?</kbd></button>#{SWITCH}</div></div></header>)
    end

    def foot(links)
      by = byline.empty? ? '' : %(<span class="by">by #{esc(byline)}</span>)
      %(<footer class="foot"><div class="inner"><span>#{links.join}</span>#{by}</div></footer>)
    end

    def shell(title:, description:, twin:, header:, main:, foot:)
      %(<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">) +
        %(<meta name="color-scheme" content="light dark"><meta name="theme-color" content="#f6f3ec"><title>#{esc(title)}</title>) +
        %(<meta name="description" content="#{esc(description)}"><meta property="og:type" content="website">) +
        %(<meta property="og:title" content="#{esc(title)}"><meta property="og:description" content="#{esc(description)}">) +
        %(<script>#{THEME_INIT}</script>) +
        %(<link rel="preload" href="kit/fonts/source-serif-4.woff2" as="font" type="font/woff2" crossorigin>) +
        %(<link rel="preload" href="kit/fonts/ibm-plex-mono-500.woff2" as="font" type="font/woff2" crossorigin>) +
        %w[kit/palette.css kit/base.css kit/components.css journal.css].map { |css| %(<link rel="stylesheet" href="#{css}">) }.join +
        %(<link rel="icon" href="favicon.svg" type="image/svg+xml"><link rel="alternate" type="text/markdown" href="#{twin}"></head>) +
        %(<body><a class="skip" href="#main">Skip to the page</a>#{header}<main class="page edge" id="main">#{main}</main>#{foot}#{KEYS}) +
        %(<script src="kit/site.js" defer></script><script src="journal.js" defer></script></body></html>)
    end
  end
end
