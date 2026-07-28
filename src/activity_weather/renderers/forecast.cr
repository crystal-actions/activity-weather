module ActivityWeather
  module Renderers
    # 760x240: a condensed "today" panel on the left and one column per
    # trailing day on the right — mini icon, temperature, and an activity
    # bar in that day's accent color, growing in with a stagger.
    class Forecast < Renderer
      WIDTH        = 760.0
      HEIGHT       = 240.0
      PANEL_WIDTH  = 248.0
      COLUMNS_LEFT = 268.0
      BAR_BASE     = 196.0

      protected def size(report : WeatherReport) : {Float64, Float64}
        {WIDTH, HEIGHT}
      end

      protected def used_conditions(report : WeatherReport) : Array(Condition)
        ([report.condition] + report.daily.map(&.condition)).uniq
      end

      protected def animation_extras : Array(String)
        ["bars"]
      end

      protected def style_rules(report : WeatherReport, dark : Bool) : String
        ".aw-overlay{fill:#{overlay_color(report, dark)}}"
      end

      protected def extra_defs(io : String::Builder, report : WeatherReport) : Nil
        io << %(    <clipPath id="aw-card"><rect x="1" y="1" width="#{SVG.num(WIDTH - 2)}" height="#{SVG.num(HEIGHT - 2)}" rx="16"/></clipPath>\n)
      end

      protected def body(io : String::Builder, report : WeatherReport) : Nil
        io << %(  <rect x="0.5" y="0.5" width="#{SVG.num(WIDTH - 1)}" height="#{SVG.num(HEIGHT - 1)}" rx="16" fill="url(#aw-sky)" #{faint_stroke(report)}/>\n)
        # A quieter field behind the day columns so the bars read against
        # the sky.
        io << %(  <g clip-path="url(#aw-card)"><rect x="#{SVG.num(PANEL_WIDTH + 8)}" y="1" width="#{SVG.num(WIDTH - PANEL_WIDTH - 9)}" height="#{SVG.num(HEIGHT - 2)}" #{overlay_paint(report)}/></g>\n)
        io << %(  <line x1="#{SVG.num(PANEL_WIDTH + 8)}" y1="20" x2="#{SVG.num(PANEL_WIDTH + 8)}" y2="220" #{faint_stroke(report)} stroke-width="1"/>\n)

        today_panel(io, report)
        columns(io, report)
      end

      private def today_panel(io : String::Builder, report : WeatherReport) : Nil
        name = display_repo(report, 15.0, 200.0)
        io << %(  <text x="24" y="40" font-family="#{font}" font-size="15" font-weight="600" #{ink_paint(report)}>#{SVG.escape(name)}</text>\n)
        io << %(  <text x="24" y="58" font-family="#{font}" font-size="11" #{sub_paint(report)}>#{SVG.escape(report.period_label)}</text>\n)

        WeatherIcons.use(io, report.condition, 20, 70, 92)
        temp = format_temp(report.temperature)
        io << %(  <text x="124" y="122" font-family="#{font}" font-size="40" font-weight="700" #{ink_paint(report)}>#{SVG.escape(temp)}</text>\n)
        trend_x = 124 + text_width(temp, 40.0) + 8
        io << %(  <text x="#{SVG.num(trend_x)}" y="120" font-family="#{font}" font-size="18" fill="#{accent(report)}">#{trend_glyph(report.pressure)}</text>\n)
        label = report.condition.key.split('_').join(' ').upcase
        io << %(  <text x="125" y="142" font-family="#{font}" font-size="11" font-weight="600" letter-spacing="1.2" #{sub_paint(report)}>#{SVG.escape(label)}</text>\n)

        phrase = truncate_to_width(report.phrase, 11.5, 208.0)
        io << %(  <text x="24" y="196" font-family="#{font}" font-size="11.5" font-style="italic" #{sub_paint(report)}>#{SVG.escape(phrase)}</text>\n)
        summary = "#{report.metrics.commits} commits · #{report.metrics.prs_opened} prs · #{report.metrics.issues_opened} issues"
        io << %(  <text x="24" y="218" font-family="#{font}" font-size="11" #{sub_paint(report)}>#{SVG.escape(summary)}</text>\n)
      end

      private def columns(io : String::Builder, report : WeatherReport) : Nil
        days = report.daily
        return if days.empty?
        span = (WIDTH - COLUMNS_LEFT - 12.0) / days.size

        days.each_with_index do |day, index|
          center = COLUMNS_LEFT + span * index + span / 2

          if index == days.size - 1
            io << %(  <rect x="#{SVG.num(center - span / 2 + 3)}" y="34" width="#{SVG.num(span - 6)}" height="178" rx="10" fill="none" #{faint_stroke(report)} stroke-width="1"/>\n)
          end

          io << %(  <text x="#{SVG.num(center)}" y="56" text-anchor="middle" font-family="#{font}" font-size="11" #{sub_paint(report)}>#{day_label(day, index == days.size - 1)}</text>\n)
          WeatherIcons.use(io, day.condition, center - 19, 66, 38)
          io << %(  <text x="#{SVG.num(center)}" y="132" text-anchor="middle" font-family="#{font}" font-size="14" font-weight="600" #{ink_paint(report)}>#{SVG.escape(format_temp(day.temperature))}</text>\n)

          bar_height = 10.0 + day.temperature / 40.0 * 50.0
          bar_paint = Palettes.for(day.condition, theme.mono?).accent
          io << %(  <rect class="aw-grow" x="#{SVG.num(center - 4)}" y="#{SVG.num(BAR_BASE - bar_height)}" width="8" height="#{SVG.num(bar_height)}" rx="4" fill="#{bar_paint}" opacity="0.9" style="transform-origin:#{SVG.num(center)}px #{SVG.num(BAR_BASE)}px;animation-delay:#{SVG.num(index * 0.08)}s"/>\n)
          io << %(  <line x1="#{SVG.num(center - 14)}" y1="#{SVG.num(BAR_BASE + 6)}" x2="#{SVG.num(center + 14)}" y2="#{SVG.num(BAR_BASE + 6)}" #{faint_stroke(report)} stroke-width="1"/>\n)
        end
      end

      private def day_label(day : DayReport, today : Bool) : String
        today ? "Today" : day.date.day_of_week.to_s[0, 3]
      end

      private def overlay_color(report : WeatherReport, dark : Bool) : String
        # Pale skies quiet down with white, saturated ones with black.
        resolved_ink(report, dark).primary == Palettes::DARK_INK.primary ? "rgba(255,255,255,0.35)" : "rgba(6,16,28,0.16)"
      end

      private def overlay_paint(report : WeatherReport) : String
        mode.auto? ? %(class="aw-overlay") : %(fill="#{overlay_color(report, mode.dark?)}")
      end
    end
  end
end
