require "yaml"

module ActivityWeather
  enum ThemeMode
    Auto
    Light
    Dark
  end

  class PaletteOverride
    include YAML::Serializable
    include YAML::Serializable::Strict

    property background : String? = nil
    property text_color : String? = nil

    def initialize
    end
  end

  # The weather condition owns the sky — the gradient that fills the card —
  # so unlike a typical theme this one only decides the chrome around it:
  # what sits behind the rounded card, whether the palette is desaturated,
  # which of the day/dusk gradient sets a static mode uses, and the font.
  # Ink colors on top of the sky are chosen per condition (a pale snowy sky
  # needs dark text where a storm needs white) unless `text_color` forces one.
  class ThemeConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    # {light, dark} outer backgrounds per preset. "transparent" lets the
    # README's own background show through the card's rounded corners.
    PRESETS = {
      "github"   => {"transparent", "transparent"},
      "midnight" => {"#0b1021", "#0b1021"},
      "paper"    => {"#faf8f2", "#221f1a"},
      "mono"     => {"#ffffff", "#000000"},
    }

    # Colors land in a <style> block, so restrict them to a safe subset.
    SAFE_COLOR = /\A[#a-zA-Z0-9(),.%\- ]+\z/

    property preset : String = "github"
    property mode : ThemeMode = ThemeMode::Auto
    property background : String? = nil
    # Forces the ink everywhere; nil lets each condition pick a legible one.
    property text_color : String? = nil
    property dark : PaletteOverride = PaletteOverride.new
    property font_family : String = "-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

    def initialize
    end

    # The mono preset trades the condition skies for a neutral ramp — the
    # icon accent is the only color that survives.
    def mono? : Bool
      preset == "mono"
    end

    def light_background : String
      background || PRESETS[preset]?.try(&.first) || "transparent"
    end

    def dark_background : String
      dark.background || background || PRESETS[preset]?.try(&.last) || "transparent"
    end

    def light_text : String?
      text_color
    end

    def dark_text : String?
      dark.text_color || text_color
    end

    def validate : Array(String)
      errors = [] of String
      unless PRESETS.has_key?(preset)
        errors << "unknown theme `preset`: #{preset} (known: #{PRESETS.keys.join(", ")})"
      end
      {light_background, dark_background, light_text, dark_text}.each do |color|
        next unless color
        errors << "theme color contains unsafe characters: #{color.inspect}" unless color.matches?(SAFE_COLOR)
      end
      errors.uniq
    end
  end
end
