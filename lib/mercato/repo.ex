defmodule Mercato.Repo do
  @moduledoc """
  The Ecto repository for Mercato.

  This module provides database access for all Mercato schemas. It can be configured
  to use PostgreSQL, MySQL, or any other Ecto-supported database adapter.

  ## Configuration

  Configure the repository in your application's config files:

      # config/config.exs
      config :mercato, Mercato.Repo,
        database: "mercato_dev",
        username: "postgres",
        password: "postgres",
        hostname: "localhost"

      config :mercato,
        ecto_repos: [Mercato.Repo]

  ## Usage

  The repository is automatically started as part of the Mercato application
  supervision tree. You can use it directly for custom queries:

      import Ecto.Query

      Mercato.Repo.all(from p in Mercato.Catalog.Product, where: p.status == "published")
  """

  use Ecto.Repo,
    otp_app: :mercato,
    adapter: Ecto.Adapters.Postgres
end
