require "./spec_helper"

private INPUT_VARS = %w[INPUT_CONFIG INPUT_TOKEN INPUT_NO_COMMIT INPUT_COMMIT_MESSAGE
  INPUT_REPO INPUT_PERIOD GITHUB_WORKSPACE GITHUB_TOKEN GITHUB_ACTIONS]

private def with_clean_env(vars : Hash(String, String), &)
  saved = INPUT_VARS.to_h { |name| {name, ENV[name]?} }
  INPUT_VARS.each { |name| ENV.delete(name) }
  vars.each { |name, value| ENV[name] = value }
  yield
ensure
  saved.try &.each do |name, value|
    value ? (ENV[name] = value) : ENV.delete(name)
  end
end

describe ActivityWeather::Inputs do
  it "uses CLI values and defaults outside of actions" do
    with_clean_env({} of String => String) do
      inputs = ActivityWeather::Inputs.resolve("conf.yml", "/tmp/ws", false)
      inputs.config_path.should eq("conf.yml")
      inputs.config_explicit?.should be_true
      inputs.workspace.should eq("/tmp/ws")
      inputs.token.should be_nil
      inputs.commit?.should be_false
      inputs.repo.should be_nil
      inputs.period.should be_nil
      inputs.commit_message.should eq(ActivityWeather::Inputs::DEFAULT_COMMIT_MESSAGE)
    end
  end

  it "falls back to the conventional config path, marked as non-explicit" do
    with_clean_env({} of String => String) do
      inputs = ActivityWeather::Inputs.resolve
      inputs.config_path.should eq(ActivityWeather::Inputs::DEFAULT_CONFIG_PATH)
      inputs.config_explicit?.should be_false
    end
  end

  it "lets INPUT_* env vars win over CLI values" do
    env = {
      "INPUT_CONFIG"         => "action.yml",
      "GITHUB_WORKSPACE"     => "/github/workspace",
      "INPUT_TOKEN"          => "tok",
      "INPUT_COMMIT_MESSAGE" => "custom",
      "INPUT_REPO"           => "octo/repo",
      "INPUT_PERIOD"         => "14d",
      "GITHUB_ACTIONS"       => "true",
    }
    with_clean_env(env) do
      inputs = ActivityWeather::Inputs.resolve("conf.yml", "/tmp/ws", false)
      inputs.config_path.should eq("action.yml")
      inputs.config_explicit?.should be_true
      inputs.workspace.should eq("/github/workspace")
      inputs.token.should eq("tok")
      inputs.commit_message.should eq("custom")
      inputs.repo.should eq("octo/repo")
      inputs.period.should eq("14d")
      inputs.commit?.should be_true
    end
  end

  it "respects no_commit inside actions" do
    env = {"GITHUB_ACTIONS" => "true", "INPUT_NO_COMMIT" => "true"}
    with_clean_env(env) do
      ActivityWeather::Inputs.resolve.commit?.should be_false
    end
  end

  it "rejects a no_commit value that is neither true nor false" do
    with_clean_env({"INPUT_NO_COMMIT" => "tru"}) do
      expect_raises(ActivityWeather::ConfigError, /INPUT_NO_COMMIT/) do
        ActivityWeather::Inputs.resolve
      end
    end
  end

  it "commits locally only with the explicit flag" do
    with_clean_env({} of String => String) do
      ActivityWeather::Inputs.resolve(commit_flag: true).commit?.should be_true
      ActivityWeather::Inputs.resolve.commit?.should be_false
    end
  end

  it "falls back to GITHUB_TOKEN" do
    with_clean_env({"GITHUB_TOKEN" => "ghtok"}) do
      ActivityWeather::Inputs.resolve.token.should eq("ghtok")
    end
  end
end
