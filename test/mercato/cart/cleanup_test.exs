defmodule Mercato.Cart.CleanupTest do
  # async: false — shared-mode sandbox so the Cleanup GenServer (a separate process)
  # can reach the test connection.
  use ExUnit.Case, async: false

  alias Mercato.{Cart, Repo}
  alias Mercato.Cart.Cleanup

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  defp stale_cart do
    {:ok, cart} =
      Cart.create_cart(%{cart_token: "stale-#{System.unique_integer([:positive])}"})

    past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
    {:ok, cart} = cart |> Ecto.Changeset.change(expires_at: past) |> Repo.update()
    cart
  end

  describe "Cart.expire_stale_carts/0" do
    test "abandons expired active carts and leaves fresh ones active" do
      stale = stale_cart()

      {:ok, fresh} =
        Cart.create_cart(%{cart_token: "fresh-#{System.unique_integer([:positive])}"})

      assert Cart.expire_stale_carts() >= 1

      assert Repo.get!(Cart.Cart, stale.id).status == "abandoned"
      assert Repo.get!(Cart.Cart, fresh.id).status == "active"
    end

    test "does not touch non-active carts" do
      {:ok, cart} =
        Cart.create_cart(%{cart_token: "converted-#{System.unique_integer([:positive])}"})

      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        cart
        |> Ecto.Changeset.change(status: "converted", expires_at: past)
        |> Repo.update()

      Cart.expire_stale_carts()

      assert Repo.get!(Cart.Cart, cart.id).status == "converted"
    end
  end

  describe "Cart.Cleanup worker" do
    test "expires stale carts when it sweeps" do
      stale = stale_cart()

      {:ok, pid} = Cleanup.start_link(interval: :timer.hours(1))
      send(pid, :sweep)
      # Synchronous call flushes the mailbox, so :sweep has been handled by the time it returns.
      :sys.get_state(pid)

      assert Repo.get!(Cart.Cart, stale.id).status == "abandoned"

      GenServer.stop(pid)
    end
  end
end
