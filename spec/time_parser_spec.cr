require "spec"
require "../src/time_parser"

describe Faro::TimeParser do
  it "parses bare number as seconds" do
    Faro::TimeParser.parse("5").should eq 5.seconds
  end

  it "parses '5s' as 5 seconds" do
    Faro::TimeParser.parse("5s").should eq 5.seconds
  end

  it "parses '5m' as 5 minutes" do
    Faro::TimeParser.parse("5m").should eq 5.minutes
  end

  it "parses '5h' as 5 hours" do
    Faro::TimeParser.parse("5h").should eq 5.hours
  end

  it "parses '5d' as 5 days" do
    Faro::TimeParser.parse("5d").should eq 5.days
  end

  it "parses decimal values" do
    Faro::TimeParser.parse("1.5m").total_seconds.should be_close(90.0, 1e-9)
    Faro::TimeParser.parse("0.5h").total_seconds.should be_close(1800.0, 1e-9)
  end

  it "raises on empty string" do
    expect_raises(Exception, /invalid/) { Faro::TimeParser.parse("") }
    expect_raises(Exception, /invalid/) { Faro::TimeParser.parse("  ") }
  end

  it "raises on invalid format" do
    expect_raises(Exception, /invalid/) { Faro::TimeParser.parse("abc") }
    expect_raises(Exception, /invalid/) { Faro::TimeParser.parse("5x") }
    expect_raises(Exception, /invalid/) { Faro::TimeParser.parse("5 years") }
  end
end
