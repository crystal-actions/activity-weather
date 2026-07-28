module ActivityWeather
  module Renderers
    # 840x220 README hero: a layered scene — sky, sun or moon, two drifting
    # cloud layers, condition precipitation, and two hill silhouettes whose
    # ridgelines are seeded from the repository name, so every repo gets its
    # own horizon. Text sits on the left with a soft outline for legibility
    # over the scenery.
    class Banner < Renderer
      WIDTH  = 840.0
      HEIGHT = 220.0

      # Hills are translucent dark washes, so they sit convincingly on any
      # condition sky in either mode.
      FAR_HILL  = "rgba(18,38,58,0.28)"
      NEAR_HILL = "rgba(9,22,38,0.42)"
      # Text over the near hill, which is always dark.
      ON_HILL = "rgba(242,246,250,0.88)"

      protected def size(report : WeatherReport) : {Float64, Float64}
        {WIDTH, HEIGHT}
      end

      protected def animation_extras : Array(String)
        ["layers"]
      end

      protected def extra_defs(io : String::Builder, report : WeatherReport) : Nil
        io << %(    <clipPath id="aw-banner"><rect x="1" y="1" width="#{SVG.num(WIDTH - 2)}" height="#{SVG.num(HEIGHT - 2)}" rx="16"/></clipPath>\n)
      end

      protected def body(io : String::Builder, report : WeatherReport) : Nil
        random = rng(report)
        io << %(  <rect x="0.5" y="0.5" width="#{SVG.num(WIDTH - 1)}" height="#{SVG.num(HEIGHT - 1)}" rx="16" fill="url(#aw-sky)" #{faint_stroke(report)}/>\n)
        io << %(  <g clip-path="url(#aw-banner)">\n)
        celestial(io, report, random)
        aurora_sky(io, random) if report.condition.aurora?
        rainbow_arcs(io) if report.condition.rainbow?
        cloud_layers(io, report, random)
        precipitation(io, report, random)
        hills(io, random)
        storm_theatrics(io, report, random) if report.condition.stormy?
        io << "  </g>\n"
        text_block(io, report)
      end

      private def celestial(io : String::Builder, report : WeatherReport, random : SVG::Rng) : Nil
        case report.condition
        in .sunny?, .partly_cloudy?, .rainbow?, .windy?
          io << %(    <circle cx="700" cy="64" r="52" fill="#FFE29A" opacity="0.18"/>\n)
          if report.condition.sunny?
            io << %(    <g class="aw-rays" style="transform-origin:700px 64px" stroke="#FFC53D" stroke-width="5" stroke-linecap="round">\n)
            8.times do |index|
              angle = index * Math::PI / 4 + 0.2
              io << %(      <line x1="#{SVG.num(700 + 44 * Math.cos(angle))}" y1="#{SVG.num(64 + 44 * Math.sin(angle))}" x2="#{SVG.num(700 + 56 * Math.cos(angle))}" y2="#{SVG.num(64 + 56 * Math.sin(angle))}"/>\n)
            end
            io << "    </g>\n"
          end
          io << %(    <circle cx="700" cy="64" r="34" fill="url(#awg-sun)"/>\n)
        in .aurora?
          io << %(    <circle cx="700" cy="58" r="26" fill="#E9F0F8" opacity="0.92"/>\n)
          io << %(    <circle cx="712" cy="50" r="24" fill="url(#aw-sky)"/>\n)
        in .cloudy?, .rainy?, .stormy?, .foggy?, .snowy?
          # Overcast: the cloud layers are the sky's whole story.
        end
      end

      private def aurora_sky(io : String::Builder, random : SVG::Rng) : Nil
        Palettes::AURORA_RIBBONS.each_with_index do |color, index|
          base = 34 + index * 26
          io << %(    <path class="aw-ribbon aw-r#{index + 1}" d="M-40 #{base + 30} C 180 #{base - 24}, 420 #{base + 44}, 880 #{base - 16}" fill="none" stroke="#{color}" stroke-width="26" stroke-linecap="round" opacity="0.16"/>\n)
        end
        io << %(    <g fill="#EAF4FF">\n)
        12.times do |index|
          x = random.between(20.0, 820.0)
          y = random.between(14.0, 110.0)
          r = random.between(0.9, 1.9)
          io << %(      <circle class="aw-star aw-t#{index % 3 + 1}" cx="#{SVG.num(x)}" cy="#{SVG.num(y)}" r="#{SVG.num(r)}" opacity="0.7"/>\n)
        end
        io << "    </g>\n"
      end

      private def rainbow_arcs(io : String::Builder) : Nil
        io << %(    <g fill="none" stroke-width="12" opacity="0.4">\n)
        Palettes::RAINBOW_ARCS.each_with_index do |color, index|
          radius = 205 - index * 14
          io << %(      <path d="M#{SVG.num(190 - radius)} 250 A#{SVG.num(radius)} #{SVG.num(radius)} 0 0 1 #{SVG.num(190 + radius)} 250" stroke="#{color}"/>\n)
        end
        io << "    </g>\n"
      end

      private def cloud_layers(io : String::Builder, report : WeatherReport, random : SVG::Rng) : Nil
        condition = report.condition
        return if condition.aurora?
        fill = condition.stormy? ? "url(#awg-storm)" : "url(#awg-cloud)"

        far = condition.sunny? ? 1 : 3
        io << %(    <g class="aw-layer-far" opacity="0.25">\n)
        far.times do
          x = random.between(-30.0, 700.0)
          y = random.between(-6.0, 34.0)
          scale = random.between(1.2, 1.7)
          WeatherIcons.cloud(io, transform: "translate(#{SVG.num(x)},#{SVG.num(y)}) scale(#{SVG.num(scale)})", fill: fill, cls: "")
        end
        io << "    </g>\n"

        return if condition.sunny? || condition.windy?
        io << %(    <g class="aw-layer-near" opacity="0.55">\n)
        2.times do
          x = random.between(-20.0, 640.0)
          y = random.between(14.0, 56.0)
          scale = random.between(1.0, 1.4)
          WeatherIcons.cloud(io, transform: "translate(#{SVG.num(x)},#{SVG.num(y)}) scale(#{SVG.num(scale)})", fill: fill, cls: "")
        end
        io << "    </g>\n"
      end

      private def precipitation(io : String::Builder, report : WeatherReport, random : SVG::Rng) : Nil
        case report.condition
        in .rainy?, .stormy?
          io << %(    <g stroke="#{report.condition.stormy? ? "#9FB3C8" : "#4FC3F7"}" stroke-width="2" stroke-linecap="round" opacity="0.45">\n)
          14.times do |index|
            x = random.between(20.0, 820.0)
            y = random.between(60.0, 150.0)
            io << %(      <line class="aw-streak aw-d#{index % 3 + 1}" x1="#{SVG.num(x)}" y1="#{SVG.num(y)}" x2="#{SVG.num(x - 4)}" y2="#{SVG.num(y + 13)}"/>\n)
          end
          io << "    </g>\n"
        in .snowy?
          io << %(    <g fill="#EAF2FB" opacity="0.9">\n)
          16.times do |index|
            x = random.between(16.0, 824.0)
            y = random.between(40.0, 150.0)
            r = random.between(1.3, 2.7)
            io << %(      <circle class="aw-flake aw-f#{index % 3 + 1}" cx="#{SVG.num(x)}" cy="#{SVG.num(y)}" r="#{SVG.num(r)}"/>\n)
          end
          io << "    </g>\n"
        in .foggy?
          # Bands hug the horizon so they read as ground fog instead of
          # striking through the text block on the left.
          [{128.0, 0.2, "aw-fog-a"}, {150.0, 0.16, "aw-fog-b"}, {170.0, 0.18, "aw-fog-a"}].each do |(y, opacity, cls)|
            x = random.between(-60.0, 40.0)
            io << %(    <rect class="#{cls}" x="#{SVG.num(x)}" y="#{SVG.num(y)}" width="#{SVG.num(WIDTH + 80)}" height="16" rx="8" fill="#ffffff" opacity="#{SVG.num(opacity)}"/>\n)
          end
        in .windy?
          io << %(    <g fill="none" stroke="#EAF7FB" stroke-width="3.5" stroke-linecap="round" opacity="0.4">\n)
          io << %(      <path class="aw-wind aw-w1" d="M340 70 h300 a10 10 0 1 0 -10 -17"/>\n)
          io << %(      <path class="aw-wind aw-w2" d="M420 110 h330 a11 11 0 1 1 -11 19"/>\n)
          io << %(      <path class="aw-wind aw-w3" d="M380 150 h240"/>\n)
          io << "    </g>\n"
        in .sunny?, .partly_cloudy?, .cloudy?, .rainbow?, .aurora?
          # Dry skies.
        end
      end

      # Two ridgelines from seeded control points, smoothed with cubics.
      private def hills(io : String::Builder, random : SVG::Rng) : Nil
        io << %(    <path d="#{ridge_path(random, 126.0, 164.0)}" fill="#{FAR_HILL}"/>\n)
        io << %(    <path d="#{ridge_path(random, 154.0, 188.0)}" fill="#{NEAR_HILL}"/>\n)
      end

      private def ridge_path(random : SVG::Rng, min_y : Float64, max_y : Float64) : String
        step = WIDTH / 5
        points = (0..5).map { |index| {index * step, random.between(min_y, max_y)} }
        String.build do |path|
          path << "M0 #{SVG.num(HEIGHT)} L0 #{SVG.num(points.first[1])}"
          points.each_cons_pair do |(x1, y1), (x2, y2)|
            third = (x2 - x1) / 3
            path << " C#{SVG.num(x1 + third)} #{SVG.num(y1)} #{SVG.num(x2 - third)} #{SVG.num(y2)} #{SVG.num(x2)} #{SVG.num(y2)}"
          end
          path << " L#{SVG.num(WIDTH)} #{SVG.num(HEIGHT)} Z"
        end
      end

      private def storm_theatrics(io : String::Builder, report : WeatherReport, random : SVG::Rng) : Nil
        x = random.between(360.0, 640.0)
        io << %(    <g transform="translate(#{SVG.num(x)},14) scale(1.9)">\n)
        io << %(      <path class="aw-bolt" d="M34 36 L25 50 h6 L27 62 L41 46 h-7 l6 -10 z" fill="#FFD93D" opacity="#{animated? ? "0" : "0.9"}"/>\n)
        io << "    </g>\n"
        if animated?
          io << %(    <rect class="aw-flash" x="1" y="1" width="#{SVG.num(WIDTH - 2)}" height="#{SVG.num(HEIGHT - 2)}" fill="#ffffff"/>\n)
        end
      end

      private def text_block(io : String::Builder, report : WeatherReport) : Nil
        outline = %(paint-order="stroke" stroke="rgba(8,20,32,0.3)")
        name = display_repo(report, 22.0, 470.0)
        io << %(  <text x="36" y="64" font-family="#{font}" font-size="22" font-weight="700" #{ink_paint(report)} #{outline} stroke-width="4">#{SVG.escape(name)}</text>\n)
        phrase = truncate_to_width(report.phrase, 14.0, 470.0)
        io << %(  <text x="36" y="92" font-family="#{font}" font-size="14" #{sub_paint(report)} #{outline} stroke-width="3">#{SVG.escape(phrase)}</text>\n)

        chip = "#{format_temp(report.temperature)} · #{report.condition.key.split('_').join(' ').upcase} #{trend_glyph(report.pressure)}"
        chip_width = text_width(chip, 13.0) + 26
        io << %(  <rect x="36" y="106" width="#{SVG.num(chip_width)}" height="26" rx="13" fill="rgba(10,24,40,0.28)" #{faint_stroke(report)}/>\n)
        io << %(  <text x="#{SVG.num(36 + chip_width / 2)}" y="123" text-anchor="middle" font-family="#{font}" font-size="13" font-weight="600" fill="#F2F6FA">#{SVG.escape(chip)}</text>\n)

        metrics = report.metrics
        summary = "#{metrics.commits} commits · #{metrics.prs_opened} prs · #{metrics.issues_opened} issues · +#{metrics.stars_gained} stars · #{report.period_label}"
        io << %(  <text x="36" y="200" font-family="#{font}" font-size="12" fill="#{ON_HILL}">#{SVG.escape(summary)}</text>\n)
      end
    end
  end
end
