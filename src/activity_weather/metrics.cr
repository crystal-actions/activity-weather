module ActivityWeather
  # Activity counted over a window. Pure data — the judgment calls (what is
  # "sunny", what is "churn") belong to the meteorologist.
  record Metrics,
    days : Int32,
    commits : Int32,
    authors : Int32,
    issues_opened : Int32,
    issues_closed : Int32,
    prs_opened : Int32,
    prs_merged : Int32,
    releases : Int32,
    stars_gained : Int32 do
    def per_day(count : Int | Float64) : Float64
      count.to_f / Math.max(days, 1)
    end

    def self.zero(days : Int32) : Metrics
      new(days, 0, 0, 0, 0, 0, 0, 0, 0)
    end
  end

  record DayMetrics,
    # Midnight UTC of the calendar day the counts cover.
    date : Time,
    metrics : Metrics

  module MetricsCalculator
    # Counts every event whose own timestamp falls in [from, to). An issue
    # opened before the window but closed inside it counts as one close and
    # no open — each event is judged by when it happened, not by the state
    # of its parent object.
    def self.window(snapshot : ActivitySnapshot, from : Time, to : Time) : Metrics
      days = Math.max(((to - from).total_days).round.to_i, 1)
      authors = snapshot.commits
        .select { |commit| commit.timestamp >= from && commit.timestamp < to }
        .compact_map(&.author).uniq!.size

      Metrics.new(
        days: days,
        commits: count(snapshot.commits.map(&.timestamp), from, to),
        authors: authors,
        issues_opened: count(snapshot.issues.reject(&.pull_request).map(&.created_at), from, to),
        issues_closed: count(snapshot.issues.reject(&.pull_request).compact_map(&.closed_at), from, to),
        prs_opened: count(snapshot.issues.select(&.pull_request).map(&.created_at), from, to),
        prs_merged: count(snapshot.issues.select(&.pull_request).compact_map(&.merged_at), from, to),
        releases: count(snapshot.releases.map(&.published_at), from, to),
        stars_gained: count(snapshot.star_times, from, to),
      )
    end

    # One Metrics per UTC calendar day, oldest first, covering the `days`
    # days that end at `as_of`. Days with nothing stay present as zeros —
    # a forecast strip needs the quiet days drawn, not skipped.
    def self.daily(snapshot : ActivitySnapshot, as_of : Time, days : Int32) : Array(DayMetrics)
      finish = as_of.at_beginning_of_day + 1.day
      (0...days).to_a.reverse.map do |back|
        day_start = finish - (back + 1).days
        DayMetrics.new(day_start, window(snapshot, day_start, day_start + 1.day))
      end
    end

    # The current window and the one before it, for the pressure trend.
    def self.split(snapshot : ActivitySnapshot, as_of : Time, days : Int32) : {Metrics, Metrics}
      current_from = as_of - days.days
      {
        window(snapshot, current_from, as_of),
        window(snapshot, current_from - days.days, current_from),
      }
    end

    private def self.count(times : Array(Time), from : Time, to : Time) : Int32
      times.count { |time| time >= from && time < to }
    end
  end
end
