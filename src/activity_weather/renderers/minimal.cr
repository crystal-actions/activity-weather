module ActivityWeather
  module Renderers
    # A 28px pill badge for inline README use: tiny icon plus
    # "sunny · 24°" on the condition gradient. Width follows the label.
    class Minimal < Renderer
      HEIGHT    = 28.0
      FONT_SIZE = 12.0

      protected def size(report : WeatherReport) : {Float64, Float64}
        {10.0 + 16.0 + 7.0 + text_width(label(report), FONT_SIZE) + 12.0, HEIGHT}
      end

      protected def body(io : String::Builder, report : WeatherReport) : Nil
        width = last_size[0]
        io << %(  <rect x="0.5" y="0.5" width="#{SVG.num(width - 1)}" height="#{SVG.num(HEIGHT - 1)}" rx="13.5" fill="url(#aw-sky)" #{faint_stroke(report)}/>\n)
        WeatherIcons.use(io, report.condition, 8, 6, 16)
        io << %(  <text x="31" y="19" font-family="#{font}" font-size="#{SVG.num(FONT_SIZE)}" font-weight="600" #{ink_paint(report)}>#{SVG.escape(label(report))}</text>\n)
      end

      private def label(report : WeatherReport) : String
        "#{report.condition.key.split('_').join(' ')} · #{format_temp(report.temperature)}"
      end
    end
  end
end
