defmodule Mercato.Cart.Cleanup do
  @moduledoc """
  Optional periodic worker that expires stale carts.

  Mercato does NOT start this — cart state lives in the database, so expiration is a
  host concern. Either call `Mercato.Cart.expire_stale_carts/0` from your own scheduler
  (cron/Oban), or add this worker to your supervision tree for an in-process sweep:

      children = [
        {Mercato.Cart.Cleanup, interval: :timer.hours(1)}
      ]

  ## Options

  - `:interval` - milliseconds between sweeps (default: 1 hour)
  - `:name` - registered name (default: `Mercato.Cart.Cleanup`)
  """

  use GenServer
  require Logger

  @default_interval :timer.hours(1)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    schedule(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:sweep, %{interval: interval} = state) do
    if Mercato.repo_started?() do
      count = Mercato.Cart.expire_stale_carts()
      if count > 0, do: Logger.info("Mercato.Cart.Cleanup expired #{count} stale cart(s)")
    end

    schedule(interval)
    {:noreply, state}
  end

  defp schedule(interval), do: Process.send_after(self(), :sweep, interval)
end
