require "sqlite3"
{% if flag?(:duckdb) %}
  require "duckdb"
{% end %}
require "option_parser"

require "./config"
require "./log"
require "./faro"

log_level = "warn"

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

    opts.on("-v", "--verbose", "Enable debug logging") do
      log_level = "debug"
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

# CLI verbose flag overrides config log level
config.log.level = log_level if log_level == "debug"

Faro.run(config)
