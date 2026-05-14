# Parses human-friendly time duration strings.
#
# Supported formats:
#   "5"       → 5.seconds  (bare number = seconds)
#   "5s"      → 5.seconds
#   "5m"      → 5.minutes
#   "5h"      → 5.hours
#   "5d"      → 5.days
#
# Raises on invalid input.  Always returns Time::Span.
module Faro
  module TimeParser
    def self.parse(str : String) : Time::Span
      s = str.strip
      raise "invalid time string: '#{str}'" if s.empty?

      seconds = case s
      when /^(-?\d+(?:\.\d+)?)([smhd])$/
        val = $1.to_f64
        case $2
        when "s" then val
        when "m" then val * 60
        when "h" then val * 3600
        when "d" then val * 86400
        else          val
        end
      when /^(-?\d+(?:\.\d+)?)$/
        $1.to_f64
      else
        raise "invalid time string: '#{str}'"
      end

      seconds.seconds
    end
  end
end
