# Golden-file assertions. Regenerate with: UPDATE_GOLDEN=1 crystal spec
module Golden
  def self.assert(name : String, actual : String, file = __FILE__, line = __LINE__) : Nil
    path = (SpecHelper::FIXTURES / "golden" / name).to_s
    if ENV["UPDATE_GOLDEN"]?
      Dir.mkdir_p(File.dirname(path))
      File.write(path, actual)
    end
    unless File.exists?(path)
      fail "golden file missing: #{path} (run UPDATE_GOLDEN=1 crystal spec)", file: file, line: line
    end
    actual.should eq(File.read(path)), file: file, line: line
  end
end
