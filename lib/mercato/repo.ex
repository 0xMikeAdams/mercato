defmodule Mercato.Repo do
  @moduledoc """
  The Ecto repository for Mercato.

  Mercato can run on either:

  - your application's repo (recommended), configured via `config :mercato, :repo, MyApp.Repo`
  - `Mercato.Repo` (defaults to this)

  ## Configuration

  If you want Mercato to use your application's repo:

      # config/config.exs
      config :mercato, :repo, MyApp.Repo

  If you want to use `Mercato.Repo`, configure it like any other `Ecto.Repo`:

      # config/config.exs
      config :mercato, Mercato.Repo,
        database: "mercato_dev",
        username: "postgres",
        password: "postgres",
        hostname: "localhost"

  ## Usage

  Mercato will start `Mercato.Repo` only when `config :mercato, :repo` is set to `Mercato.Repo`.
  Otherwise, your application is responsible for starting its own repo.

      import Ecto.Query

      Mercato.Repo.all(from p in Mercato.Catalog.Product, where: p.status == "published")
  """

  use Ecto.Repo,
    otp_app: :mercato,
    adapter: Ecto.Adapters.Postgres
end
