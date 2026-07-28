require "http/client"
require "json"
require "uri"

module ActivityWeather
  class ApiError < Exception
  end

  # Server-side failures worth another attempt; carries the same message the
  # caller would otherwise see, plus the delay the server named if it named one.
  private class RetryableApiError < ApiError
    getter retry_after : Time::Span?

    def initialize(message : String, @retry_after : Time::Span? = nil)
      super(message)
    end
  end

  # Seam for the GitHub-backed activity fetches so specs can inject a fake.
  abstract class GitHubSource
    abstract def repo_info(repo : String) : RepoInfo
    abstract def commits(repo : String, since : Time, until_time : Time) : Array(CommitInfo)
    abstract def issues(repo : String, since : Time) : Array(IssueInfo)
    abstract def releases(repo : String) : Array(ReleaseInfo)
    abstract def star_times(repo : String, since : Time) : Array(Time)

    # True once any listing hit its page cap, meaning counts are a floor.
    def truncated? : Bool
      false
    end
  end

  # Fetches activity from the GitHub REST API. Deliberately avoids both the
  # `/stats/*` endpoints (202 "come back later" semantics need an unbounded
  # poll loop, and their buckets ignore the requested window) and the Search
  # API (its own much smaller rate limit) — plain listings with server-side
  # date filters cover everything the meteorologist needs in ~26 requests
  # worst case, well inside the default workflow token's budget.
  class GitHubApi < GitHubSource
    PER_PAGE     = 100
    MAX_ATTEMPTS =   3

    # Page caps per listing. A window that big has saturated the temperature
    # scale anyway, so the report stays the same — but `truncated?` flips so
    # the runner can say the numbers are a floor.
    MAX_PAGES     = 10
    STAR_PAGE_CAP =  4

    # How many pages of one collection may be in flight together. Low enough
    # to stay clear of the secondary rate limit that punishes bursts.
    PAGE_WINDOW = 4

    # A secondary rate limit names its own delay; anything longer than this is
    # better spent failing with a message someone can act on.
    MAX_RETRY_AFTER = 30.seconds

    # Timestamps carry `starred_at` only under this media type.
    STAR_ACCEPT = "application/vnd.github.star+json"

    REPO_PATTERN = %r{\A[^/\s]+/[^/\s]+\z}

    getter? truncated : Bool = false

    def initialize(@token : String? = nil,
                   @api_base : String = "https://api.github.com",
                   @backoff_base : Time::Span = 1.second,
                   pool : HTTPPool? = nil)
      @pool = pool || HTTPPool.new
    end

    def repo_info(repo : String) : RepoInfo
      validate_repo(repo)
      body = get_response("#{@api_base}/repos/#{repo}", "repository #{repo}").body
      dto = parse_one(body, "repository #{repo}", RepoDTO)
      RepoInfo.new(
        full_name: dto.full_name,
        stars: dto.stargazers_count,
        created_at: dto.created_at,
        pushed_at: dto.pushed_at,
        archived: dto.archived?,
        default_branch: dto.default_branch,
      )
    end

    def commits(repo : String, since : Time, until_time : Time) : Array(CommitInfo)
      validate_repo(repo)
      query = "since=#{time_param(since)}&until=#{time_param(until_time)}"
      fetch_pages("/repos/#{repo}/commits?#{query}", "commits of #{repo}", CommitDTO, MAX_PAGES)
        .compact_map do |dto|
          timestamp = dto.commit.author.try(&.date) || dto.commit.committer.try(&.date)
          next unless timestamp
          CommitInfo.new(timestamp: timestamp, author: dto.author.try(&.login) || dto.commit.author.try(&.email))
        end
    end

    # One listing, four metrics: entries carrying a `pull_request` key are
    # PRs, and their `merged_at` rides along in the same payload — no
    # per-item follow-up requests. `since` filters on `updated_at`
    # server-side, which covers everything opened or closed in the window.
    def issues(repo : String, since : Time) : Array(IssueInfo)
      validate_repo(repo)
      query = "state=all&since=#{time_param(since)}&sort=updated&direction=desc"
      fetch_pages("/repos/#{repo}/issues?#{query}", "issues of #{repo}", IssueDTO, MAX_PAGES)
        .map do |dto|
          IssueInfo.new(
            number: dto.number,
            created_at: dto.created_at,
            closed_at: dto.closed_at,
            pull_request: !dto.pull_request.nil?,
            merged_at: dto.pull_request.try(&.merged_at),
          )
        end
    end

    # A single page: release cadence past 30-per-window has nothing left to
    # tell a weather report.
    def releases(repo : String) : Array(ReleaseInfo)
      validate_repo(repo)
      body = get_response("#{@api_base}/repos/#{repo}/releases?per_page=30", "releases of #{repo}").body
      list = parse_page(body, "releases of #{repo}", ReleaseDTO) || [] of ReleaseDTO
      list.compact_map do |dto|
        next if dto.draft?
        published = dto.published_at
        next unless published
        ReleaseInfo.new(published_at: published)
      end
    end

    # Stargazers only list oldest-first, so the recent window lives on the
    # *last* pages: read the `Link: rel="last"` header from page 1, then walk
    # backwards until a page dips below `since` or the cap is spent.
    def star_times(repo : String, since : Time) : Array(Time)
      validate_repo(repo)
      context = "stargazers of #{repo}"
      page_url = ->(page : Int32) do
        "#{@api_base}/repos/#{repo}/stargazers?per_page=#{PER_PAGE}&page=#{page}"
      end

      first_response = get_response(page_url.call(1), context, accept: STAR_ACCEPT)
      last = last_page(first_response) || 1

      times = [] of Time
      page = last
      while page >= 1
        if page < last - STAR_PAGE_CAP + 1
          # The window reaches further back than the budget; report a floor.
          @truncated = true
          break
        end
        body = page == 1 ? first_response.body : get_response(page_url.call(page), context, accept: STAR_ACCEPT).body
        stars = parse_page(body, context, StarDTO) || [] of StarDTO
        recent = stars.select { |star| star.starred_at >= since }
        times.concat(recent.map(&.starred_at))
        # A page that is only partly recent contains the boundary: done.
        break if recent.size < stars.size
        page -= 1
      end
      times.sort!
    end

    struct RepoDTO
      include JSON::Serializable

      getter full_name : String
      getter stargazers_count : Int32 = 0
      getter created_at : Time
      getter pushed_at : Time? = nil
      getter? archived : Bool = false
      getter default_branch : String = "main"
    end

    struct AccountRefDTO
      include JSON::Serializable

      getter login : String? = nil
    end

    struct GitActorDTO
      include JSON::Serializable

      getter date : Time? = nil
      getter email : String? = nil
    end

    struct CommitDetailDTO
      include JSON::Serializable

      getter author : GitActorDTO? = nil
      getter committer : GitActorDTO? = nil
    end

    struct CommitDTO
      include JSON::Serializable

      getter commit : CommitDetailDTO
      getter author : AccountRefDTO? = nil
    end

    struct PullRefDTO
      include JSON::Serializable

      getter merged_at : Time? = nil
    end

    struct IssueDTO
      include JSON::Serializable

      getter number : Int32
      getter created_at : Time
      getter closed_at : Time? = nil
      getter pull_request : PullRefDTO? = nil
    end

    struct ReleaseDTO
      include JSON::Serializable

      getter published_at : Time? = nil
      getter? draft : Bool = false
    end

    struct StarDTO
      include JSON::Serializable

      getter starred_at : Time
    end

    private def validate_repo(repo : String) : Nil
      return if repo.matches?(REPO_PATTERN)
      raise ApiError.new("`repo` must look like owner/name, got: #{repo.inspect}")
    end

    private def time_param(time : Time) : String
      URI.encode_www_form(time.to_utc.to_rfc3339)
    end

    # Walks a paginated collection up to `max_pages`, collecting every item.
    #
    # Page 1 comes back with a `Link` header naming the last page, which turns
    # the rest of the walk into a few bounded fan-outs. Without a `Link`
    # header there is nothing to plan from, so that path stays sequential.
    private def fetch_pages(path : String, context : String, dto : T.class,
                            max_pages : Int32) : Array(T) forall T
      separator = path.includes?('?') ? '&' : '?'
      page_url = ->(page : Int32) do
        "#{@api_base}#{path}#{separator}per_page=#{PER_PAGE}&page=#{page}"
      end

      items = [] of T
      response = get_response(page_url.call(1), context)
      first = parse_page(response.body, context, dto)
      return items unless first
      items.concat(first)
      return items if first.size < PER_PAGE

      last = last_page(response)
      if last && last > max_pages
        @truncated = true
        last = max_pages
      end

      page = 2
      while last.nil? || page <= last
        if page > max_pages
          @truncated = true
          break
        end
        window = last ? Math.min(PAGE_WINDOW, last - page + 1) : 1
        bodies = Concurrent.map((page...page + window).to_a, PAGE_WINDOW) do |number|
          get_response(page_url.call(number), context).body
        end
        bodies.each do |body|
          batch = parse_page(body, context, dto)
          return items unless batch
          items.concat(batch)
          return items if batch.size < PER_PAGE
        end
        page += window
      end
      items
    end

    # `nil` means the collection is over: an empty body (a 204, say) is not a
    # JSON array, and neither is a proxy's HTML error page — that one has to
    # surface as an API error rather than a raw parse exception.
    private def parse_page(body : String, context : String, dto : T.class) : Array(T)? forall T
      return if body.blank?
      begin
        Array(T).from_json(body)
      rescue ex : JSON::ParseException
        raise ApiError.new("#{context}: unexpected response from GitHub (#{ex.message})")
      end
    end

    private def parse_one(body : String, context : String, dto : T.class) : T forall T
      T.from_json(body)
    rescue ex : JSON::ParseException
      raise ApiError.new("#{context}: unexpected response from GitHub (#{ex.message})")
    end

    # `Link: <https://api.github.com/...?page=7>; rel="last", <...>; rel="next"`.
    # Splitting on commas is safe for the URLs GitHub puts in here.
    private def last_page(response : HTTP::Client::Response) : Int32?
      link = response.headers["Link"]?
      return unless link
      link.split(',').each do |part|
        next unless part.includes?(%(rel="last"))
        if match = part.match(/[?&]page=(\d+)/)
          number = match[1].to_i?
          return number if number && number > 1
        end
      end
      nil
    end

    private def get_response(url : String, context : String,
                             accept : String? = nil) : HTTP::Client::Response
      with_retries(context) do
        response = @pool.get(url, headers(accept))
        check_status(response, context)
        response
      end
    end

    private def with_retries(context : String, & : -> T) : T forall T
      attempt = 0
      loop do
        attempt += 1
        wait = nil.as(Time::Span?)
        begin
          return yield
        rescue ex : RetryableApiError
          raise ApiError.new(ex.message || "GitHub API error") if attempt >= MAX_ATTEMPTS
          wait = ex.retry_after
        rescue ex : ApiError
          raise ex
        rescue ex : Exception
          # Socket, TLS and other transport failures; only ApiError leaves
          # this method so callers have one error type to handle.
          raise ApiError.new("network error talking to GitHub (#{context}): #{ex.message}") if attempt >= MAX_ATTEMPTS
        end
        # Jitter earns its keep now that several listings and several pages
        # are in flight together: without it they back off in lockstep and
        # hit the same limit again at the same instant.
        sleep(wait || @backoff_base * (2 ** (attempt - 1)) * (1.0 + rand * 0.25))
      end
    end

    private def check_status(response : HTTP::Client::Response, context : String) : Nil
      case response.status_code
      when 200, 204
        nil
      when 401
        raise ApiError.new("GitHub API rejected the token (401) — check the `token` input")
      when 403, 429
        # Two different failures share these codes. An exhausted hourly quota
        # will still be exhausted in a second, so it stays fatal with a message
        # that says what to do about it. A secondary (burst) limit names its own
        # delay and clears on its own — waiting it out is the whole fix.
        raise rate_limit_error(response) if response.headers["x-ratelimit-remaining"]? == "0"
        if wait = ActivityWeather.retry_after(response, MAX_RETRY_AFTER)
          raise RetryableApiError.new(
            "GitHub API asked for a #{wait.total_seconds.round.to_i}s pause (#{context})", wait)
        end
        raise rate_limit_error(response)
      when 404
        raise ApiError.new("#{context}: not found or not accessible (pass a token with access?)")
      when 500..599
        # GitHub 5xx is usually transient; one policy for every listing.
        raise RetryableApiError.new("GitHub API returned #{response.status_code} for #{context}")
      else
        raise ApiError.new("GitHub API returned #{response.status_code} for #{context}")
      end
    end

    private def rate_limit_error(response : HTTP::Client::Response) : ApiError
      if response.headers["x-ratelimit-remaining"]? == "0"
        reset = response.headers["x-ratelimit-reset"]?.try(&.to_i64?)
        at = reset ? " (resets at #{Time.unix(reset).to_rfc3339})" : ""
        ApiError.new("GitHub API rate limit exceeded#{at} — pass a `token` to raise the limit")
      else
        ApiError.new("GitHub API denied the request (#{response.status_code})")
      end
    end

    private def headers(accept : String? = nil) : HTTP::Headers
      result = HTTP::Headers{
        "Accept"               => accept || "application/vnd.github+json",
        "User-Agent"           => "activity-weather/#{VERSION}",
        "X-GitHub-Api-Version" => "2022-11-28",
      }
      if token = @token
        result["Authorization"] = "Bearer #{token}" unless token.empty?
      end
      result
    end
  end
end
