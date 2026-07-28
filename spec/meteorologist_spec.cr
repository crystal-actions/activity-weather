require "./spec_helper"
require "./support/factories"

alias Meteo = ActivityWeather::Meteorologist
alias Cond = ActivityWeather::Condition

private DEFAULTS = ActivityWeather::Thresholds.new

private def condition(metrics, repo = Factory.repo, thresholds = DEFAULTS) : Cond
  Meteo.condition_for(metrics, repo, thresholds)
end

describe ActivityWeather::Meteorologist do
  describe ".temperature" do
    it "is 0 for a dead week and saturates at 40" do
      Meteo.temperature(ActivityWeather::Metrics.zero(7)).should eq(0.0)
      Meteo.temperature(Factory.metrics(commits: 700, authors: 20)).should eq(40.0)
    end

    it "reads a steady hobby project as warm, not cold" do
      # One commit a day from one person: ~1.7 points/day.
      temp = Meteo.temperature(Factory.metrics(commits: 7, authors: 1))
      temp.should be > 10.0
      temp.should be < 20.0
    end
  end

  describe ".humidity" do
    it "is the opened share of opened+closed, and 50 in still air" do
      Meteo.humidity(ActivityWeather::Metrics.zero(7)).should eq(50)
      Meteo.humidity(Factory.metrics(issues_opened: 3, issues_closed: 1)).should eq(75)
      Meteo.humidity(Factory.metrics(prs_opened: 1, prs_merged: 3)).should eq(25)
    end
  end

  describe ".trend" do
    it "compares the current window against the previous one" do
      busy = Factory.metrics(commits: 20, authors: 2)
      quiet = Factory.metrics(commits: 5, authors: 1)
      Meteo.trend(busy, quiet).should eq(ActivityWeather::Trend::Rising)
      Meteo.trend(quiet, busy).should eq(ActivityWeather::Trend::Falling)
      Meteo.trend(busy, busy).should eq(ActivityWeather::Trend::Steady)
      Meteo.trend(ActivityWeather::Metrics.zero(7), ActivityWeather::Metrics.zero(7))
        .should eq(ActivityWeather::Trend::Steady)
    end
  end

  describe ".condition_for" do
    it "calls aurora on a star surge, on both sides of the line" do
      condition(Factory.metrics(stars_gained: 70)).should eq(Cond::Aurora)
      condition(Factory.metrics(stars_gained: 69)).should_not eq(Cond::Aurora)
    end

    it "paints a rainbow after a release in a busy week, but not a cold one" do
      busy_release = Factory.metrics(releases: 1, commits: 20, authors: 2)
      condition(busy_release).should eq(Cond::Rainbow)
      # A release into silence is not a celebration-grade week.
      condition(Factory.metrics(releases: 1)).should eq(Cond::PartlyCloudy)
    end

    it "declares a storm when issues flood in faster than they close" do
      storm = Factory.metrics(issues_opened: 21, issues_closed: 5, commits: 10, authors: 2)
      condition(storm).should eq(Cond::Stormy)
      # One fewer per day: below the 3/day line.
      condition(Factory.metrics(issues_opened: 20, issues_closed: 5, commits: 10, authors: 2))
        .should_not eq(Cond::Stormy)
      # Same influx, but triage keeps pace: opened must exceed 2x closed.
      condition(Factory.metrics(issues_opened: 21, issues_closed: 11, commits: 10, authors: 2))
        .should_not eq(Cond::Stormy)
    end

    it "freezes over when nothing lands and almost nothing stirs" do
      condition(ActivityWeather::Metrics.zero(7)).should eq(Cond::Snowy)
      # One lone issue in a week: below half the fog line, still frozen.
      condition(Factory.metrics(issues_opened: 1)).should eq(Cond::Snowy)
      # An archived repository is frozen no matter what trickles in.
      condition(Factory.metrics(commits: 30, authors: 3), Factory.repo(archived: true))
        .should eq(Cond::Snowy)
    end

    it "settles into fog on a faint trickle of activity" do
      # A single commit in a week is above frozen (something landed) but
      # below the fog line.
      condition(Factory.metrics(commits: 1, authors: 1)).should eq(Cond::Foggy)
      # One issue opened and closed, nothing landed: too alive for snow.
      condition(Factory.metrics(issues_opened: 1, issues_closed: 1)).should eq(Cond::Foggy)
    end

    it "rains when the backlog swells without storming" do
      rain = Factory.metrics(commits: 10, authors: 1, issues_opened: 14, issues_closed: 2)
      condition(rain).should eq(Cond::Rainy)
      # Triage keeping pace drops the humidity below the rain line.
      dry = Factory.metrics(commits: 10, authors: 1, issues_opened: 14, issues_closed: 14)
      condition(dry).should_not eq(Cond::Rainy)
    end

    it "turns windy when discussion outweighs code" do
      windy = Factory.metrics(commits: 3, authors: 1,
        issues_opened: 12, issues_closed: 12)
      condition(windy).should eq(Cond::Windy)
      # The same churn behind a mountain of commits is just a busy repo.
      grounded = Factory.metrics(commits: 40, authors: 3,
        issues_opened: 12, issues_closed: 12)
      condition(grounded).should_not eq(Cond::Windy)
    end

    it "is sunny when hot and dry, partly cloudy when merely warm" do
      condition(Factory.metrics(commits: 35, authors: 3)).should eq(Cond::Sunny)
      condition(Factory.metrics(commits: 10, authors: 1)).should eq(Cond::PartlyCloudy)
    end

    it "defaults to cloudy in the unremarkable middle" do
      condition(Factory.metrics(commits: 8)).should eq(Cond::Cloudy)
    end

    it "honours custom thresholds" do
      lax = ActivityWeather::Thresholds.new
      lax.sunny_temp = 10.0
      condition(Factory.metrics(commits: 10, authors: 1), thresholds: lax).should eq(Cond::Sunny)
    end
  end

  describe ".report" do
    it "assembles a full report from a snapshot, deterministically" do
      from = Factory::AS_OF - 7.days
      commits = (0...14).map { |i| Factory.commit(from + (i % 7).days + i.hours, "dev#{i % 3}") }
      snapshot = Factory.snapshot(commits: commits)

      report = Meteo.report(snapshot, Factory::AS_OF, 7, 7, DEFAULTS, ActivityWeather::PhraseBook.new)
      again = Meteo.report(snapshot, Factory::AS_OF, 7, 7, DEFAULTS, ActivityWeather::PhraseBook.new)
      report.should eq(again)

      report.repo.should eq("octo/repo")
      report.metrics.commits.should eq(14)
      report.daily.size.should eq(7)
      report.period_label.should eq("last 7 days")
      report.phrase.should eq(ActivityWeather::PhraseBook::DEFAULTS[report.condition])
    end

    it "skips the forecast when asked for zero days" do
      report = Meteo.report(Factory.snapshot, Factory::AS_OF, 7, 0, DEFAULTS, ActivityWeather::PhraseBook.new)
      report.daily.should be_empty
    end

    it "keeps window verdicts out of the per-day forecast" do
      # A quiet single day is fog, never snow or aurora.
      quiet_day = ActivityWeather::Metrics.zero(1)
      Meteo.day_condition(quiet_day, DEFAULTS).should eq(Cond::Foggy)
    end
  end
end

describe ActivityWeather::PhraseBook do
  it "fills placeholders and honours overrides" do
    book = ActivityWeather::PhraseBook.new({"sunny" => "{repo}: {commits} commits by {authors} devs"})
    metrics = Factory.metrics(commits: 42, authors: 3)
    book.phrase(Cond::Sunny, metrics, "octo/repo").should eq("octo/repo: 42 commits by 3 devs")
    # Conditions without an override keep the stock phrase.
    book.phrase(Cond::Foggy, metrics, "octo/repo")
      .should eq(ActivityWeather::PhraseBook::DEFAULTS[Cond::Foggy])
  end
end
