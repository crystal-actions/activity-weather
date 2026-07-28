require "./spec_helper"

describe ActivityWeather::Period do
  it "parses bare day counts and d/w/m suffixes" do
    ActivityWeather::Period.parse_days("7").should eq(7)
    ActivityWeather::Period.parse_days("7d").should eq(7)
    ActivityWeather::Period.parse_days("2w").should eq(14)
    ActivityWeather::Period.parse_days("1m").should eq(30)
    ActivityWeather::Period.parse_days(" 3W ").should eq(21)
  end

  it "accepts the bounds and rejects just past them" do
    ActivityWeather::Period.parse_days("1d").should eq(1)
    ActivityWeather::Period.parse_days("90d").should eq(90)
    expect_raises(ActivityWeather::ConfigError, /between 1 and 90/) do
      ActivityWeather::Period.parse_days("0d")
    end
    expect_raises(ActivityWeather::ConfigError, /between 1 and 90/) do
      ActivityWeather::Period.parse_days("91d")
    end
    expect_raises(ActivityWeather::ConfigError, /between 1 and 90/) do
      ActivityWeather::Period.parse_days("13w")
    end
  end

  it "rejects garbage with the accepted forms in the message" do
    ["", "7 days", "d7", "-3d", "1.5w", "1y"].each do |value|
      expect_raises(ActivityWeather::ConfigError, /`period`/) do
        ActivityWeather::Period.parse_days(value)
      end
    end
  end

  it "labels windows for the SVG" do
    ActivityWeather::Period.label(1).should eq("last 24 hours")
    ActivityWeather::Period.label(7).should eq("last 7 days")
  end
end
