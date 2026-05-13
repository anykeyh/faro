require "spec"
require "../src/store/duckdb"

# Returns a fresh in‑memory store with schema already set up.
# Each call creates a new database connection with its own schema.
def fresh_store : Faro::Store::DuckDB
  store = Faro::Store::DuckDB.new(":memory:")
  store.setup_schema
  store
end
