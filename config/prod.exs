import Config

# Configure the Mercato repository for production
# Note: Host applications should override these settings in their runtime.exs
config :mercato, Mercato.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

# Configure logger for production
config :logger, level: :info
