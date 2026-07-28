module ActivityWeather
  # Condition icons as reusable <symbol>s in a 64x64 box, placed with <use>.
  # Geometry is shared — every cloud is the same primitives — and colors
  # reference the gradient defs the renderer emits (awg-cloud, awg-sun,
  # awg-storm), so one icon works in both theme modes. Stroke widths are
  # chosen to survive being scaled down to a 16px badge.
  #
  # Animation classes (aw-rays, aw-drop, …) are always present in the
  # markup; whether they move is decided entirely by the <style> block.
  module WeatherIcons
    # Emit one <symbol> per condition actually used in the document.
    def self.defs(io : String::Builder, conditions : Enumerable(Condition)) : Nil
      conditions.to_a.uniq.sort_by!(&.value).each do |condition|
        io << %(    <symbol id="aw-i-#{condition.key}" viewBox="0 0 64 64">\n)
        draw(io, condition)
        io << "    </symbol>\n"
      end
    end

    def self.use(io : String::Builder, condition : Condition,
                 x : Float64 | Int32, y : Float64 | Int32, size : Float64 | Int32) : Nil
      io << %(  <use href="#aw-i-#{condition.key}" x="#{SVG.num(x)}" y="#{SVG.num(y)}" width="#{SVG.num(size)}" height="#{SVG.num(size)}"/>\n)
    end

    private def self.draw(io : String::Builder, condition : Condition) : Nil
      case condition
      in .sunny?         then sunny(io)
      in .partly_cloudy? then partly_cloudy(io)
      in .cloudy?        then cloudy(io)
      in .rainy?         then rainy(io)
      in .stormy?        then stormy(io)
      in .foggy?         then foggy(io)
      in .snowy?         then snowy(io)
      in .windy?         then windy(io)
      in .rainbow?       then rainbow(io)
      in .aurora?        then aurora(io)
      end
    end

    private def self.sunny(io) : Nil
      rays(io, scale: 1.0)
      io << %(      <circle class="aw-sun-core" cx="32" cy="32" r="15" fill="url(#awg-sun)"/>\n)
    end

    # Eight rays from r=21 to r=29 around the core.
    private def self.rays(io, scale : Float64) : Nil
      io << %(      <g class="aw-rays" stroke="#FFC53D" stroke-width="#{SVG.num(4.5 * scale)}" stroke-linecap="round">\n)
      8.times do |index|
        angle = index * Math::PI / 4
        x1 = 32 + 21 * scale * Math.cos(angle)
        y1 = 32 + 21 * scale * Math.sin(angle)
        x2 = 32 + 29 * scale * Math.cos(angle)
        y2 = 32 + 29 * scale * Math.sin(angle)
        io << %(        <line x1="#{SVG.num(x1)}" y1="#{SVG.num(y1)}" x2="#{SVG.num(x2)}" y2="#{SVG.num(y2)}"/>\n)
      end
      io << "      </g>\n"
    end

    # A fluffy cloud from overlapping primitives (fill-only, so the seams
    # vanish). Footprint roughly x 7..56, y 17..51 before transform. Public:
    # the banner scene builds its cloud layers from the same shape.
    def self.cloud(io, transform : String? = nil, fill : String = "url(#awg-cloud)",
                   opacity : Float64 = 1.0, cls : String = "aw-cloud") : Nil
      io << %(      <g class="#{cls}")
      io << %( transform="#{transform}") if transform
      io << %( fill="#{fill}")
      io << %( opacity="#{SVG.num(opacity)}") if opacity < 1.0
      io << ">\n"
      io << %(        <circle cx="19" cy="40" r="11"/>\n)
      io << %(        <circle cx="33" cy="31" r="14"/>\n)
      io << %(        <circle cx="45" cy="40" r="10"/>\n)
      io << %(        <rect x="14" y="36" width="42" height="15" rx="7.5"/>\n)
      io << "      </g>\n"
    end

    private def self.partly_cloudy(io) : Nil
      io << %(      <g transform="translate(16,-8) scale(0.72)">\n)
      rays(io, scale: 0.9)
      io << %(        <circle cx="32" cy="32" r="14" fill="url(#awg-sun)"/>\n)
      io << "      </g>\n"
      cloud(io, transform: "translate(-2,10) scale(0.92)")
    end

    private def self.cloudy(io) : Nil
      cloud(io, transform: "translate(10,-7) scale(0.72)", opacity: 0.55, cls: "aw-cloud-back")
      cloud(io, transform: "translate(-1,6) scale(0.95)")
    end

    private def self.rainy(io) : Nil
      drops(io)
      cloud(io, transform: "translate(1,-5) scale(0.95)")
    end

    # Three round-capped streaks, staggered so they fall out of phase.
    private def self.drops(io, color : String = "#4FC3F7") : Nil
      [{22, "aw-d1"}, {32, "aw-d2"}, {42, "aw-d3"}].each do |(x, cls)|
        io << %(      <line class="aw-drop #{cls}" x1="#{x}" y1="46" x2="#{x - 3}" y2="54" stroke="#{color}" stroke-width="3.5" stroke-linecap="round"/>\n)
      end
    end

    private def self.stormy(io) : Nil
      io << %(      <line class="aw-drop aw-d1" x1="20" y1="45" x2="17" y2="52" stroke="#4FC3F7" stroke-width="3.5" stroke-linecap="round"/>\n)
      io << %(      <line class="aw-drop aw-d3" x1="46" y1="45" x2="43" y2="52" stroke="#4FC3F7" stroke-width="3.5" stroke-linecap="round"/>\n)
      cloud(io, transform: "translate(1,-7) scale(0.95)", fill: "url(#awg-storm)")
      io << %(      <path class="aw-bolt" d="M34 36 L25 50 h6 L27 62 L41 46 h-7 l6 -10 z" fill="#FFD93D"/>\n)
    end

    private def self.foggy(io) : Nil
      cloud(io, transform: "translate(2,-10) scale(0.88)", opacity: 0.75)
      io << %(      <g stroke="#AEBBC9" stroke-width="4.5" stroke-linecap="round">\n)
      io << %(        <line class="aw-fog-a" x1="14" y1="47" x2="46" y2="47"/>\n)
      io << %(        <line class="aw-fog-b" x1="20" y1="54" x2="52" y2="54"/>\n)
      io << %(        <line class="aw-fog-a" x1="12" y1="61" x2="38" y2="61"/>\n)
      io << "      </g>\n"
    end

    private def self.snowy(io) : Nil
      flakes(io)
      cloud(io, transform: "translate(1,-6) scale(0.92)")
    end

    # Six-armed flakes: three strokes crossing at 60°.
    private def self.flakes(io, color : String = "#DDEBFF") : Nil
      [{21, 50, "aw-f1"}, {33, 55, "aw-f2"}, {44, 49, "aw-f3"}].each do |(x, y, cls)|
        io << %(      <g class="aw-flake #{cls}" transform="translate(#{x},#{y})" stroke="#{color}" stroke-width="1.7" stroke-linecap="round">\n)
        io << %(        <path d="M-4 0H4M-2 -3.46L2 3.46M-2 3.46L2 -3.46"/>\n)
        io << "      </g>\n"
      end
    end

    private def self.windy(io) : Nil
      io << %(      <g fill="none" stroke="#EAF7FB" stroke-linecap="round" stroke-width="4">\n)
      io << %(        <path class="aw-wind aw-w1" d="M6 26 h29 a5.5 5.5 0 1 0 -5.5 -9" opacity="0.95"/>\n)
      io << %(        <path class="aw-wind aw-w2" d="M6 37 h38 a6 6 0 1 1 -6 10" opacity="0.7"/>\n)
      io << %(        <path class="aw-wind aw-w3" d="M6 48 h21" opacity="0.45"/>\n)
      io << "      </g>\n"
    end

    private def self.rainbow(io) : Nil
      io << %(      <g fill="none" stroke-width="3.6" stroke-linecap="round" class="aw-arc" opacity="0.92">\n)
      Palettes::RAINBOW_ARCS.each_with_index do |color, index|
        radius = 27 - index * 4.5
        io << %(        <path d="M#{SVG.num(32 - radius)} 46 A#{SVG.num(radius)} #{SVG.num(radius)} 0 0 1 #{SVG.num(32 + radius)} 46" stroke="#{color}"/>\n)
      end
      io << "      </g>\n"
      cloud(io, transform: "translate(-9,28) scale(0.5)")
      cloud(io, transform: "translate(30,32) scale(0.42)")
    end

    private def self.aurora(io) : Nil
      [{0, "aw-r1"}, {12, "aw-r2"}, {24, "aw-r3"}].each_with_index do |(dx, cls), index|
        color = Palettes::AURORA_RIBBONS[index]
        io << %(      <path class="aw-ribbon #{cls}" d="M#{16 + dx} 56 C#{10 + dx} 42 #{22 + dx} 34 #{17 + dx} 18" fill="none" stroke="#{color}" stroke-width="6" stroke-linecap="round" opacity="0.78"/>\n)
      end
      io << %(      <g fill="#E9F5FF">\n)
      io << %(        <circle class="aw-star aw-t1" cx="8" cy="12" r="1.4"/>\n)
      io << %(        <circle class="aw-star aw-t2" cx="52" cy="8" r="1.1"/>\n)
      io << %(        <circle class="aw-star aw-t3" cx="58" cy="24" r="1.3"/>\n)
      io << "      </g>\n"
    end
  end
end
