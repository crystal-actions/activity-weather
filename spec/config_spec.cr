require "./spec_helper"

private def load_fixture(name : String) : ActivityWeather::Config
  ActivityWeather::Config.load(SpecHelper.fixture("configs", name))
end

describe ActivityWeather::Config do
  it "provides working defaults from an empty document" do
    config = ActivityWeather::Config.empty
    config.validate!
    config.period_days.should eq(7)
    config.style.should eq(ActivityWeather::Style::Card)
    config.animated?.should be_true
    config.forecast.days.should eq(7)
    config.metrics.stars?.should be_true
    config.render_targets.should eq([{"ACTIVITY_WEATHER.svg", ActivityWeather::Style::Card, nil}])
  end

  it "loads a full config with every knob turned" do
    config = load_fixture("full.yml")
    config.repo.should eq("crystal-actions/activity-weather")
    config.period_days.should eq(14)
    config.animated?.should be_false
    config.forecast.days.should eq(14)
    config.metrics.stars?.should be_false
    config.thresholds.sunny_temp.should eq(20.0)
    config.thresholds.storm_issues_per_day.should eq(5.5)
    config.messages["sunny"].should contain("쾌청")
    config.theme.preset.should eq("midnight")
    config.theme.mode.should eq(ActivityWeather::ThemeMode::Dark)
    config.render_targets.should eq([
      {"docs/weather.svg", ActivityWeather::Style::Banner, nil},
      {"docs/weather-dark.svg", ActivityWeather::Style::Banner, ActivityWeather::ThemeMode::Dark},
      {"docs/weather-badge.svg", ActivityWeather::Style::Minimal, nil},
    ])
  end

  it "returns an empty config for a missing default-path file, but errors when named" do
    missing = SpecHelper.fixture("configs", "does-not-exist.yml")
    ActivityWeather::Config.load(missing, explicit: false).period.should eq("7d")
    expect_raises(ActivityWeather::ConfigError, /not found/) do
      ActivityWeather::Config.load(missing)
    end
  end

  it "rejects unknown keys" do
    expect_raises(ActivityWeather::ConfigError, /perid/) do
      load_fixture("invalid_unknown_key.yml")
    end
  end

  it "rewrites enum errors into the field vocabulary with the version" do
    error = expect_raises(ActivityWeather::ConfigError) do
      load_fixture("invalid_style.yml")
    end
    error.message.to_s.should contain(%("crad"))
    error.message.to_s.should contain("card, forecast, banner, terminal, minimal")
    error.message.to_s.should contain("activity-weather v#{ActivityWeather::VERSION}")
  end

  it "collects validation errors instead of stopping at the first" do
    error = expect_raises(ActivityWeather::ConfigError) do
      load_fixture("invalid_thresholds.yml")
    end
    error.message.to_s.should contain("sunny_temp")
    error.message.to_s.should contain("rain_humidity")
  end

  it "validates the period through the same parser the runner uses" do
    expect_raises(ActivityWeather::ConfigError, /between 1 and 90/) do
      load_fixture("invalid_period.yml")
    end
  end

  it "rejects malformed repo values" do
    config = ActivityWeather::Config.parse("repo: not-a-pair")
    expect_raises(ActivityWeather::ConfigError, /owner\/name/) do
      config.validate!
    end
  end

  it "restricts output paths to relative .svg files" do
    {
      "output: weather.png"                     => /end with .svg/,
      "output: /abs/w.svg"                      => /relative/,
      "output: ../escape.svg"                   => /relative/,
      "outputs: []"                             => /must not be empty/,
      "output: a.svg\noutputs: [{path: b.svg}]" => /keep only one/,
      "outputs: [{path: a.svg}, {path: a.svg}]" => /duplicate/,
    }.each do |yaml, pattern|
      config = ActivityWeather::Config.parse(yaml)
      expect_raises(ActivityWeather::ConfigError, pattern) { config.validate! }
    end
  end

  it "rejects messages for unknown conditions" do
    config = ActivityWeather::Config.parse("messages:\n  drizzle: nope")
    error = expect_raises(ActivityWeather::ConfigError, /unknown `messages` key/) do
      config.validate!
    end
    error.message.to_s.should contain("partly_cloudy")
  end

  it "rejects unknown theme presets and unsafe colors" do
    config = ActivityWeather::Config.parse("theme:\n  preset: neon")
    expect_raises(ActivityWeather::ConfigError, /unknown theme `preset`/) { config.validate! }

    config = ActivityWeather::Config.parse("theme:\n  background: \"</style><script>\"")
    expect_raises(ActivityWeather::ConfigError, /unsafe characters/) { config.validate! }
  end

  it "accepts integers where thresholds take floats" do
    config = ActivityWeather::Config.parse("thresholds:\n  sunny_temp: 30")
    config.thresholds.sunny_temp.should eq(30.0)
  end
end

describe ActivityWeather::ThemeConfig do
  it "resolves preset backgrounds with overrides winning" do
    theme = ActivityWeather::ThemeConfig.from_yaml("preset: paper")
    theme.light_background.should eq("#faf8f2")
    theme.dark_background.should eq("#221f1a")

    theme = ActivityWeather::ThemeConfig.from_yaml("background: \"#123456\"\ndark:\n  background: \"#654321\"")
    theme.light_background.should eq("#123456")
    theme.dark_background.should eq("#654321")
  end

  it "lets the dark text override fall back to the shared one" do
    theme = ActivityWeather::ThemeConfig.from_yaml("text_color: \"#111111\"")
    theme.light_text.should eq("#111111")
    theme.dark_text.should eq("#111111")

    theme = ActivityWeather::ThemeConfig.from_yaml("text_color: \"#111111\"\ndark:\n  text_color: \"#eeeeee\"")
    theme.dark_text.should eq("#eeeeee")
  end
end
