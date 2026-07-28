module ActivityWeather
  # The CSS animation catalog. CSS keyframes rather than SMIL: one `<style>`
  # block is easy to omit entirely when `animated: false`, and a single
  # `prefers-reduced-motion` rule silences everything at once. The output is
  # a pure function of (conditions, style needs), so golden files hold.
  #
  # Class naming: `aw-` prefix throughout; numbered variants (`aw-d2`) are
  # stagger delays so identical shapes fall out of phase.
  module Animations
    REDUCED_MOTION_GUARD = "@media (prefers-reduced-motion:reduce){*{animation:none !important}}"

    # Keyframes + rules for the icon layer of each condition.
    CONDITION_CSS = {
      Condition::Sunny => "@keyframes aw-spin{to{transform:rotate(360deg)}}" \
                          "@keyframes aw-breathe{50%{transform:scale(1.05)}}" \
                          ".aw-rays{animation:aw-spin 90s linear infinite;transform-origin:32px 32px}" \
                          ".aw-sun-core{animation:aw-breathe 4s ease-in-out infinite;transform-origin:32px 32px}" \
                          "@keyframes aw-twinkle{50%{opacity:1}}" \
                          ".aw-star{opacity:.25;animation:aw-twinkle 2.8s ease-in-out infinite}" \
                          ".aw-t2{animation-delay:.9s}.aw-t3{animation-delay:1.7s}",
      Condition::PartlyCloudy => "@keyframes aw-spin{to{transform:rotate(360deg)}}" \
                                 ".aw-rays{animation:aw-spin 90s linear infinite;transform-origin:32px 32px}" \
                                 "@keyframes aw-drift{50%{transform:translateX(5px)}}" \
                                 ".aw-cloud{animation:aw-drift 7s ease-in-out infinite}",
      Condition::Cloudy => "@keyframes aw-drift{50%{transform:translateX(5px)}}" \
                           "@keyframes aw-drift-back{50%{transform:translateX(-4px)}}" \
                           ".aw-cloud{animation:aw-drift 7s ease-in-out infinite}" \
                           ".aw-cloud-back{animation:aw-drift-back 9s ease-in-out infinite}",
      Condition::Rainy => "@keyframes aw-drift{50%{transform:translateX(5px)}}" \
                          ".aw-cloud{animation:aw-drift 7s ease-in-out infinite}" \
                          "@keyframes aw-fall{70%{opacity:1}to{transform:translateY(13px);opacity:0}}" \
                          ".aw-drop{animation:aw-fall 1.2s linear infinite}" \
                          ".aw-d2{animation-delay:.4s}.aw-d3{animation-delay:.8s}" \
                          ".aw-streak{animation:aw-fall 1.1s linear infinite}",
      Condition::Stormy => "@keyframes aw-bolt-flash{0%,86%{opacity:0}88%{opacity:1}90%{opacity:.35}93%{opacity:1}96%,100%{opacity:0}}" \
                           ".aw-bolt{animation:aw-bolt-flash 4.5s infinite}" \
                           "@keyframes aw-sheet{0%,85%{opacity:0}88%{opacity:.26}90%{opacity:.06}93%{opacity:.2}97%,100%{opacity:0}}" \
                           ".aw-flash{opacity:0;animation:aw-sheet 4.5s infinite}" \
                           "@keyframes aw-fall{70%{opacity:1}to{transform:translateY(13px);opacity:0}}" \
                           ".aw-drop{animation:aw-fall 1.2s linear infinite}" \
                           ".aw-d2{animation-delay:.4s}.aw-d3{animation-delay:.8s}" \
                           ".aw-streak{animation:aw-fall 1.1s linear infinite}",
      Condition::Foggy => "@keyframes aw-fog-l{50%{transform:translateX(6px)}}" \
                          "@keyframes aw-fog-r{50%{transform:translateX(-6px)}}" \
                          ".aw-fog-a{animation:aw-fog-l 6s ease-in-out infinite}" \
                          ".aw-fog-b{animation:aw-fog-r 8s ease-in-out infinite}",
      Condition::Snowy => "@keyframes aw-drift{50%{transform:translateX(5px)}}" \
                          ".aw-cloud{animation:aw-drift 7s ease-in-out infinite}" \
                          "@keyframes aw-snowfall{0%{transform:translate(0,0);opacity:1}50%{transform:translate(2.5px,8px)}90%{opacity:1}100%{transform:translate(-1px,15px);opacity:0}}" \
                          ".aw-flake{animation:aw-snowfall 3.2s linear infinite}" \
                          ".aw-f2{animation-delay:1.1s}.aw-f3{animation-delay:2.1s}",
      Condition::Windy => "@keyframes aw-gust{0%{stroke-dashoffset:120;opacity:0}25%{opacity:1}85%{opacity:1}100%{stroke-dashoffset:-40;opacity:0}}" \
                          ".aw-wind{stroke-dasharray:70 90;animation:aw-gust 2.6s ease-in-out infinite}" \
                          ".aw-w2{animation-delay:.35s}.aw-w3{animation-delay:.7s}",
      Condition::Rainbow => "@keyframes aw-drift{50%{transform:translateX(5px)}}" \
                            ".aw-cloud{animation:aw-drift 7s ease-in-out infinite}" \
                            "@keyframes aw-glow{50%{opacity:1}}" \
                            ".aw-arc{animation:aw-glow 5s ease-in-out infinite}",
      Condition::Aurora => "@keyframes aw-ribbon-sway{50%{transform:translateX(7px) skewX(3deg)}}" \
                           ".aw-ribbon{animation:aw-ribbon-sway 10s ease-in-out infinite}" \
                           ".aw-r2{animation-delay:2.4s}.aw-r3{animation-delay:5.1s}" \
                           "@keyframes aw-twinkle{50%{opacity:1}}" \
                           ".aw-star{opacity:.25;animation:aw-twinkle 2.8s ease-in-out infinite}" \
                           ".aw-t2{animation-delay:.9s}.aw-t3{animation-delay:1.7s}",
    }

    # Scene-level extras a style can request by name.
    EXTRA_CSS = {
      # Banner cloud layers drift on longer periods, in opposite phases.
      "layers" => "@keyframes aw-drift-far{50%{transform:translateX(14px)}}" \
                  "@keyframes aw-drift-near{50%{transform:translateX(-11px)}}" \
                  ".aw-layer-far{animation:aw-drift-far 34s ease-in-out infinite}" \
                  ".aw-layer-near{animation:aw-drift-near 22s ease-in-out infinite}",
      # Forecast bars grow in once, staggered per column via inline delay.
      "bars" => "@keyframes aw-rise{from{transform:scaleY(0)}}" \
                ".aw-grow{animation:aw-rise .6s cubic-bezier(.2,.8,.3,1) backwards}",
      # Terminal cursor blink.
      "cursor" => "@keyframes aw-blink{50%{opacity:0}}" \
                  ".aw-cursor{animation:aw-blink 1.1s steps(2,jump-none) infinite}",
    }

    # Assembled CSS for the conditions on screen. Deduplicated: several
    # conditions share keyframes, and a forecast strip mixes conditions, so
    # rules are split on "}" boundaries and each unique rule survives once.
    def self.css(conditions : Enumerable(Condition), extras : Array(String) = [] of String) : String
      blocks = conditions.map { |condition| CONDITION_CSS[condition] }.to_a
      blocks.concat(extras.map { |name| EXTRA_CSS[name] })
      rules = [] of String
      blocks.each do |block|
        split_rules(block).each do |rule|
          rules << rule unless rules.includes?(rule)
        end
      end
      return "" if rules.empty?
      rules.join + REDUCED_MOTION_GUARD
    end

    # Splits on top-level rule boundaries; keyframes blocks contain nested
    # braces, so a depth counter rather than a plain split.
    private def self.split_rules(css : String) : Array(String)
      rules = [] of String
      depth = 0
      start = 0
      css.each_char_with_index do |char, index|
        depth += 1 if char == '{'
        if char == '}'
          depth -= 1
          if depth.zero?
            rules << css[start..index]
            start = index + 1
          end
        end
      end
      rules
    end
  end
end
