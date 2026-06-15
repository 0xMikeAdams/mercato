defmodule Mercato.Orders.NumberGenerator do
  @moduledoc """
  Generates unique, human-readable order numbers of the form `ORD-<unix>-<random>`.

  Uniqueness is backstopped by the `orders.order_number` unique index; this generator
  retries on the (rare) collision so callers get a fresh number.
  """

  alias Mercato.Orders.Order

  @doc """
  Returns `{:ok, order_number}` with a number not currently present in the orders table.
  """
  @spec generate() :: {:ok, String.t()}
  def generate do
    order_number = build()

    case repo().get_by(Order, order_number: order_number) do
      nil -> {:ok, order_number}
      _existing -> generate()
    end
  end

  defp build do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    random = :rand.uniform(9999) |> Integer.to_string() |> String.pad_leading(4, "0")
    "ORD-#{timestamp}-#{random}"
  end

  defp repo, do: Mercato.repo()
end
