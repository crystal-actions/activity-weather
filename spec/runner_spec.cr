require "./spec_helper"
require "file_utils"
require "./support/factories"
require "./support/fake_github_source"

private def with_workspace(&)
  dir = File.tempname("aw-runner")
  Dir.mkdir_p(dir)
  output_file = File.join(dir, "github_output")
  File.write(output_file, "")
  saved_repo = ENV["GITHUB_REPOSITORY"]?
  saved_output = ENV["GITHUB_OUTPUT"]?
  ENV.delete("GITHUB_REPOSITORY")
  ENV["GITHUB_OUTPUT"] = output_file
  log = IO::Memory.new
  saved_io = ActivityWeather::Annotations.io
  ActivityWeather::Annotations.io = log
  begin
    yield dir, -> { parse_outputs(output_file) }, log
  ensure
    ActivityWeather::Annotations.io = saved_io
    saved_repo ? (ENV["GITHUB_REPOSITORY"] = saved_repo) : ENV.delete("GITHUB_REPOSITORY")
    saved_output ? (ENV["GITHUB_OUTPUT"] = saved_output) : ENV.delete("GITHUB_OUTPUT")
    FileUtils.rm_rf(dir)
  end
end

private def parse_outputs(path : String) : Hash(String, String)
  File.read_lines(path).compact_map do |line|
    key, _, value = line.partition('=')
    line.includes?('=') ? {key, value} : nil
  end.to_h
end

private def busy_source : FakeGitHubSource
  source = FakeGitHubSource.new
  from = Factory::AS_OF - 7.days
  source.commits_value = (0...35).map { |i| Factory.commit(from + (i % 7).days + (i % 5).hours, "dev#{i % 3}") }
  source.star_times_value = [from + 1.day, from + 2.days]
  source
end

private def run(config : ActivityWeather::Config, source : ActivityWeather::GitHubSource,
                workspace : String) : Int32
  ActivityWeather::Runner.new(config, source, workspace, as_of: Factory::AS_OF).run
end

describe ActivityWeather::Runner do
  it "renders, writes, and reports every output" do
    with_workspace do |dir, outputs, _log|
      config = ActivityWeather::Config.parse("repo: octo/repo")
      run(config, busy_source, dir).should eq(0)

      svg = File.read(File.join(dir, "ACTIVITY_WEATHER.svg"))
      svg.should start_with("<svg")
      svg.should contain("octo/repo")

      recorded = outputs.call
      recorded["condition"].should eq("sunny")
      recorded["temperature"].to_f.should be > 20.0
      recorded["phrase"].should_not be_empty
      recorded["paths"].should eq("ACTIVITY_WEATHER.svg")
      recorded["width"].should eq("480")
      recorded["height"].should eq("240")
      recorded["changed"].should eq("false")
    end
  end

  it "writes every target of a multi-output config before reporting" do
    yaml = <<-YAML
      repo: octo/repo
      outputs:
        - path: docs/weather.svg
        - path: docs/badge.svg
          style: minimal
      YAML
    with_workspace do |dir, outputs, _log|
      run(ActivityWeather::Config.parse(yaml), busy_source, dir).should eq(0)
      File.exists?(File.join(dir, "docs/weather.svg")).should be_true
      File.exists?(File.join(dir, "docs/badge.svg")).should be_true
      outputs.call["paths"].should eq("docs/weather.svg,docs/badge.svg")
    end
  end

  it "falls back to GITHUB_REPOSITORY and errors without either" do
    with_workspace do |dir, _outputs, log|
      source = busy_source
      ENV["GITHUB_REPOSITORY"] = "env/repo"
      begin
        run(ActivityWeather::Config.empty, source, dir).should eq(0)
        source.requested_repos.first.should eq("env/repo")
      ensure
        ENV.delete("GITHUB_REPOSITORY")
      end

      run(ActivityWeather::Config.empty, busy_source, dir).should eq(1)
      log.to_s.should contain("::error::")
      log.to_s.should contain("`repo` is not set")
    end
  end

  it "skips the star and release fetches when disabled" do
    yaml = "repo: octo/repo\nmetrics:\n  stars: false\n  releases: false"
    with_workspace do |dir, _outputs, _log|
      source = busy_source
      run(ActivityWeather::Config.parse(yaml), source, dir).should eq(0)
      # repo_info + commits + issues only.
      source.requested_repos.size.should eq(3)
    end
  end

  it "reports an empty window as weather, not an error" do
    with_workspace do |dir, outputs, _log|
      run(ActivityWeather::Config.parse("repo: octo/repo"), FakeGitHubSource.new, dir).should eq(0)
      outputs.call["condition"].should eq("snowy")
    end
  end

  it "announces truncated listings without failing" do
    with_workspace do |dir, _outputs, log|
      source = busy_source
      source.truncated = true
      run(ActivityWeather::Config.parse("repo: octo/repo"), source, dir).should eq(0)
      log.to_s.should contain("::notice::")
      log.to_s.should contain("floor")
    end
  end

  it "turns an API failure into an error annotation and exit 1" do
    with_workspace do |dir, _outputs, log|
      source = FakeGitHubSource.new
      source.error = ActivityWeather::ApiError.new("rate limit exceeded")
      run(ActivityWeather::Config.parse("repo: octo/repo"), source, dir).should eq(1)
      log.to_s.should contain("::error::rate limit exceeded")
      File.exists?(File.join(dir, "ACTIVITY_WEATHER.svg")).should be_false
    end
  end
end
