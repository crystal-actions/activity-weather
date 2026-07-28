module ActivityWeather
  # Orchestrates the pipeline: fetch activity, read the weather, render every
  # target, write files, report outputs. Returns a process exit code.
  class Runner
    # What one concurrent fetch may return; results are read back by position.
    private alias Fetched = RepoInfo | Array(CommitInfo) | Array(IssueInfo) | Array(ReleaseInfo) | Array(Time)

    getter written_paths = [] of String

    def initialize(@config : Config, @github_source : GitHubSource,
                   @workspace : String = Dir.current,
                   @committer : Committer? = nil,
                   @as_of : Time = Time.utc)
    end

    def run : Int32
      repo = @config.repo || ENV["GITHUB_REPOSITORY"]?.presence ||
             raise ConfigError.new("`repo` is not set and GITHUB_REPOSITORY is not available — " \
                                   "pass the `repo` input or add `repo:` to the config")
      days = @config.period_days

      snapshot = fetch(repo)
      # An empty window is a valid weather — fog or snow — so unlike a mural
      # of zero faces there is nothing to refuse here.
      report = Meteorologist.report(snapshot, @as_of, days, @config.forecast.days,
        @config.thresholds, @config.phrase_book)

      if report.truncated
        Annotations.notice("some listings hit their page caps for #{repo}; counts are a floor, not a total")
      end

      # Render everything before writing anything: a failure halfway through
      # would otherwise leave some outputs updated and others stale.
      rendered = @config.render_targets.map do |path, style, mode_override|
        renderer = Renderer.for(style, @config, mode_override)
        {path, renderer.render(report), renderer.last_size}
      end

      rendered.each do |path, svg, _size|
        full_path = File.join(@workspace, path)
        Dir.mkdir_p(File.dirname(full_path))
        File.write(full_path, svg)
        written_paths << path
      end

      Annotations.output("condition", report.condition.key)
      Annotations.output("temperature", report.temperature.to_s)
      Annotations.output("phrase", report.phrase)
      Annotations.output("paths", written_paths.join(","))
      # Reported for the first target only — what a single-output config (the
      # common case) means by "the image".
      if first = rendered.first?
        Annotations.output("width", first[2][0].ceil.to_i.to_s)
        Annotations.output("height", first[2][1].ceil.to_i.to_s)
      end

      changed = false
      if committer = @committer
        changed = committer.commit(written_paths)
        Annotations.notice(changed ? "activity weather updated: #{report.condition.key}, #{report.temperature.round.to_i}°" : "activity weather already up to date")
      end
      Annotations.output("changed", changed.to_s)
      0
    rescue ex : ConfigError | ApiError | CommitError
      Annotations.error(ex.message || ex.class.name)
      1
    end

    private def fetch(repo : String) : ActivitySnapshot
      source = @github_source
      # Twice the window so the previous half is on hand for the trend, at
      # the cost of a few extra pages rather than extra endpoints.
      since = @as_of - (@config.period_days * 2).days

      # Independent round trips to the same host: run them together, results
      # come back in list order — and so does the first error, so which
      # listing failed reads the same on every run.
      fetches = [
        -> { source.repo_info(repo).as(Fetched) },
        -> { source.commits(repo, since, @as_of).as(Fetched) },
        -> { source.issues(repo, since).as(Fetched) },
      ]
      fetches << -> { source.releases(repo).as(Fetched) } if @config.metrics.releases?
      if @config.metrics.stars?
        # The default workflow token is a GitHub App installation token, and
        # the starring API is closed to those — there is no permission to
        # grant. Stars are flavor, not substance, so degrade to zero with a
        # warning instead of failing the whole report.
        fetches << -> do
          begin
            source.star_times(repo, since).as(Fetched)
          rescue ex : ApiError
            Annotations.warning("stargazers unavailable, reporting stars as 0 — pass a personal access " \
                                "token via `token` to enable them, or set `metrics.stars: false` (#{ex.message})")
            ([] of Time).as(Fetched)
          end
        end
      end

      results = Concurrent.map(fetches, fetches.size, &.call)

      ActivitySnapshot.new(
        repo: results[0].as(RepoInfo),
        commits: results[1].as(Array(CommitInfo)),
        issues: results[2].as(Array(IssueInfo)),
        releases: @config.metrics.releases? ? results[3].as(Array(ReleaseInfo)) : [] of ReleaseInfo,
        star_times: @config.metrics.stars? ? results.last.as(Array(Time)) : [] of Time,
        truncated: source.truncated?,
      )
    end
  end
end
