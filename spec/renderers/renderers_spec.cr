require "../spec_helper"
require "../support/factories"
require "../support/golden"

private def render(style : ActivityWeather::Style, report : ActivityWeather::WeatherReport,
                   yaml : String = "{}") : String
  config = ActivityWeather::Config.parse(yaml)
  ActivityWeather::Renderer.for(style, config).render(report)
end

alias Style = ActivityWeather::Style
alias Weather = ActivityWeather::Condition

describe ActivityWeather::Renderer do
  it "renders the same report to identical bytes" do
    report = Factory.report
    first = render(Style::Card, report)
    second = render(Style::Card, report)
    first.should eq(second)
  end

  it "gives different repositories different seeded scenery" do
    sunny = Factory.report(condition: Weather::Snowy)
    other = Factory.report(condition: Weather::Snowy, repo: "octo/another")
    a = render(Style::Banner, sunny)
    b = render(Style::Banner, other)
    a.should_not eq(b)
  end

  it "reports the document size through last_size" do
    config = ActivityWeather::Config.empty
    renderer = ActivityWeather::Renderer.for(Style::Card, config)
    renderer.render(Factory.report)
    renderer.last_size.should eq({480.0, 240.0})
  end

  it "omits every animation rule when animated is off" do
    svg = render(Style::Card, Factory.report, "animated: false")
    svg.should_not contain("@keyframes")
    svg.should_not contain("animation")
  end

  it "escapes repository names and phrases" do
    report = Factory.report(repo: "octo/<svg>", phrase: %(a "quoted" <phrase>))
    svg = render(Style::Card, report)
    svg.should_not contain("<svg>>")
    svg.should contain("&lt;svg&gt;")
    svg.should contain("&lt;phrase&gt;")
  end

  it "inlines colors in static modes and classes in auto" do
    auto = render(Style::Card, Factory.report)
    auto.should contain(%(class="aw-ink"))
    auto.should contain("prefers-color-scheme")

    dark = render(Style::Card, Factory.report, "theme:\n  mode: dark")
    dark.should_not contain(%(class="aw-ink"))
    dark.should contain(%(stop-color="#12295C"))
  end

  describe "golden files" do
    it "card, one per representative condition" do
      Golden.assert("card_sunny.svg", render(Style::Card, Factory.report))
      Golden.assert("card_stormy_dark.svg", render(
        Style::Card,
        Factory.report(condition: Weather::Stormy, temperature: 18.0, pressure: ActivityWeather::Trend::Falling,
          phrase: "Storm warning — issues are rolling in fast"),
        "theme:\n  mode: dark"))
      Golden.assert("card_snowy_light.svg", render(
        Style::Card,
        Factory.report(condition: Weather::Snowy, temperature: 2.0, wind: 0, humidity: 50,
          phrase: "Frozen over — the repository is hibernating",
          metrics: Factory.metrics),
        "theme:\n  mode: light"))
      Golden.assert("card_rainbow_static.svg", render(
        Style::Card,
        Factory.report(condition: Weather::Rainbow, phrase: "A rainbow after the storm — freshly released"),
        "animated: false"))
      Golden.assert("card_aurora.svg", render(
        Style::Card,
        Factory.report(condition: Weather::Aurora, phrase: "Aurora overhead — stargazers are flocking in",
          metrics: Factory.metrics(commits: 40, stars_gained: 180, authors: 4))))
    end

    it "forecast with a mixed week" do
      Golden.assert("forecast_week.svg", render(
        Style::Forecast,
        Factory.report(condition: Weather::PartlyCloudy, daily: Factory.week)))
    end

    it "banner scenes" do
      Golden.assert("banner_sunny.svg", render(Style::Banner, Factory.report))
      Golden.assert("banner_stormy_dark.svg", render(
        Style::Banner,
        Factory.report(condition: Weather::Stormy, temperature: 18.0,
          phrase: "Storm warning — issues are rolling in fast"),
        "theme:\n  mode: dark"))
      Golden.assert("banner_foggy.svg", render(
        Style::Banner,
        Factory.report(condition: Weather::Foggy, temperature: 4.0, wind: 2,
          phrase: "Fog has settled in — barely a commit in sight")))
    end

    it "terminal readout" do
      Golden.assert("terminal_rainy.svg", render(
        Style::Terminal,
        Factory.report(condition: Weather::Rainy, temperature: 16.0, humidity: 78,
          phrase: "Issue showers — the backlog is filling up")))
    end

    it "minimal badges" do
      Golden.assert("minimal_sunny.svg", render(Style::Minimal, Factory.report))
      Golden.assert("minimal_windy_dark.svg", render(
        Style::Minimal,
        Factory.report(condition: Weather::Windy, temperature: 12.0),
        "theme:\n  mode: dark"))
    end
  end
end
