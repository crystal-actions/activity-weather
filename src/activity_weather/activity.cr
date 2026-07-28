module ActivityWeather
  # Raw facts fetched from the API, before any interpretation. Everything the
  # meteorologist needs and nothing it has to go back for: timestamps stay
  # timestamps here so windowing and day-bucketing remain pure functions.
  record RepoInfo,
    full_name : String,
    stars : Int32,
    created_at : Time,
    pushed_at : Time?,
    archived : Bool,
    default_branch : String

  record CommitInfo,
    timestamp : Time,
    # Login when the commit is linked to an account, otherwise the commit
    # email — good enough to count distinct active people.
    author : String?

  record IssueInfo,
    number : Int32,
    created_at : Time,
    closed_at : Time?,
    # The issues endpoint returns pull requests too; this flag is how the
    # four issue/PR metrics come out of a single paginated listing.
    pull_request : Bool,
    merged_at : Time?

  record ReleaseInfo,
    published_at : Time

  record ActivitySnapshot,
    repo : RepoInfo,
    commits : Array(CommitInfo),
    issues : Array(IssueInfo),
    releases : Array(ReleaseInfo),
    star_times : Array(Time),
    # True when any listing hit its page cap: the numbers below are then a
    # floor, not a count. The scale saturates long before the caps do, so
    # the report stays honest — but it is announced, not hidden.
    truncated : Bool
end
