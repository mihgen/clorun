require '../lib/options'

describe "Command line parameters" do
  it "should return default target if not specifying target and test" do
    opts = Clorun::Options.new(["-c", "default"])
    "all".should == opts.target
  end
  it "should return that -c CONFIG is mandatory if not specify config" do
    opts = Clorun::Options.new(["feature"])
    opts.config.should_not == nil
  end
end


