module ActivityWeather
  module Renderers
    # 464x232 retro terminal in the wttr.in spirit: traffic-light title bar,
    # phosphor-toned monospace report, per-condition ASCII art in the accent
    # color, and a blinking prompt. Deliberately ignores the theme mode — a
    # terminal is dark in daylight too.
    class Terminal < Renderer
      WIDTH  = 464.0
      HEIGHT = 232.0

      BG     = "#0d1117"
      BORDER = "#30363d"
      BRIGHT = "#e6edf3"
      DIM    = "#8b949e"
      GREEN  = "#3fb950"

      FONT_SIZE  = 13.0
      CHAR_WIDTH =  7.8 # 0.6em advance
      LINE       = 19.0
      MARGIN     = 20.0
      ART_COLS   =   15
      MONO       = "ui-monospace, 'SF Mono', 'Cascadia Code', Menlo, Consolas, monospace"

      # Five rows, at most 14 columns, ASCII only — the art has to survive
      # any monospace font a viewer has.
      ART = {
        Condition::Sunny => [
          %q[   \   /],
          %q[    .-.],
          %q[ - (   ) -],
          %q[    `-'],
          %q[   /   \],
        ],
        Condition::PartlyCloudy => [
          %q[  \  /],
          %q[_ /"".-.],
          %q[  \_(   ).],
          %q[  /(___(__)],
          %q[],
        ],
        Condition::Cloudy => [
          %q[],
          %q[    .--.],
          %q[ .-(    ).],
          %q[(___.__)__)],
          %q[],
        ],
        Condition::Rainy => [
          %q[    .-.],
          %q[   (   ).],
          %q[  (___(__)],
          %q[   / / / /],
          %q[  / / / /],
        ],
        Condition::Stormy => [
          %q[    .-.],
          %q[   (   ).],
          %q[  (___(__)],
          %q[   _/ /_/],
          %q[   /_ /],
        ],
        Condition::Foggy => [
          %q[],
          %q[ _ - _ - _],
          %q[  _ - _ -],
          %q[ _ - _ - _],
          %q[],
        ],
        Condition::Snowy => [
          %q[    .-.],
          %q[   (   ).],
          %q[  (___(__)],
          %q[   *  *  *],
          %q[  *  *  *],
        ],
        Condition::Windy => [
          %q[],
          %q[ ~~~~~~>],
          %q[   ~~~~>],
          %q[ ~~~~~>],
          %q[],
        ],
        Condition::Rainbow => [
          %q[    _.-._],
          %q[  .'     '.],
          %q[ / .-'-. \],
          %q[  (___(__)],
          %q[],
        ],
        Condition::Aurora => [
          %q[ (  )  (  )],
          %q[  )  (  )],
          %q[ (  )  (  )],
          %q[   *    *],
          %q[ *    *   *],
        ],
      }

      protected def size(report : WeatherReport) : {Float64, Float64}
        {WIDTH, HEIGHT}
      end

      # Only the cursor blinks here; the shared condition animations target
      # icon geometry this style does not draw.
      protected def style_block(io : String::Builder, report : WeatherReport) : Nil
        return unless animated?
        css = Animations.css([] of Condition, ["cursor"])
        io << "  <style>" << css << "</style>\n" unless css.empty?
      end

      # No gradients, no icon symbols.
      protected def defs_block(io : String::Builder, report : WeatherReport) : Nil
      end

      protected def body(io : String::Builder, report : WeatherReport) : Nil
        io << %(  <rect x="0.5" y="0.5" width="#{SVG.num(WIDTH - 1)}" height="#{SVG.num(HEIGHT - 1)}" rx="10" fill="#{BG}" stroke="#{BORDER}"/>\n)
        title_bar(io, report)

        columns = ((WIDTH - MARGIN * 2) / CHAR_WIDTH).to_i
        repo = report.repo
        command = "$ activity-weather --repo #{repo} --period #{report.period_days}d"
        line(io, 1, 0.0, truncate_to_columns(command, columns), GREEN)

        art(io, report)
        readout(io, report, columns)

        prompt_y = row_y(9)
        line(io, 9, 0.0, "$", GREEN)
        io << %(  <rect class="aw-cursor" x="#{SVG.num(MARGIN + CHAR_WIDTH * 2)}" y="#{SVG.num(prompt_y - 11)}" width="#{SVG.num(CHAR_WIDTH)}" height="14" fill="#{GREEN}"/>\n)
      end

      private def title_bar(io : String::Builder, report : WeatherReport) : Nil
        [{20, "#ff5f56"}, {36, "#ffbd2e"}, {52, "#27c93f"}].each do |(x, color)|
          io << %(  <circle cx="#{x}" cy="17" r="5" fill="#{color}"/>\n)
        end
        title = truncate_to_columns("~/#{report.repo.split('/').last} — weather", 40)
        io << %(  <text x="#{SVG.num(WIDTH / 2)}" y="21" text-anchor="middle" font-family="#{MONO}" font-size="11" fill="#{DIM}">#{SVG.escape(title)}</text>\n)
        io << %(  <line x1="1" y1="32" x2="#{SVG.num(WIDTH - 1)}" y2="32" stroke="#{BORDER}"/>\n)
      end

      private def art(io : String::Builder, report : WeatherReport) : Nil
        color = condition_palette(report).accent
        ART[report.condition].each_with_index do |row, index|
          next if row.empty?
          line(io, index + 3, 0.0, row, color, bold: true)
        end
      end

      private def readout(io : String::Builder, report : WeatherReport, columns : Int32) : Nil
        left = ART_COLS.to_f
        width = columns - ART_COLS

        condition = report.condition.key.split('_').join(' ')
        line(io, 3, left, "#{format_temp(report.temperature)}  #{condition} #{trend_glyph(report.pressure)}", BRIGHT, bold: true)
        line(io, 4, left, truncate_to_columns(report.phrase, width), DIM)
        pairs(io, 6, left, {"commits", format_count(report.metrics.commits)}, {"prs", format_count(report.metrics.prs_opened)})
        pairs(io, 7, left, {"issues", format_count(report.metrics.issues_opened)}, {"stars", "+#{format_count(report.metrics.stars_gained)}"})
        line(io, 8, left, "wind #{report.wind} km/h   humidity #{report.humidity}%", DIM)
      end

      # `commits 128    prs 12` with dim labels and bright values.
      private def pairs(io : String::Builder, row : Int32, column : Float64,
                        first : {String, String}, second : {String, String}) : Nil
        x = MARGIN + column * CHAR_WIDTH
        gap = (13 - first[0].size - first[1].size).clamp(2, 13)
        io << %(  <text x="#{SVG.num(x)}" y="#{SVG.num(row_y(row))}" font-family="#{MONO}" font-size="#{SVG.num(FONT_SIZE)}" fill="#{DIM}" xml:space="preserve">#{first[0]} <tspan fill="#{BRIGHT}">#{SVG.escape(first[1])}</tspan>#{" " * gap}#{second[0]} <tspan fill="#{BRIGHT}">#{SVG.escape(second[1])}</tspan></text>\n)
      end

      private def line(io : String::Builder, row : Int32, column : Float64, text : String,
                       color : String, bold : Bool = false) : Nil
        return if text.empty?
        x = MARGIN + column * CHAR_WIDTH
        weight = bold ? %( font-weight="600") : ""
        io << %(  <text x="#{SVG.num(x)}" y="#{SVG.num(row_y(row))}" font-family="#{MONO}" font-size="#{SVG.num(FONT_SIZE)}"#{weight} fill="#{color}" xml:space="preserve">#{SVG.escape(text)}</text>\n)
      end

      private def row_y(row : Int32) : Float64
        36.0 + row * LINE
      end

      private def truncate_to_columns(text : String, columns : Int32) : String
        return text if text.size <= columns
        "#{text[0, Math.max(columns - 1, 1)]}…"
      end

      private def format_count(value : Int32) : String
        return value.to_s if value < 1000
        "#{(value / 1000.0).round(1)}k"
      end
    end
  end
end
