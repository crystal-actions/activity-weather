module ActivityWeather
  # Turns counted activity into weather. Pure and deterministic: everything
  # it needs arrives as an argument — no clock, no environment — so the same
  # snapshot always produces the same report, which is what makes the
  # decision tree testable one threshold at a time.
  module Meteorologist
    # Relative worth of each kind of event. A merged PR is work that landed;
    # an opened issue is work that appeared; a release is a milestone. Stars
    # are cheap applause and weigh accordingly.
    COMMIT_POINTS       =  1.0
    PR_OPENED_POINTS    =  3.0
    PR_MERGED_POINTS    =  4.0
    ISSUE_OPENED_POINTS =  2.0
    ISSUE_CLOSED_POINTS =  2.5
    RELEASE_POINTS      = 10.0
    STAR_POINTS         =  0.5
    AUTHOR_POINTS       =  5.0

    def self.report(snapshot : ActivitySnapshot, as_of : Time, period_days : Int32,
                    forecast_days : Int32, thresholds : Thresholds,
                    phrases : PhraseBook) : WeatherReport
      current, previous = MetricsCalculator.split(snapshot, as_of, period_days)
      condition = condition_for(current, snapshot.repo, thresholds)

      daily = [] of DayReport
      if forecast_days > 0
        daily = MetricsCalculator.daily(snapshot, as_of, forecast_days).map do |day|
          DayReport.new(day.date, day_condition(day.metrics, thresholds), temperature(day.metrics))
        end
      end

      WeatherReport.new(
        condition: condition,
        temperature: temperature(current),
        wind: wind(current),
        humidity: humidity(current),
        pressure: trend(current, previous),
        phrase: phrases.phrase(condition, current, snapshot.repo.full_name),
        repo: snapshot.repo.full_name,
        period_days: period_days,
        metrics: current,
        daily: daily,
        truncated: snapshot.truncated,
      )
    end

    # Weighted activity points; the single number the temperature is read
    # from. Log-scaled downstream, so it only has to be monotonic, not fair.
    def self.points(metrics : Metrics) : Float64
      metrics.commits * COMMIT_POINTS +
        metrics.prs_opened * PR_OPENED_POINTS +
        metrics.prs_merged * PR_MERGED_POINTS +
        metrics.issues_opened * ISSUE_OPENED_POINTS +
        metrics.issues_closed * ISSUE_CLOSED_POINTS +
        metrics.releases * RELEASE_POINTS +
        metrics.stars_gained * STAR_POINTS +
        metrics.authors * AUTHOR_POINTS
    end

    # 0–40 °C. Log scale so a steady hobby project reads warm and a monorepo
    # saturates instead of breaking the thermometer: ~1 point/day ≈ 10°,
    # ~3/day ≈ 20°, ~7/day ≈ 30°, 15+/day pegs at 40°.
    def self.temperature(metrics : Metrics) : Float64
      scaled = 10.0 * Math.log2(1.0 + metrics.per_day(points(metrics)))
      scaled.clamp(0.0, 40.0).round(1)
    end

    # Everything opened and closed, regardless of what it was.
    def self.churn(metrics : Metrics) : Int32
      metrics.issues_opened + metrics.issues_closed +
        metrics.prs_opened + metrics.prs_merged
    end

    # 0–60 km/h of churn.
    def self.wind(metrics : Metrics) : Int32
      (12.0 * Math.log2(1.0 + metrics.per_day(churn(metrics)))).round.to_i.clamp(0, 60)
    end

    # Backlog pressure: the share of opened among opened+closed. 50 when
    # nothing happened — still air, not dry air.
    def self.humidity(metrics : Metrics) : Int32
      opened = metrics.issues_opened + metrics.prs_opened
      closed = metrics.issues_closed + metrics.prs_merged
      total = opened + closed
      return 50 if total.zero?
      (100.0 * opened / total).round.to_i
    end

    def self.trend(current : Metrics, previous : Metrics) : Trend
      now = points(current)
      before = points(previous)
      return Trend::Steady if now.zero? && before.zero?
      return Trend::Rising if now > before * 1.25
      return Trend::Falling if now < before * 0.8
      Trend::Steady
    end

    # Ordered decision tree, first match wins. Rare and special outranks
    # common: a release paints a rainbow over what would otherwise be a
    # merely sunny week.
    def self.condition_for(metrics : Metrics, repo : RepoInfo, thresholds : Thresholds) : Condition
      temp = temperature(metrics)
      issues_per_day = metrics.per_day(metrics.issues_opened)
      points_per_day = metrics.per_day(points(metrics))

      if metrics.per_day(metrics.stars_gained) >= thresholds.aurora_stars_per_day
        Condition::Aurora
      elsif metrics.releases >= 1 && temp >= thresholds.rainbow_min_temp
        Condition::Rainbow
      elsif storm?(metrics, thresholds)
        Condition::Stormy
      elsif frozen?(metrics, repo, points_per_day, thresholds)
        Condition::Snowy
      elsif points_per_day < thresholds.fog_points_per_day
        Condition::Foggy
      else
        busy_condition(metrics, temp, issues_per_day, thresholds)
      end
    end

    # The reduced per-day tree for the forecast strip: no aurora, rainbow, or
    # snow — those are verdicts about a whole window, and a single quiet day
    # inside a busy week is just a foggy day, not a frozen repository.
    def self.day_condition(metrics : Metrics, thresholds : Thresholds) : Condition
      temp = temperature(metrics)
      points_per_day = metrics.per_day(points(metrics))

      if storm?(metrics, thresholds)
        Condition::Stormy
      elsif points_per_day < thresholds.fog_points_per_day
        Condition::Foggy
      else
        busy_condition(metrics, temp, metrics.per_day(metrics.issues_opened), thresholds)
      end
    end

    private def self.storm?(metrics : Metrics, thresholds : Thresholds) : Bool
      metrics.per_day(metrics.issues_opened) >= thresholds.storm_issues_per_day &&
        metrics.issues_opened > 2 * metrics.issues_closed
    end

    # Frozen means nothing landed — no commits, no merges — and nothing else
    # was loud enough to call the place alive: below half the fog line with
    # nothing landed is snow, below the fog line with a trickle is fog. A
    # docs repository doing heavy issue triage with zero commits is busy,
    # not hibernating.
    private def self.frozen?(metrics : Metrics, repo : RepoInfo, points_per_day : Float64,
                             thresholds : Thresholds) : Bool
      return true if repo.archived
      metrics.commits.zero? && metrics.prs_merged.zero? &&
        points_per_day < thresholds.fog_points_per_day / 2
    end

    private def self.busy_condition(metrics : Metrics, temp : Float64,
                                    issues_per_day : Float64, thresholds : Thresholds) : Condition
      moisture = humidity(metrics)
      if moisture >= thresholds.rain_humidity && issues_per_day >= 1.0
        Condition::Rainy
      elsif wind(metrics) >= thresholds.windy_wind && metrics.commits < churn(metrics)
        # More discussion than code: strong wind is only "windy weather" when
        # the churn outweighs what actually landed in the tree.
        Condition::Windy
      elsif temp >= thresholds.sunny_temp && moisture < 60
        Condition::Sunny
      elsif temp >= 12.0
        Condition::PartlyCloudy
      else
        Condition::Cloudy
      end
    end
  end
end
