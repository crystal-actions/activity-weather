require "./spec_helper"
require "./support/factories"

alias Calc = ActivityWeather::MetricsCalculator

describe ActivityWeather::MetricsCalculator do
  describe ".window" do
    it "judges each event by its own timestamp, not its parent's state" do
      from = Factory::AS_OF - 7.days
      # Opened before the window, closed inside it: one close, no open.
      old_but_closed = Factory.issue(created_at: from - 10.days, closed_at: from + 1.day)
      # Opened inside, still open: one open, no close.
      fresh = Factory.issue(number: 2, created_at: from + 2.days)
      # A PR opened and merged inside the window.
      pr = Factory.issue(number: 3, created_at: from + 3.days, closed_at: from + 4.days,
        pull_request: true, merged_at: from + 4.days)
      snapshot = Factory.snapshot(issues: [old_but_closed, fresh, pr])

      metrics = Calc.window(snapshot, from, Factory::AS_OF)
      metrics.issues_opened.should eq(1)
      metrics.issues_closed.should eq(1)
      metrics.prs_opened.should eq(1)
      metrics.prs_merged.should eq(1)
    end

    it "counts distinct commit authors inside the window only" do
      from = Factory::AS_OF - 7.days
      commits = [
        Factory.commit(from + 1.day, "alice"),
        Factory.commit(from + 2.days, "alice"),
        Factory.commit(from + 3.days, "bob"),
        Factory.commit(from + 4.days, nil),    # anonymous — no author to count
        Factory.commit(from - 1.day, "carol"), # before the window
      ]
      metrics = Calc.window(Factory.snapshot(commits: commits), from, Factory::AS_OF)
      metrics.commits.should eq(4)
      metrics.authors.should eq(2)
    end

    it "treats the window as [from, to)" do
      from = Factory::AS_OF - 7.days
      edge = [Factory.commit(from), Factory.commit(Factory::AS_OF)]
      metrics = Calc.window(Factory.snapshot(commits: edge), from, Factory::AS_OF)
      metrics.commits.should eq(1)
    end
  end

  describe ".daily" do
    it "buckets by UTC calendar day, keeping quiet days as zeros" do
      # 09:00 and 23:59 on the same UTC day land in one bucket; 00:00 the
      # next day lands in the next.
      day = Factory::AS_OF.at_beginning_of_day
      commits = [
        Factory.commit(day - 2.days + 9.hours),
        Factory.commit(day - 2.days + 23.hours + 59.minutes),
        Factory.commit(day - 1.day),
      ]
      daily = Calc.daily(Factory.snapshot(commits: commits), Factory::AS_OF, 3)
      daily.size.should eq(3)
      daily.map(&.metrics.commits).should eq([2, 1, 0])
      daily.first.date.should eq(day - 2.days)
      # Today's bucket covers up through as_of even though the day is not over.
      daily.last.date.should eq(day)
      daily.all? { |bucket| bucket.metrics.days == 1 }.should be_true
    end
  end

  describe ".split" do
    it "splits into the current window and the one before it" do
      from = Factory::AS_OF - 7.days
      commits = [
        Factory.commit(from + 1.day),
        Factory.commit(from + 2.days),
        Factory.commit(from - 3.days),
      ]
      current, previous = Calc.split(Factory.snapshot(commits: commits), Factory::AS_OF, 7)
      current.commits.should eq(2)
      previous.commits.should eq(1)
      current.days.should eq(7)
      previous.days.should eq(7)
    end
  end

  it "computes per-day rates without dividing by zero" do
    Factory.metrics(days: 7, commits: 14).per_day(14).should eq(2.0)
    ActivityWeather::Metrics.zero(0).per_day(5).should eq(5.0)
  end
end
