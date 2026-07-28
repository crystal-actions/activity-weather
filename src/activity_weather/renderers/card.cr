module ActivityWeather
  module Renderers
    # The default style: a 480x240 weather-app card. Big animated icon on the
    # left, the temperature and condition beside it, the phrase underneath,
    # and a metrics row along the bottom. Each condition also scatters a few
    # ambient touches (sparkles, streaks, fog bands) behind the content,
    # seeded from the repository name.
    class Card < Renderer
      WIDTH  = 480.0
      HEIGHT = 240.0

      protected def size(report : WeatherReport) : {Float64, Float64}
        {WIDTH, HEIGHT}
      end

      protected def extra_defs(io : String::Builder, report : WeatherReport) : Nil
        io << %(    <clipPath id="aw-card"><rect x="1" y="1" width="#{SVG.num(WIDTH - 2)}" height="#{SVG.num(HEIGHT - 2)}" rx="16"/></clipPath>\n)
      end

      protected def body(io : String::Builder, report : WeatherReport) : Nil
        io << %(  <rect x="0.5" y="0.5" width="#{SVG.num(WIDTH - 1)}" height="#{SVG.num(HEIGHT - 1)}" rx="16" fill="url(#aw-sky)" #{faint_stroke(report)}/>\n)
        io << %(  <g clip-path="url(#aw-card)">\n)
        ambient(io, report)
        io << "  </g>\n"

        header(io, report)
        WeatherIcons.use(io, report.condition, 30, 74, 116)
        reading(io, report)
        metrics_row(io, report)

        # The lightning sheet sits above everything and is invisible until
        # its animation raises the opacity.
        if report.condition.stormy? && animated?
          io << %(  <rect class="aw-flash" x="1" y="1" width="#{SVG.num(WIDTH - 2)}" height="#{SVG.num(HEIGHT - 2)}" rx="16" fill="#ffffff"/>\n)
        end
      end

      private def header(io : String::Builder, report : WeatherReport) : Nil
        name = display_repo(report, 17.0, 300.0)
        io << %(  <text x="28" y="37" font-family="#{font}" font-size="17" font-weight="600" #{ink_paint(report)}>#{SVG.escape(name)}</text>\n)
        io << %(  <text x="452" y="34" text-anchor="end" font-family="#{font}" font-size="12" #{sub_paint(report)}>#{SVG.escape(report.period_label)}</text>\n)
        io << %(  <text x="452" y="52" text-anchor="end" font-family="#{font}" font-size="10.5" #{sub_paint(report)} opacity="0.8">#{SVG.escape("#{report.wind} km/h · #{report.humidity}%")}</text>\n)
      end

      private def reading(io : String::Builder, report : WeatherReport) : Nil
        temp = format_temp(report.temperature)
        io << %(  <text x="176" y="153" font-family="#{font}" font-size="54" font-weight="700" #{ink_paint(report)}>#{SVG.escape(temp)}</text>\n)
        trend_x = 176 + text_width(temp, 54.0) + 12
        io << %(  <text x="#{SVG.num(trend_x)}" y="150" font-family="#{font}" font-size="24" fill="#{accent(report)}">#{trend_glyph(report.pressure)}</text>\n)

        label = report.condition.key.split('_').join(' ').upcase
        io << %(  <text x="178" y="178" font-family="#{font}" font-size="13" font-weight="600" letter-spacing="1.5" #{sub_paint(report)}>#{SVG.escape(label)}</text>\n)

        phrase = truncate_to_width(report.phrase, 12.5, 274.0)
        io << %(  <text x="178" y="200" font-family="#{font}" font-size="12.5" font-style="italic" #{sub_paint(report)}>#{SVG.escape(phrase)}</text>\n)
      end

      private def metrics_row(io : String::Builder, report : WeatherReport) : Nil
        io << %(  <line x1="28" y1="212" x2="452" y2="212" #{faint_stroke(report)} stroke-width="1"/>\n)
        cells = [
          {format_count(report.metrics.commits), "commits"},
          {format_count(report.metrics.prs_opened), "prs"},
          {format_count(report.metrics.issues_opened), "issues"},
          {"+#{format_count(report.metrics.stars_gained)}", "stars"},
        ]
        cells.each_with_index do |(value, label), index|
          x = 28 + index * 108
          io << %(  <text x="#{x}" y="232" font-family="#{font}" font-size="13" font-weight="600" #{ink_paint(report)}>#{SVG.escape(value)}<tspan dx="5" font-size="10.5" font-weight="400" #{sub_paint(report)}>#{label}</tspan></text>\n)
        end
      end

      private def format_count(value : Int32) : String
        return value.to_s if value < 1000
        "#{(value / 1000.0).round(1)}k"
      end

      # A few condition-specific touches behind the content, seeded per repo.
      private def ambient(io : String::Builder, report : WeatherReport) : Nil
        random = rng(report)
        case report.condition
        in .sunny?, .aurora?
          stars(io, random, count: report.condition.aurora? ? 8 : 4)
          aurora_ribbons(io) if report.condition.aurora?
        in .rainy?, .stormy?
          streaks(io, random, report.condition.stormy? ? "#9FB3C8" : "#4FC3F7")
        in .snowy?
          ambient_flakes(io, random)
        in .foggy?
          fog_banks(io)
        in .windy?
          streamlines(io)
        in .rainbow?
          backdrop_arcs(io)
        in .partly_cloudy?, .cloudy?
          # The icon's own clouds carry these; a busy sky would fight the text.
        end
      end

      private def stars(io : String::Builder, random : SVG::Rng, count : Int32) : Nil
        io << %(    <g fill="#F4FAFF">\n)
        count.times do |index|
          x = random.between(180.0, 460.0)
          y = random.between(24.0, 96.0)
          r = random.between(1.0, 2.0)
          io << %(      <circle class="aw-star aw-t#{index % 3 + 1}" cx="#{SVG.num(x)}" cy="#{SVG.num(y)}" r="#{SVG.num(r)}" opacity="0.6"/>\n)
        end
        io << "    </g>\n"
      end

      private def aurora_ribbons(io : String::Builder) : Nil
        Palettes::AURORA_RIBBONS.each_with_index do |color, index|
          y = 26 + index * 20
          io << %(    <path class="aw-ribbon aw-r#{index + 1}" d="M-20 #{y + 26} C 120 #{y - 14}, 300 #{y + 40}, 500 #{y - 8}" fill="none" stroke="#{color}" stroke-width="20" stroke-linecap="round" opacity="0.14"/>\n)
        end
      end

      private def streaks(io : String::Builder, random : SVG::Rng, color : String) : Nil
        io << %(    <g stroke="#{color}" stroke-width="2" stroke-linecap="round" opacity="0.35">\n)
        6.times do |index|
          x = random.between(180.0, 460.0)
          y = random.between(34.0, 96.0)
          io << %(      <line class="aw-streak aw-d#{index % 3 + 1}" x1="#{SVG.num(x)}" y1="#{SVG.num(y)}" x2="#{SVG.num(x - 3)}" y2="#{SVG.num(y + 11)}"/>\n)
        end
        io << "    </g>\n"
      end

      private def ambient_flakes(io : String::Builder, random : SVG::Rng) : Nil
        io << %(    <g fill="#EAF2FB" opacity="0.85">\n)
        7.times do |index|
          x = random.between(170.0, 460.0)
          y = random.between(28.0, 104.0)
          r = random.between(1.4, 2.6)
          io << %(      <circle class="aw-flake aw-f#{index % 3 + 1}" cx="#{SVG.num(x)}" cy="#{SVG.num(y)}" r="#{SVG.num(r)}"/>\n)
        end
        io << "    </g>\n"
      end

      private def fog_banks(io : String::Builder) : Nil
        io << %(    <rect class="aw-fog-a" x="-30" y="98" width="360" height="12" rx="6" fill="#ffffff" opacity="0.2"/>\n)
        io << %(    <rect class="aw-fog-b" x="60" y="138" width="450" height="14" rx="7" fill="#ffffff" opacity="0.16"/>\n)
      end

      private def streamlines(io : String::Builder) : Nil
        io << %(    <g fill="none" stroke="#EAF7FB" stroke-width="3" stroke-linecap="round" opacity="0.3">\n)
        io << %(      <path class="aw-wind aw-w1" d="M150 62 h240 a9 9 0 1 0 -9 -15"/>\n)
        io << %(      <path class="aw-wind aw-w2" d="M190 96 h250 a10 10 0 1 1 -10 17"/>\n)
        io << "    </g>\n"
      end

      private def backdrop_arcs(io : String::Builder) : Nil
        io << %(    <g fill="none" stroke-width="11" opacity="0.22">\n)
        Palettes::RAINBOW_ARCS.each_with_index do |color, index|
          radius = 210 - index * 13
          io << %(      <path d="M#{SVG.num(420 - radius)} 262 A#{SVG.num(radius)} #{SVG.num(radius)} 0 0 1 #{SVG.num(420 + radius)} 262" stroke="#{color}"/>\n)
        end
        io << "    </g>\n"
      end
    end
  end
end
