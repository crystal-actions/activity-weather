module ActivityWeather
  # The reporting window, written as `7d`, `2w`, or `1m`. Parsed into whole
  # days: everything downstream buckets by UTC calendar day, so a fractional
  # window would only create days that are half inside the report.
  module Period
    MIN_DAYS = 1
    # Bounded by what the paged endpoints can actually cover: past ~90 days a
    # busy repository blows through the page caps and the report would be
    # computed from a silently truncated sample.
    MAX_DAYS = 90

    DEFAULT = "7d"

    def self.parse_days(value : String) : Int32
      match = value.strip.downcase.match(/\A(\d+)\s*([dwm])?\z/)
      unless match
        raise ConfigError.new(
          "`period` must be a number of days, weeks, or months like `7d`, `2w`, or `1m`: got #{value.inspect}")
      end

      count = match[1].to_i64
      days =
        case match[2]?
        when "w" then count * 7
        when "m" then count * 30 # calendar-agnostic on purpose: "1m" means "about 30 days", not a date range
        else          count
        end

      unless MIN_DAYS <= days <= MAX_DAYS
        raise ConfigError.new(
          "`period` must be between #{MIN_DAYS} and #{MAX_DAYS} days: #{value.inspect} is #{days} days")
      end
      days.to_i32
    end

    # `7d` → "last 7 days", `1d` → "last 24 hours" — what the SVG prints.
    def self.label(days : Int32) : String
      days == 1 ? "last 24 hours" : "last #{days} days"
    end
  end
end
