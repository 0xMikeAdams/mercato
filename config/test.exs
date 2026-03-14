import Config

# Configure the Mercato repository for testing
config :mercato, Mercato.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mercato_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Print only warnings and errors during test
config :logger, level: :warning

# Set environment for Mercato
config :mercato, :env, :test

config :mercato, Mercato.TestEndpoint,
  url: [host: "example.com"],
  secret_key_base: String.duplicate("a", 64),
  server: false,
  debug_errors: true
