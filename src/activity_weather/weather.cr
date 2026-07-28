module ActivityWeather
  enum Condition
    Sunny
    PartlyCloudy
    Cloudy
    Rainy
    Stormy
    Foggy
    Snowy
    Windy
    Rainbow
    Aurora

    # The name used in config keys, action outputs, and CSS classes:
    # `PartlyCloudy` → "partly_cloudy".
    def key : String
      to_s.underscore
    end

    def self.keys : Array(String)
      values.map(&.key)
    end
  end

  # Whether the current window is busier than the one before it.
  enum Trend
    Rising
    Steady
    Falling
  end

  record DayReport,
    date : Time,
    condition : Condition,
    # 0..40 like the main reading; drives the mini bars in the forecast strip.
    temperature : Float64

  record WeatherReport,
    condition : Condition,
    # Activity level on a 0–40 °C scale.
    temperature : Float64,
    # Churn (things opened and closed) on a 0–60 km/h scale.
    wind : Int32,
    # Backlog pressure: share of opened among opened+closed, 0–100 %.
    humidity : Int32,
    pressure : Trend,
    phrase : String,
    repo : String,
    period_days : Int32,
    metrics : Metrics,
    daily : Array(DayReport),
    truncated : Bool do
    def period_label : String
      Period.label(period_days)
    end
  end

  # One phrase per condition, overridable from the config for localization.
  # Deterministic on purpose: the same weather always says the same thing,
  # so golden files and cached READMEs do not churn.
  class PhraseBook
    DEFAULTS = {
      Condition::Sunny        => "Clear skies — commits are pouring in",
      Condition::PartlyCloudy => "Fair weather with a steady stream of commits",
      Condition::Cloudy       => "Overcast — things are ticking along quietly",
      Condition::Rainy        => "Issue showers — the backlog is filling up",
      Condition::Stormy       => "Storm warning — issues are rolling in fast",
      Condition::Foggy        => "Fog has settled in — barely a commit in sight",
      Condition::Snowy        => "Frozen over — the repository is hibernating",
      Condition::Windy        => "Gusty — plenty of churn, little landing",
      Condition::Rainbow      => "A rainbow after the storm — freshly released",
      Condition::Aurora       => "Aurora overhead — stargazers are flocking in",
    }

    def initialize(@overrides : Hash(String, String) = {} of String => String)
    end

    def phrase(condition : Condition, metrics : Metrics, repo : String) : String
      template = @overrides[condition.key]? || DEFAULTS[condition]
      template
        .gsub("{repo}", repo)
        .gsub("{commits}", metrics.commits.to_s)
        .gsub("{authors}", metrics.authors.to_s)
        .gsub("{issues}", metrics.issues_opened.to_s)
        .gsub("{prs}", metrics.prs_opened.to_s)
        .gsub("{stars}", metrics.stars_gained.to_s)
    end
  end
end
