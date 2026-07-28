# Hand-built inputs for the pure core. Every time is pinned so specs stay
# deterministic; AS_OF is a Tuesday, which the forecast day-label specs rely on.
module Factory
  AS_OF = Time.utc(2026, 7, 21, 12, 0, 0)

  def self.metrics(days = 7, commits = 0, authors = 0, issues_opened = 0,
                   issues_closed = 0, prs_opened = 0, prs_merged = 0,
                   releases = 0, stars_gained = 0) : ActivityWeather::Metrics
    ActivityWeather::Metrics.new(
      days: days, commits: commits, authors: authors,
      issues_opened: issues_opened, issues_closed: issues_closed,
      prs_opened: prs_opened, prs_merged: prs_merged,
      releases: releases, stars_gained: stars_gained,
    )
  end

  def self.repo(full_name = "octo/repo", stars = 120, archived = false) : ActivityWeather::RepoInfo
    ActivityWeather::RepoInfo.new(
      full_name: full_name, stars: stars,
      created_at: Time.utc(2020, 1, 1), pushed_at: AS_OF,
      archived: archived, default_branch: "main",
    )
  end

  def self.commit(at : Time, author : String? = "octocat") : ActivityWeather::CommitInfo
    ActivityWeather::CommitInfo.new(timestamp: at, author: author)
  end

  def self.issue(number = 1, created_at = AS_OF, closed_at : Time? = nil,
                 pull_request = false, merged_at : Time? = nil) : ActivityWeather::IssueInfo
    ActivityWeather::IssueInfo.new(
      number: number, created_at: created_at, closed_at: closed_at,
      pull_request: pull_request, merged_at: merged_at,
    )
  end

  def self.report(condition = ActivityWeather::Condition::Sunny,
                  temperature = 24.0, wind = 12, humidity = 48,
                  pressure = ActivityWeather::Trend::Rising,
                  phrase = "Clear skies — commits are pouring in",
                  repo = "octo/weather-repo", period_days = 7,
                  metrics = self.metrics(commits: 128, authors: 5, issues_opened: 7,
                    issues_closed: 5, prs_opened: 12, prs_merged: 9, stars_gained: 23),
                  daily = [] of ActivityWeather::DayReport,
                  truncated = false) : ActivityWeather::WeatherReport
    ActivityWeather::WeatherReport.new(
      condition: condition, temperature: temperature, wind: wind,
      humidity: humidity, pressure: pressure, phrase: phrase, repo: repo,
      period_days: period_days, metrics: metrics, daily: daily, truncated: truncated,
    )
  end

  # A week of varied weather ending at AS_OF, for forecast renders.
  def self.week : Array(ActivityWeather::DayReport)
    conditions = [
      ActivityWeather::Condition::Foggy,
      ActivityWeather::Condition::Cloudy,
      ActivityWeather::Condition::PartlyCloudy,
      ActivityWeather::Condition::Sunny,
      ActivityWeather::Condition::Rainy,
      ActivityWeather::Condition::Stormy,
      ActivityWeather::Condition::Sunny,
    ]
    start = AS_OF.at_beginning_of_day - 6.days
    conditions.map_with_index do |condition, index|
      ActivityWeather::DayReport.new(start + index.days, condition, 4.0 + index * 5.0)
    end
  end

  def self.snapshot(repo = self.repo,
                    commits = [] of ActivityWeather::CommitInfo,
                    issues = [] of ActivityWeather::IssueInfo,
                    releases = [] of ActivityWeather::ReleaseInfo,
                    star_times = [] of Time,
                    truncated = false) : ActivityWeather::ActivitySnapshot
    ActivityWeather::ActivitySnapshot.new(
      repo: repo, commits: commits, issues: issues,
      releases: releases, star_times: star_times, truncated: truncated,
    )
  end
end
