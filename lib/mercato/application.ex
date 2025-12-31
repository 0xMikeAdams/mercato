defmodule Mercato.Application do
  @moduledoc """
  The Mercato OTP Application.

  This module starts and supervises the core components of the Mercato e-commerce engine:
  - Ecto Repository for database access
  - Phoenix PubSub for real-time event broadcasting
  - Cart Manager DynamicSupervisor for managing cart GenServers
  - Subscription Scheduler for automated subscription renewals
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Ecto Repository
      Mercato.Repo,

      # Phoenix PubSub for real-time events
      {Phoenix.PubSub, name: Mercato.PubSub},

      # Registry for Cart Manager GenServers
      {Registry, keys: :unique, name: Mercato.Cart.Manager.Registry},

      # DynamicSupervisor for Cart GenServers
      Mercato.Cart.Manager.Supervisor,

      # Subscription renewal scheduler (will be fully implemented in future tasks)
      Mercato.Subscriptions.Scheduler
    ]

    opts = [strategy: :one_for_one, name: Mercato.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
