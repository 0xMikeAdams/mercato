# Mercato Configuration Template
# Copy the relevant sections to your config files

# config/config.exs
config :mercato, Mercato.Repo,
  database: "your_app_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :mercato,
  ecto_repos: [Mercato.Repo],
  # Set this to your real payment gateway module before processing live payments.
  payment_gateway: nil,
  # Shipping calculator configuration
  shipping_calculator: Mercato.ShippingCalculators.FlatRate,
  # Tax calculator configuration
  tax_calculator: Mercato.TaxCalculators.Simple,
  # Store settings
  store_settings: %{
    currency: "USD",
    locale: "en",
    default_tax_rate: 0.08,
    store_address: %{
      line1: "123 Store St",
      city: "Store City",
      state: "ST",
      postal_code: "12345",
      country: "US"
    }
  }

# config/dev.exs
config :mercato, Mercato.Repo,
  database: "your_app_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# config/test.exs
config :mercato, Mercato.Repo,
  database: "your_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# config/prod.exs
config :mercato, Mercato.Repo,
  # Configure your production database URL
  # url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true

# Optional convenience scheduler
#
# Add this child in your host application's supervision tree if you want the
# built-in renewal timer:
#
#   Mercato.Subscriptions.scheduler_child_spec(enabled: true, interval: :timer.hours(1))
