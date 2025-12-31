import Config

# Configure the Mercato repository for development
config :mercato, Mercato.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mercato_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Configure logger for development
config :logger, :console, format: "[$level] $message\n"
