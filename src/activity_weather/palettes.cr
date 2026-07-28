module ActivityWeather
  # Text colors that sit on top of a condition sky.
  record Ink,
    primary : String,
    secondary : String,
    faint : String

  # The sky for one condition: {top, bottom} gradient stops for the light
  # (day) and dark (dusk) palettes, the icon accent, and whether the light
  # sky is pale enough to need dark ink.
  record ConditionPalette,
    light : {String, String},
    dark : {String, String},
    accent : String,
    dark_ink_on_light : Bool

  # The condition owns the sky; the theme only decides day vs dusk and
  # whether the whole thing is desaturated (mono preset).
  module Palettes
    WHITE_INK = Ink.new("#ffffff", "rgba(255,255,255,0.78)", "rgba(255,255,255,0.28)")
    DARK_INK  = Ink.new("#243140", "rgba(36,49,64,0.76)", "rgba(36,49,64,0.24)")

    # Light skies stay saturated enough for white ink except where the
    # weather itself is pale — fog and snow read wrong when vivid.
    TABLE = {
      Condition::Sunny        => ConditionPalette.new({"#3D8FD6", "#7EC3F0"}, {"#12295C", "#3A5FA0"}, "#FFB020", false),
      Condition::PartlyCloudy => ConditionPalette.new({"#5B8FC7", "#8FB8DC"}, {"#1B2A47", "#45608A"}, "#F5C453", false),
      Condition::Cloudy       => ConditionPalette.new({"#6B7E93", "#9AA9BA"}, {"#232C3A", "#48566B"}, "#AAB8C8", false),
      Condition::Rainy        => ConditionPalette.new({"#4E6478", "#7A8FA3"}, {"#1A2430", "#3A4A5C"}, "#4FC3F7", false),
      Condition::Stormy       => ConditionPalette.new({"#39445A", "#5C6C85"}, {"#12161F", "#2C3646"}, "#FFD93D", false),
      Condition::Foggy        => ConditionPalette.new({"#9AA5B1", "#C6CDD5"}, {"#252A31", "#4A525C"}, "#C3CCD4", true),
      Condition::Snowy        => ConditionPalette.new({"#8FA9C9", "#D6E4F2"}, {"#1E2B40", "#3E5471"}, "#DDEBFF", true),
      Condition::Windy        => ConditionPalette.new({"#4193BE", "#7FC4DC"}, {"#173044", "#3A5E77"}, "#8FD6C7", false),
      Condition::Rainbow      => ConditionPalette.new({"#3D8FD6", "#8FD0F5"}, {"#12295C", "#3A5FA0"}, "#FFB020", false),
      # The aurora happens at night in either theme.
      Condition::Aurora => ConditionPalette.new({"#0B1D3A", "#16436B"}, {"#081426", "#103352"}, "#46E8A0", false),
    }

    MONO_LIGHT = {"#f2f5f8", "#e2e8ee"}
    MONO_DARK  = {"#1b2129", "#10151b"}

    # The five rainbow arc colors and the three aurora ribbon colors, shared
    # by icons and scene layers.
    RAINBOW_ARCS   = ["#FF5E5B", "#FFB400", "#7ED957", "#38B6FF", "#8C52FF"]
    AURORA_RIBBONS = ["#46E8A0", "#5BC0EB", "#9B5DE5"]

    # Cloud body gradients per mode; the icon geometry stays identical.
    CLOUD_LIGHT = {"#ffffff", "#d7dee8"}
    CLOUD_DARK  = {"#b8c4d4", "#8494ac"}
    STORM_CLOUD = {"#7A8699", "#56637A"}

    def self.for(condition : Condition, mono : Bool = false) : ConditionPalette
      base = TABLE[condition]
      return base unless mono
      ConditionPalette.new(MONO_LIGHT, MONO_DARK, base.accent, true)
    end

    def self.ink(palette : ConditionPalette, dark : Bool) : Ink
      return WHITE_INK if dark
      palette.dark_ink_on_light ? DARK_INK : WHITE_INK
    end
  end
end
