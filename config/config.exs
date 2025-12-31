import Config

# Configure Mercato's Ecto repository
config :mercato,
  ecto_repos: [Mercato.Repo]

# Import environment specific config
import_config "#{config_env()}.exs"
