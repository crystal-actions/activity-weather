module ActivityWeather
  # Turns a WeatherReport into an SVG document. Styles implement `size` and
  # `body`; the base class assembles the single <style> block (animations +
  # theme rules) and the single <defs> block (sky/cloud/sun gradients + the
  # icon symbols) every style draws from.
  #
  # Theme modes work like the sibling project: in `auto` the condition
  # gradient stops and ink fills are CSS classes flipped by a
  # prefers-color-scheme media query, so the SVG follows the viewer's OS
  # theme even inside a README <img>; `light`/`dark` inline every color.
  abstract class Renderer
    def initialize(@config : Config, mode : ThemeMode? = nil)
      @mode = mode || @config.theme.mode
    end

    getter mode : ThemeMode

    # Document size of the most recent `render`, so a caller can report the
    # dimensions it just wrote without parsing the SVG back.
    getter last_size : {Float64, Float64} = {0.0, 0.0}

    def render(report : WeatherReport) : String
      width, height = size(report)
      @last_size = {width, height}
      SVG.document(width, height) do |io|
        style_block(io, report)
        defs_block(io, report)
        backdrop(io, report)
        body(io, report)
      end
    end

    def self.for(style : Style, config : Config, mode : ThemeMode? = nil) : Renderer
      case style
      in .card?     then Renderers::Card.new(config, mode)
      in .forecast? then Renderers::Forecast.new(config, mode)
      in .banner?   then Renderers::Banner.new(config, mode)
      in .terminal? then Renderers::Terminal.new(config, mode)
      in .minimal?  then Renderers::Minimal.new(config, mode)
      end
    end

    protected abstract def size(report : WeatherReport) : {Float64, Float64}
    protected abstract def body(io : String::Builder, report : WeatherReport) : Nil

    # Conditions whose icons and animations this document needs; forecast
    # adds every per-day condition.
    protected def used_conditions(report : WeatherReport) : Array(Condition)
      [report.condition]
    end

    # Named extras from Animations::EXTRA_CSS a style wants (bars, cursor…).
    protected def animation_extras : Array(String)
      [] of String
    end

    # Style CSS emitted per palette pass; `dark` names which palette. Only
    # meaningful in auto mode — static modes should inline instead.
    protected def style_rules(report : WeatherReport, dark : Bool) : String
      ""
    end

    # Extra defs a style needs, inside the shared <defs> element.
    protected def extra_defs(io : String::Builder, report : WeatherReport) : Nil
    end

    protected def theme : ThemeConfig
      @config.theme
    end

    protected def animated? : Bool
      @config.animated?
    end

    protected def condition_palette(report : WeatherReport) : ConditionPalette
      Palettes.for(report.condition, theme.mono?)
    end

    # Ink for the static palette of the current mode (auto uses light here —
    # its dark colors live in the media query).
    protected def ink(report : WeatherReport) : Ink
      resolved_ink(report, mode.dark?)
    end

    protected def resolved_ink(report : WeatherReport, dark : Bool) : Ink
      base = Palettes.ink(condition_palette(report), dark)
      override = dark ? theme.dark_text : theme.light_text
      return base unless override
      # A forced ink keeps the computed faint tone: dividers at full text
      # color would shout over the content.
      Ink.new(override, override, base.faint)
    end

    # Deterministic scatter, one stream per document, seeded by repository so
    # each repo gets its own scenery.
    protected def rng(report : WeatherReport) : SVG::Rng
      SVG::Rng.new(report.repo)
    end

    # ---- paint helpers: class= in auto mode, fill=/stroke= otherwise ----

    protected def ink_paint(report : WeatherReport) : String
      mode.auto? ? %(class="aw-ink") : %(fill="#{ink(report).primary}")
    end

    protected def sub_paint(report : WeatherReport) : String
      mode.auto? ? %(class="aw-sub") : %(fill="#{ink(report).secondary}")
    end

    protected def faint_paint(report : WeatherReport) : String
      mode.auto? ? %(class="aw-faint") : %(fill="#{ink(report).faint}")
    end

    protected def faint_stroke(report : WeatherReport) : String
      mode.auto? ? %(class="aw-stroke") : %(stroke="#{ink(report).faint}")
    end

    protected def accent(report : WeatherReport) : String
      condition_palette(report).accent
    end

    protected def font : String
      SVG.escape(theme.font_family)
    end

    protected def format_temp(value : Float64) : String
      "#{value.round.to_i}°"
    end

    protected def trend_glyph(trend : Trend) : String
      case trend
      in .rising?  then "↗"
      in .steady?  then "→"
      in .falling? then "↘"
      end
    end

    # The header line: the configured title with {repo} filled in, or the
    # repository name itself.
    protected def heading(report : WeatherReport) : String
      if title = @config.title
        title.gsub("{repo}", report.repo)
      else
        report.repo
      end
    end

    # ---- text measurement (no font metrics at render time) ----

    # Rough advance width: CJK and other wide scripts occupy roughly a full
    # em, latin about 0.55 em, digits slightly wider.
    protected def text_width(text : String, font_size : Float64) : Float64
      units = text.each_char.sum do |char|
        if char.ord > 0x2E80
          1.0
        elsif char.ascii_number?
          0.6
        else
          0.55
        end
      end
      units * font_size
    end

    # Budget-based truncation: walk characters until the width is spent,
    # then close with an ellipsis. Below two characters a bare "…" reads as
    # noise, so cut plainly instead.
    protected def truncate_to_width(text : String, font_size : Float64, max_width : Float64) : String
      return text if text_width(text, font_size) <= max_width
      ellipsis = text_width("…", font_size)
      spent = 0.0
      kept = ""
      text.each_char do |char|
        width = text_width(char.to_s, font_size)
        break if spent + width + ellipsis > max_width
        kept += char
        spent += width
      end
      kept.size < 2 ? text[0, 2] : "#{kept}…"
    end

    # Prefer dropping the owner before ellipsizing the name itself.
    protected def display_repo(report : WeatherReport, font_size : Float64, max_width : Float64) : String
      full = heading(report)
      return truncate_to_width(full, font_size, max_width) unless full == report.repo
      return full if text_width(full, font_size) <= max_width
      name = report.repo.split('/').last
      truncate_to_width(name, font_size, max_width)
    end

    # ---- document chrome ----

    protected def style_block(io : String::Builder, report : WeatherReport) : Nil
      css = String.build do |builder|
        builder << Animations.css(used_conditions(report), animation_extras) if animated?
        if mode.auto?
          builder << shared_rules(report, dark: false) << style_rules(report, dark: false)
          builder << "@media (prefers-color-scheme:dark){"
          builder << shared_rules(report, dark: true) << style_rules(report, dark: true)
          builder << "}"
        end
      end
      io << "  <style>" << css << "</style>\n" unless css.empty?
    end

    private def shared_rules(report : WeatherReport, dark : Bool) : String
      palette = condition_palette(report)
      sky = dark ? palette.dark : palette.light
      cloud = dark ? Palettes::CLOUD_DARK : Palettes::CLOUD_LIGHT
      colors = resolved_ink(report, dark)
      background = dark ? theme.dark_background : theme.light_background
      ".aw-ink{fill:#{colors.primary}}" \
      ".aw-sub{fill:#{colors.secondary}}" \
      ".aw-faint{fill:#{colors.faint}}" \
      ".aw-stroke{stroke:#{colors.faint}}" \
      ".aw-s0{stop-color:#{sky[0]}}.aw-s1{stop-color:#{sky[1]}}" \
      ".aw-c0{stop-color:#{cloud[0]}}.aw-c1{stop-color:#{cloud[1]}}" \
      ".aw-bg{fill:#{background}}"
    end

    protected def defs_block(io : String::Builder, report : WeatherReport) : Nil
      palette = condition_palette(report)
      dark = mode.dark?
      sky = dark ? palette.dark : palette.light
      cloud = dark ? Palettes::CLOUD_DARK : Palettes::CLOUD_LIGHT

      io << "  <defs>\n"
      io << %(    <linearGradient id="aw-sky" x1="0" y1="0" x2="0" y2="1">\n)
      io << %(      <stop offset="0" #{stop_attrs("aw-s0", sky[0])}/>\n)
      io << %(      <stop offset="1" #{stop_attrs("aw-s1", sky[1])}/>\n)
      io << "    </linearGradient>\n"
      io << %(    <linearGradient id="awg-cloud" x1="0" y1="0" x2="0" y2="1">\n)
      io << %(      <stop offset="0" #{stop_attrs("aw-c0", cloud[0])}/>\n)
      io << %(      <stop offset="1" #{stop_attrs("aw-c1", cloud[1])}/>\n)
      io << "    </linearGradient>\n"
      io << %(    <radialGradient id="awg-sun" cx="0.4" cy="0.35" r="0.85">\n)
      io << %(      <stop offset="0" stop-color="#FFE29A"/>\n)
      io << %(      <stop offset="1" stop-color="#FFB020"/>\n)
      io << "    </radialGradient>\n"
      io << %(    <linearGradient id="awg-storm" x1="0" y1="0" x2="0" y2="1">\n)
      io << %(      <stop offset="0" stop-color="#{Palettes::STORM_CLOUD[0]}"/>\n)
      io << %(      <stop offset="1" stop-color="#{Palettes::STORM_CLOUD[1]}"/>\n)
      io << "    </linearGradient>\n"
      WeatherIcons.defs(io, used_conditions(report))
      extra_defs(io, report)
      io << "  </defs>\n"
    end

    private def stop_attrs(css_class : String, color : String) : String
      mode.auto? ? %(class="#{css_class}") : %(stop-color="#{color}")
    end

    # The page-background rect behind the card, when the theme asks for one.
    private def backdrop(io : String::Builder, report : WeatherReport) : Nil
      if mode.auto?
        return if theme.light_background == "transparent" && theme.dark_background == "transparent"
        io << %(  <rect class="aw-bg" width="100%" height="100%"/>\n)
      else
        background = mode.dark? ? theme.dark_background : theme.light_background
        return if background == "transparent"
        io << %(  <rect width="100%" height="100%" fill="#{SVG.escape(background)}"/>\n)
      end
    end
  end
end
