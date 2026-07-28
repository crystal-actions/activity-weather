require "./factories"

# Canned activity for runner specs; records what was asked for.
class FakeGitHubSource < ActivityWeather::GitHubSource
  property repo_info_value : ActivityWeather::RepoInfo = Factory.repo
  property commits_value = [] of ActivityWeather::CommitInfo
  property issues_value = [] of ActivityWeather::IssueInfo
  property releases_value = [] of ActivityWeather::ReleaseInfo
  property star_times_value = [] of Time
  property? truncated : Bool = false
  # Raised (once per call) by every fetch when set, for error-path specs.
  property error : Exception? = nil

  getter requested_repos = [] of String
  getter requested_windows = [] of {Time, Time}
  getter requested_sinces = [] of Time

  def repo_info(repo : String) : ActivityWeather::RepoInfo
    record_call(repo)
    repo_info_value
  end

  def commits(repo : String, since : Time, until_time : Time) : Array(ActivityWeather::CommitInfo)
    record_call(repo)
    @requested_windows << {since, until_time}
    commits_value
  end

  def issues(repo : String, since : Time) : Array(ActivityWeather::IssueInfo)
    record_call(repo)
    @requested_sinces << since
    issues_value
  end

  def releases(repo : String) : Array(ActivityWeather::ReleaseInfo)
    record_call(repo)
    releases_value
  end

  def star_times(repo : String, since : Time) : Array(Time)
    record_call(repo)
    @requested_sinces << since
    star_times_value
  end

  private def record_call(repo : String) : Nil
    @requested_repos << repo
    if pending = error
      raise pending
    end
  end
end
