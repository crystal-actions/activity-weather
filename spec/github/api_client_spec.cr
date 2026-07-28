require "../spec_helper"
require "http/server"
require "json"

private SINCE = Time.utc(2026, 7, 14)
private UNTIL = Time.utc(2026, 7, 21)

private def commit_json(at : Time, login : String? = "octocat", email : String? = nil) : String
  {
    commit: {author: {date: at.to_rfc3339, email: email}, committer: {date: at.to_rfc3339}},
    author: login ? {login: login} : nil,
  }.to_json
end

private def issue_json(number : Int32, created_at : Time, closed_at : Time? = nil,
                       merged_at : Time? = nil, pr : Bool = false) : String
  base = {
    number:     number,
    created_at: created_at.to_rfc3339,
    closed_at:  closed_at.try(&.to_rfc3339),
    updated_at: (closed_at || created_at).to_rfc3339,
  }
  pr ? base.merge({pull_request: {merged_at: merged_at.try(&.to_rfc3339)}}).to_json : base.to_json
end

private def star_json(at : Time) : String
  {starred_at: at.to_rfc3339, user: {login: "fan"}}.to_json
end

# Serves canned pages per path prefix and records request paths + headers.
private class ApiServer
  getter seen = [] of {String, HTTP::Headers}
  getter base : String

  def initialize(@responses : Hash(String, Hash(Int32, String)),
                 @status : Int32 = 200,
                 @response_headers : Hash(Int32, HTTP::Headers) = {} of Int32 => HTTP::Headers)
    @server = HTTP::Server.new do |context|
      @seen << {"#{context.request.path}?#{context.request.query}", context.request.headers.dup}
      if @status != 200
        context.response.status_code = @status
        next
      end
      page = (context.request.query_params["page"]? || "1").to_i
      if headers = @response_headers[page]?
        headers.each { |key, values| values.each { |value| context.response.headers.add(key, value) } }
      end
      pages = @responses.find { |prefix, _| context.request.path.ends_with?(prefix) }.try(&.last)
      context.response.content_type = "application/json"
      context.response.print(pages.try(&.[page]?) || "[]")
    end
    address = @server.bind_unused_port "127.0.0.1"
    spawn { @server.listen rescue nil }
    @base = "http://#{address}"
  end

  def close
    @server.close
  end
end

private def with_server(responses, status = 200, response_headers = {} of Int32 => HTTP::Headers, &)
  server = ApiServer.new(responses, status, response_headers)
  begin
    yield ActivityWeather::GitHubApi.new(api_base: server.base, backoff_base: 1.millisecond), server
  ensure
    server.close
  end
end

private REPO_JSON = {
  full_name:        "octo/repo",
  stargazers_count: 321,
  created_at:       "2020-01-01T00:00:00Z",
  pushed_at:        "2026-07-20T10:00:00Z",
  archived:         false,
  default_branch:   "main",
}.to_json

describe ActivityWeather::GitHubApi do
  it "maps repository info" do
    with_server({"/repos/octo/repo" => {1 => REPO_JSON}}) do |api, _server|
      info = api.repo_info("octo/repo")
      info.full_name.should eq("octo/repo")
      info.stars.should eq(321)
      info.archived.should be_false
    end
  end

  it "rejects repo names that are not owner/name" do
    with_server({} of String => Hash(Int32, String)) do |api, _server|
      expect_raises(ActivityWeather::ApiError, /owner\/name/) { api.repo_info("nope") }
    end
  end

  it "fetches commits with the window in the query and maps authors" do
    pages = {1 => "[#{commit_json(SINCE + 1.day)},#{commit_json(SINCE + 2.days, nil, "g@example.com")}]"}
    with_server({"/commits" => pages}) do |api, server|
      commits = api.commits("octo/repo", SINCE, UNTIL)
      commits.size.should eq(2)
      commits[0].author.should eq("octocat")
      commits[1].author.should eq("g@example.com")

      request = server.seen.first[0]
      request.should contain("since=2026-07-14T00%3A00%3A00Z")
      request.should contain("until=2026-07-21T00%3A00%3A00Z")
    end
  end

  it "splits issues from pull requests and keeps merged_at from the payload" do
    pages = {1 => "[" + [
      issue_json(1, SINCE + 1.day),
      issue_json(2, SINCE + 2.days, closed_at: SINCE + 3.days),
      issue_json(3, SINCE + 2.days, closed_at: SINCE + 4.days, merged_at: SINCE + 4.days, pr: true),
    ].join(",") + "]"}
    with_server({"/issues" => pages}) do |api, server|
      issues = api.issues("octo/repo", SINCE)
      issues.map(&.pull_request).should eq([false, false, true])
      issues[2].merged_at.should eq(SINCE + 4.days)
      issues[1].merged_at.should be_nil
      server.seen.first[0].should contain("state=all")
      server.seen.first[0].should contain("sort=updated")
    end
  end

  it "paginates until a short page and stops at the cap with truncated set" do
    full = "[" + (1..100).map { |i| issue_json(i, SINCE + 1.day) }.join(",") + "]"
    pages = (1..ActivityWeather::GitHubApi::MAX_PAGES + 2).to_h { |page| {page, full} }
    with_server({"/issues" => pages}) do |api, server|
      issues = api.issues("octo/repo", SINCE)
      issues.size.should eq(100 * ActivityWeather::GitHubApi::MAX_PAGES)
      api.truncated?.should be_true
      server.seen.size.should eq(ActivityWeather::GitHubApi::MAX_PAGES)
    end
  end

  it "skips draft and unpublished releases" do
    body = "[" + [
      {published_at: (SINCE + 1.day).to_rfc3339, draft: false}.to_json,
      {published_at: (SINCE + 2.days).to_rfc3339, draft: true}.to_json,
      {published_at: nil, draft: false}.to_json,
    ].join(",") + "]"
    with_server({"/releases" => {1 => body}}) do |api, _server|
      api.releases("octo/repo").size.should eq(1)
    end
  end

  describe "#star_times" do
    it "asks for the star media type and filters a single page by since" do
      body = "[#{star_json(SINCE - 1.day)},#{star_json(SINCE + 1.day)}]"
      with_server({"/stargazers" => {1 => body}}) do |api, server|
        times = api.star_times("octo/repo", SINCE)
        times.should eq([SINCE + 1.day])
        server.seen.first[1]["Accept"].should eq(ActivityWeather::GitHubApi::STAR_ACCEPT)
      end
    end

    it "jumps to the last page and walks backwards to the boundary" do
      old = "[" + (1..100).map { star_json(SINCE - 30.days) }.join(",") + "]"
      boundary = "[" + ((1..50).map { star_json(SINCE - 1.day) } +
                        (1..50).map { star_json(SINCE + 1.day) }).join(",") + "]"
      recent = "[" + (1..100).map { star_json(SINCE + 2.days) }.join(",") + "]"
      link = HTTP::Headers{"Link" => %(<x?per_page=100&page=4>; rel="last")}
      pages = {1 => old, 2 => old, 3 => boundary, 4 => recent}
      with_server({"/stargazers" => pages}, response_headers: {1 => link}) do |api, server|
        times = api.star_times("octo/repo", SINCE)
        times.size.should eq(150)
        times.should eq(times.sort)
        # Page 1 (for the Link header), then 4 and 3; the boundary page ends
        # the walk before pages 2 and 1 are fetched again.
        server.seen.map(&.first.match!(/[?&]page=(\d+)/)[1]).should eq(["1", "4", "3"])
        api.truncated?.should be_false
      end
    end

    it "reports truncation when the window outruns the page budget" do
      recent = "[" + (1..100).map { star_json(SINCE + 1.day) }.join(",") + "]"
      link = HTTP::Headers{"Link" => %(<x?per_page=100&page=9>; rel="last")}
      pages = (1..9).to_h { |page| {page, recent} }
      with_server({"/stargazers" => pages}, response_headers: {1 => link}) do |api, _server|
        times = api.star_times("octo/repo", SINCE)
        times.size.should eq(100 * ActivityWeather::GitHubApi::STAR_PAGE_CAP)
        api.truncated?.should be_true
      end
    end
  end

  describe "error handling" do
    it "surfaces 404 with a token hint" do
      with_server({} of String => Hash(Int32, String), status: 404) do |api, _server|
        expect_raises(ActivityWeather::ApiError, /not found or not accessible/) do
          api.repo_info("octo/repo")
        end
      end
    end

    it "retries 5xx and succeeds when the server recovers" do
      hits = 0
      server = HTTP::Server.new do |context|
        hits += 1
        if hits < 3
          context.response.status_code = 502
        else
          context.response.content_type = "application/json"
          context.response.print(REPO_JSON)
        end
      end
      address = server.bind_unused_port "127.0.0.1"
      spawn { server.listen rescue nil }
      begin
        api = ActivityWeather::GitHubApi.new(api_base: "http://#{address}", backoff_base: 1.millisecond)
        api.repo_info("octo/repo").full_name.should eq("octo/repo")
        hits.should eq(3)
      ensure
        server.close
      end
    end

    it "treats an exhausted hourly quota as fatal" do
      headers = HTTP::Headers{"x-ratelimit-remaining" => "0", "x-ratelimit-reset" => "1780000000"}
      server = HTTP::Server.new do |context|
        headers.each { |key, values| values.each { |value| context.response.headers.add(key, value) } }
        context.response.status_code = 403
      end
      address = server.bind_unused_port "127.0.0.1"
      spawn { server.listen rescue nil }
      begin
        api = ActivityWeather::GitHubApi.new(api_base: "http://#{address}", backoff_base: 1.millisecond)
        expect_raises(ActivityWeather::ApiError, /rate limit exceeded/) do
          api.repo_info("octo/repo")
        end
      ensure
        server.close
      end
    end

    it "sends the token as a bearer header when given" do
      with_server({"/repos/octo/repo" => {1 => REPO_JSON}}) do |_api, server|
        api = ActivityWeather::GitHubApi.new(token: "tok", api_base: server.base)
        api.repo_info("octo/repo")
        server.seen.last[1]["Authorization"].should eq("Bearer tok")
      end
    end
  end
end
