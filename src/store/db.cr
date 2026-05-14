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

    MEMORY_TAG    = ":memory:"
    ENCODED_MEMORY_SQLITE  = "%3Amemory%3A"
    ENCODED_MEMORY_DUCKDB  = "[:memory:]"

    def self.new(uri : String) : AbstractBackend
      normalized = normalize_uri(uri)

      if normalized.starts_with?(DUCKDB_SCHEME)
        DuckDbBackend.new(normalized)
      elsif normalized.starts_with?(SQLITE_SCHEME)
        SqliteBackend.new(normalized)
      else
        raise "Unsupported db URI: '#{uri}'. Use duckdb:// or sqlite3:// scheme. " \
              "Examples: duckdb://:memory:, sqlite3://:memory:, duckdb:///data/faro.db, sqlite3:///data/faro.db"
      end
    end

    private def self.normalize_uri(uri : String) : String
      if uri.starts_with?(SQLITE_SCHEME) && !uri.starts_with?(SQLITE_SCHEME + ENCODED_MEMORY_SQLITE)
        # sqlite3://:memory: → sqlite3://%3Amemory%3A
        uri.sub(SQLITE_SCHEME + MEMORY_TAG, SQLITE_SCHEME + ENCODED_MEMORY_SQLITE)
      elsif uri.starts_with?(DUCKDB_SCHEME) && !uri.starts_with?(DUCKDB_SCHEME + ENCODED_MEMORY_DUCKDB)
        # duckdb://:memory: → duckdb://[:memory:]
        uri.sub(DUCKDB_SCHEME + MEMORY_TAG, DUCKDB_SCHEME + ENCODED_MEMORY_DUCKDB)
      else
        uri
      end
    end
  end
end
