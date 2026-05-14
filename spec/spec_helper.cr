require "spec"
require "sqlite3"
require "duckdb"

require "../src/store/db"

# Returns a fresh in‑memory store with schema already set up.
# Each call creates a new database connection with its own schema.
def fresh_store(backend : Symbol = :sqlite) : Faro::Store::AbstractBackend
  uri = case backend
        when :sqlite
          # Use a unique URI per call so Crystal's connection pool doesn't reuse
          # the same in-memory database across tests.
          "sqlite3://%3Amemory%3A?max_pool_size=1"
        when :duckdb
          "duckdb://[:memory:]?max_pool_size=1"
        else
          raise "Unknown backend: #{backend}"
        end
  store = Faro::Store::Db.new(uri)
  store.setup_schema
  store
end
