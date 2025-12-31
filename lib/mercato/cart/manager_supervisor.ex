defmodule Mercato.Cart.Manager.Supervisor do
  @moduledoc """
  DynamicSupervisor for Cart Manager GenServers.

  This supervisor manages the lifecycle of individual cart manager processes,
  allowing carts to be started and stopped dynamically as needed.

  ## Usage

      # Start a cart manager
      {:ok, pid} = Mercato.Cart.Manager.Supervisor.start_cart(cart_id)

      # Stop a cart manager
      :ok = Mercato.Cart.Manager.Supervisor.stop_cart(cart_id)
  """

  use DynamicSupervisor

  alias Mercato.Cart.Manager

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a Cart Manager GenServer for the given cart ID.
  """
  def start_cart(cart_id) do
    spec = {Manager, cart_id: cart_id}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stops the Cart Manager GenServer for the given cart ID.
  """
  def stop_cart(cart_id) do
    Manager.stop(cart_id)
  end

  @doc """
  Returns a list of all active cart manager PIDs.
  """
  def active_carts do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
