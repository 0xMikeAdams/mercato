defmodule Mercato.Cart.Manager do
  @moduledoc """
  GenServer for managing in-memory cart state with periodic database persistence.

  Each active cart has its own GenServer process that maintains the cart state in memory
  for fast access and updates. The state is periodically persisted to the database and
  on cart expiration.

  ## Features

  - In-memory cart state for fast operations
  - Periodic database persistence (configurable interval)
  - Automatic cart expiration and cleanup
  - Cart lifecycle management (creation, updates, expiration)

  ## Usage

      # Start a cart manager process
      {:ok, pid} = Mercato.Cart.Manager.start_link(cart_id: cart_id)

      # Get cart state
      cart = Mercato.Cart.Manager.get_cart(cart_id)

      # Update cart state
      :ok = Mercato.Cart.Manager.update_cart(cart_id, updated_cart)

      # Stop cart manager (persists to database)
      :ok = Mercato.Cart.Manager.stop(cart_id)
  """

  use GenServer
  require Logger

  alias Mercato
  alias Mercato.Cart.Cart

  @persist_interval :timer.minutes(5)
  @cleanup_check_interval :timer.minutes(10)

  # Client API

  @doc """
  Starts a Cart Manager GenServer for the given cart ID.
  """
  def start_link(opts) do
    cart_id = Keyword.fetch!(opts, :cart_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(cart_id))
  end

  @doc """
  Gets the current cart state from the GenServer.
  """
  def get_cart(cart_id) do
    case lookup(cart_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_cart)

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Updates the cart state in the GenServer.
  """
  def update_cart(cart_id, cart) do
    case lookup(cart_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:update_cart, cart})

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Persists the cart to the database immediately.
  """
  def persist(cart_id) do
    case lookup(cart_id) do
      {:ok, pid} ->
        GenServer.call(pid, :persist)

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Stops the Cart Manager GenServer, persisting the cart to the database.
  """
  def stop(cart_id) do
    case lookup(cart_id) do
      {:ok, pid} ->
        GenServer.stop(pid, :normal)

      :error ->
        :ok
    end
  end

  @doc """
  Checks if a Cart Manager is running for the given cart ID.
  """
  def alive?(cart_id) do
    case lookup(cart_id) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    cart_id = Keyword.fetch!(opts, :cart_id)

    case repo().get(Cart, cart_id) do
      nil ->
        {:stop, :cart_not_found}

      cart ->
        # Schedule periodic persistence
        schedule_persist()

        # Schedule expiration check
        schedule_expiration_check()

        state = %{
          cart: cart,
          cart_id: cart_id,
          dirty: false
        }

        Logger.debug("Cart Manager started for cart #{cart_id}")
        {:ok, state}
    end
  end

  @impl true
  def handle_call(:get_cart, _from, state) do
    {:reply, state.cart, state}
  end

  @impl true
  def handle_call({:update_cart, cart}, _from, state) do
    new_state = %{state | cart: cart, dirty: true}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:persist, _from, state) do
    case persist_to_database(state) do
      {:ok, updated_cart} ->
        new_state = %{state | cart: updated_cart, dirty: false}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:persist, state) do
    new_state =
      if state.dirty do
        case persist_to_database(state) do
          {:ok, updated_cart} ->
            %{state | cart: updated_cart, dirty: false}

          {:error, reason} ->
            Logger.error("Failed to persist cart #{state.cart_id}: #{inspect(reason)}")
            state
        end
      else
        state
      end

    schedule_persist()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_expiration, state) do
    now = DateTime.utc_now()

    if DateTime.compare(state.cart.expires_at, now) == :lt do
      Logger.info("Cart #{state.cart_id} has expired, stopping manager")
      {:stop, :normal, state}
    else
      schedule_expiration_check()
      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Persist cart one final time before stopping
    if state.dirty do
      case persist_to_database(state) do
        {:ok, _} ->
          Logger.debug("Cart #{state.cart_id} persisted on termination")

        {:error, reason} ->
          Logger.error("Failed to persist cart #{state.cart_id} on termination: #{inspect(reason)}")
      end
    end

    :ok
  end

  # Private Functions

  defp via_tuple(cart_id) do
    {:via, Registry, {Mercato.Cart.Manager.Registry, cart_id}}
  end

  defp lookup(cart_id) do
    case Registry.lookup(Mercato.Cart.Manager.Registry, cart_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp persist_to_database(state) do
    cart = state.cart |> repo().preload(:items)

    case repo().update(Cart.totals_changeset(cart, %{
      subtotal: cart.subtotal,
      discount_total: cart.discount_total,
      shipping_total: cart.shipping_total,
      tax_total: cart.tax_total,
      grand_total: cart.grand_total
    })) do
      {:ok, updated_cart} ->
        {:ok, updated_cart}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp repo, do: Mercato.repo()

  defp schedule_persist do
    Process.send_after(self(), :persist, @persist_interval)
  end

  defp schedule_expiration_check do
    Process.send_after(self(), :check_expiration, @cleanup_check_interval)
  end
end
