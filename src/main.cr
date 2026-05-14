require "sqlite3"
require "duckdb"

require "./config"
require "./faro"


config = begin
  path = "./config.yml"
  from_stdin = false

  OptionParser.parse do |opts|
    opts.banner = "Usage: faro [options]"

    opts.on("-c FILE", "--config FILE", "Path to config file (default: ./config.yml)") do |file|
      path = file
    end

    opts.on("-i", "--stdin", "Read config from stdin") do
      from_stdin = true
    end

    opts.on("-h", "--help", "Show help") do
      puts opts
      exit 0
    end
  end

  if from_stdin
    Faro::Config.from_yaml(STDIN.gets_to_end)
  else
    Faro::Config.load(path)
  end
end

Faro.run(config)
