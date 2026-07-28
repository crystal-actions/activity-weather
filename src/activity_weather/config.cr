require "yaml"

module ActivityWeather
  class ConfigError < Exception
    getter line : Int32?

    def initialize(message : String, @line : Int32? = nil)
      super(message)
    end
  end

  enum Style
    Card
    Forecast
    Banner
    Terminal
    Minimal
  end

  # Accepts `sunny_temp: 25` as well as `sunny_temp: 25.5`; YAML's Float64
  # converter rejects bare integers, which reads as a bug to anyone writing
  # a round number.
  module NumberConverter
    def self.from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : Float64
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected a number"
      end
      node.value.to_f64? || node.raise("Expected a number, not #{node.value.inspect}")
    end

    def self.to_yaml(value : Float64, yaml : YAML::Nodes::Builder) : Nil
      value.to_yaml(yaml)
    end
  end

  class Config
    include YAML::Serializable
    include YAML::Serializable::Strict

    DEFAULT_OUTPUT = "ACTIVITY_WEATHER.svg"

    property repo : String? = nil
    property period : String = Period::DEFAULT
    property style : Style = Style::Card
    property output : String = DEFAULT_OUTPUT
    property outputs : Array(OutputEntry)? = nil
    property? animated : Bool = true
    property forecast : ForecastConfig = ForecastConfig.new
    property metrics : MetricsConfig = MetricsConfig.new
    property thresholds : Thresholds = Thresholds.new
    # Condition key → phrase template, e.g. `sunny: "쾌청 — 커밋 {commits}건"`.
    property messages : Hash(String, String) = {} of String => String
    property title : String? = nil
    property theme : ThemeConfig = ThemeConfig.new

    def self.empty : Config
      parse("{}")
    end

    # An absent file is an error only when the path was asked for by name;
    # the default path is a convention, and not using it is the zero-config
    # case, not a mistake.
    def self.load(path : String, explicit : Bool = true) : Config
      unless File.exists?(path)
        raise ConfigError.new("config file not found: #{path}") if explicit
        return empty
      end
      config = parse(File.read(path))
      config.validate!
      config
    end

    def self.parse(yaml : String) : Config
      from_yaml(yaml)
    rescue ex : YAML::ParseException
      raise ConfigError.new("invalid config: #{friendly_parse_error(ex.message)}", ex.line_number)
    end

    # Crystal reports enum failures with its own type names ("Unknown enum
    # ActivityWeather::Style value: \"crad\""). Rewrite those into the
    # field's vocabulary, listing what is actually accepted.
    private def self.friendly_parse_error(message : String?) : String
      return "could not be parsed" unless message

      match = message.match(/Unknown enum ActivityWeather::(\w+) value: (".*?")/)
      return message unless match

      values =
        case match[1]
        when "Style"     then Style.names
        when "ThemeMode" then ThemeMode.names
        else                  [] of String
        end
      return message if values.empty?
      # Name the version: this list is authoritative only for the build that
      # printed it, and a stale image rejecting a style that does exist is
      # exactly the error that reads as "your config is wrong".
      "unknown value #{match[2]} (expected one of: #{values.map(&.underscore).join(", ")}) " \
      "— reported by activity-weather v#{VERSION}"
    end

    def period_days : Int32
      Period.parse_days(period)
    end

    def phrase_book : PhraseBook
      PhraseBook.new(messages)
    end

    # The (path, style, mode override) tuples to render: the `outputs` array
    # when present, otherwise the single `output`/`style` pair.
    def render_targets : Array({String, Style, ThemeMode?})
      if entries = outputs
        entries.map { |entry| {entry.path, entry.style || style, entry.mode} }
      else
        [{output, style, nil.as(ThemeMode?)}]
      end
    end

    def validate! : Nil
      errors = [] of String

      if (name = repo) && !name.matches?(%r{\A[\w.\-]+/[\w.\-]+\z})
        errors << "`repo` must be an owner/name pair: #{name.inspect}"
      end

      begin
        period_days
      rescue ex : ConfigError
        errors << (ex.message || "invalid `period`")
      end

      validate_outputs(errors)
      validate_messages(errors)

      if (heading = title) && heading.matches?(/[\x00-\x1f]/)
        errors << "`title` must not contain control characters"
      end

      errors.concat(forecast.validate)
      errors.concat(thresholds.validate)
      errors.concat(theme.validate)

      raise ConfigError.new(errors.join("; ")) unless errors.empty?
    end

    private def validate_outputs(errors : Array(String)) : Nil
      if (entries = outputs) && entries.empty?
        errors << "`outputs` must not be empty — remove it to use `output` instead"
      end
      if outputs && output != DEFAULT_OUTPUT
        errors << "`output` is ignored when `outputs` is set — keep only one of them"
      end

      paths = render_targets.map(&.first)
      paths.each { |path| validate_output_path(path, errors) }
      errors << "duplicate output paths" if paths.uniq.size != paths.size
    end

    private def validate_output_path(path : String, errors : Array(String)) : Nil
      if path.strip.empty?
        errors << "output path must not be empty"
      elsif !path.ends_with?(".svg")
        errors << "output path must end with .svg: #{path}"
      end
      if path.starts_with?('/') || Path[path].parts.includes?("..")
        errors << "output path must be relative to the repository: #{path}"
      end
      if path.matches?(/[\x00-\x1f]/)
        errors << "output path must not contain control characters: #{path.inspect}"
      end
    end

    private def validate_messages(errors : Array(String)) : Nil
      known = Condition.keys
      messages.each do |key, value|
        unless known.includes?(key)
          errors << "unknown `messages` key: #{key.inspect} (conditions: #{known.join(", ")})"
        end
        if value.matches?(/[\x00-\x1f]/)
          errors << "message for #{key} must not contain control characters"
        end
      end
    end
  end

  class OutputEntry
    include YAML::Serializable
    include YAML::Serializable::Strict

    property path : String
    property style : Style? = nil
    # Per-output theme mode override, e.g. a light/dark pair for
    # `#gh-light-mode-only` / `#gh-dark-mode-only` README links.
    property mode : ThemeMode? = nil
  end

  class ForecastConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    # Trailing calendar days drawn in forecast-style renders; 0 hides the
    # strip entirely.
    property days : Int32 = 7

    def initialize
    end

    def validate : Array(String)
      errors = [] of String
      errors << "forecast `days` must be between 0 and 14" unless (0..14).includes?(days)
      errors
    end
  end

  class MetricsConfig
    include YAML::Serializable
    include YAML::Serializable::Strict

    # Each false skips the corresponding fetch and reports the count as 0 —
    # for repositories where those endpoints are noise or rate-limit budget.
    property? stars : Bool = true
    property? releases : Bool = true

    def initialize
    end
  end

  # Where the condition decision tree draws its lines. Every value has a
  # spec on both sides of it, so tune with `spec/meteorologist_spec.cr` open.
  class Thresholds
    include YAML::Serializable
    include YAML::Serializable::Strict

    @[YAML::Field(converter: ActivityWeather::NumberConverter)]
    property sunny_temp : Float64 = 25.0
    @[YAML::Field(converter: ActivityWeather::NumberConverter)]
    property storm_issues_per_day : Float64 = 3.0
    @[YAML::Field(converter: ActivityWeather::NumberConverter)]
    property fog_points_per_day : Float64 = 1.0
    property rain_humidity : Int32 = 70
    property windy_wind : Int32 = 25
    @[YAML::Field(converter: ActivityWeather::NumberConverter)]
    property aurora_stars_per_day : Float64 = 10.0
    @[YAML::Field(converter: ActivityWeather::NumberConverter)]
    property rainbow_min_temp : Float64 = 15.0

    def initialize
    end

    def validate : Array(String)
      errors = [] of String
      errors << "thresholds `sunny_temp` must be between 0 and 40" unless (0.0..40.0).includes?(sunny_temp)
      errors << "thresholds `storm_issues_per_day` must be positive" unless storm_issues_per_day > 0
      errors << "thresholds `fog_points_per_day` must be >= 0" if fog_points_per_day < 0
      errors << "thresholds `rain_humidity` must be between 0 and 100" unless (0..100).includes?(rain_humidity)
      errors << "thresholds `windy_wind` must be between 0 and 60" unless (0..60).includes?(windy_wind)
      errors << "thresholds `aurora_stars_per_day` must be positive" unless aurora_stars_per_day > 0
      errors << "thresholds `rainbow_min_temp` must be between 0 and 40" unless (0.0..40.0).includes?(rainbow_min_temp)
      errors
    end
  end
end
