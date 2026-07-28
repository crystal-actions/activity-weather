require "option_parser"

module ActivityWeather
  module CLI
    def self.run(argv = ARGV) : Int32
      config_flag = nil
      workspace_flag = nil
      commit_flag = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: activity-weather [options]"
        opts.on("-c PATH", "--config PATH", "Config file (default: #{Inputs::DEFAULT_CONFIG_PATH})") { |value| config_flag = value }
        opts.on("-w DIR", "--workspace DIR", "Directory output paths are relative to (default: cwd)") { |value| workspace_flag = value }
        opts.on("--commit", "Commit and push the generated files") { commit_flag = true }
        opts.on("-v", "--version", "Print version") do
          puts VERSION
          exit 0
        end
        opts.on("-h", "--help", "Show help") do
          puts opts
          exit 0
        end
        opts.invalid_option do |flag|
          STDERR.puts "unknown option: #{flag}"
          STDERR.puts opts
          exit 2
        end
      end
      parser.parse(argv)

      # First line of every run. The action ships as a container image, and an
      # image tag can move under a pinned action ref, so "which build is this"
      # has to be answerable from the log alone.
      Annotations.io.puts "activity-weather v#{VERSION}"

      begin
        inputs = Inputs.resolve(config_flag, workspace_flag, commit_flag)
      rescue ex : ConfigError
        Annotations.error(ex.message || "invalid action input")
        return 1
      end

      begin
        config = Config.load(inputs.config_path, explicit: inputs.config_explicit?)
        # The `repo`/`period` inputs beat the config, for the zero-config
        # case where there is no file to write them in; re-validate so a bad
        # override fails the same way a bad config key would.
        if repo = inputs.repo
          config.repo = repo
        end
        if period = inputs.period
          config.period = period
        end
        config.validate!
      rescue ex : ConfigError
        Annotations.error(ex.message || "invalid config", file: inputs.config_path, line: ex.line)
        return 1
      end

      pool = HTTPPool.new
      github_source = GitHubApi.new(inputs.token, pool: pool)
      committer = inputs.commit? ? Committer.new(inputs.workspace, inputs.commit_message) : nil

      begin
        Runner.new(config, github_source, inputs.workspace, committer).run
      ensure
        pool.close
      end
    end
  end
end
