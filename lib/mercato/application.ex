defmodule Mercato.Application do
  @moduledoc """
  The Mercato OTP Application.

  This module starts and supervises the core components of the Mercato e-commerce engine:
  - Optional Ecto repository (only if `config :mercato, :repo, Mercato.Repo`)
  - Optional Phoenix PubSub (only if `config :mercato, :pubsub, Mercato.PubSub`)

  Cart state lives in the database; there is no per-cart process. Expiring stale carts
  is the host's choice — call `Mercato.Cart.expire_stale_carts/0` from a scheduler, or
  add the optional `Mercato.Cart.Cleanup` worker to your supervision tree.
  """

  use Application

  @impl true
  def start(_type, _args) do
    repo = Mercato.repo()
    pubsub = Mercato.pubsub()

    children =
      []
      |> maybe_add_repo(repo)
      |> maybe_add_pubsub(pubsub)

    opts = [strategy: :one_for_one, name: Mercato.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children, Mercato.Repo), do: children ++ [Mercato.Repo]
  defp maybe_add_repo(children, _repo), do: children

  defp maybe_add_pubsub(children, Mercato.PubSub),
    do: children ++ [{Phoenix.PubSub, name: Mercato.PubSub}]

  defp maybe_add_pubsub(children, _pubsub), do: children
end
