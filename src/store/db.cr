require "db"
require "./backends/abstract_backend"
require "./backends/sqlite_backend"
require "./backends/duckdb_backend"

module Faro::Store
  # Factory that creates the appropriate database backend
  # based on the URI scheme.
  module Db
    DUCKDB_SCHEME = "duckdb://"
    SQLITE_SCHEME = "sqlite3://"

    def self.new(uri : String) : AbstractBackend
      if uri.starts_with?(DUCKDB_SCHEME)
        DuckDbBackend.new(uri)
      elsif uri.starts_with?(SQLITE_SCHEME)
        SqliteBackend.new(uri)
      else
        raise "Unsupported db URI: '#{uri}'. Use duckdb:// or sqlite3:// scheme. " \
              "Examples: duckdb://[:memory:], sqlite3:///data/faro.db"
      end
    end
  end
end
