defmodule Mercato.Controllers.Serializer do
  @moduledoc false

  # Fields stripped from every serialized struct. These are internal/sensitive and
  # must never reach an API response, regardless of which schema is being rendered.
  @always_drop [:__meta__, :idempotency_key, :payment_transaction_id]

  # Additional per-schema internal fields to drop. Keyed by struct module.
  @struct_drop %{
    Mercato.Orders.Order => [:source_cart_id]
  }

  def serialize(value) do
    do_serialize(value)
  end

  defp do_serialize(%Ecto.Association.NotLoaded{}), do: nil
  defp do_serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp do_serialize(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp do_serialize(%Date{} = d), do: Date.to_iso8601(d)
  defp do_serialize(%Time{} = t), do: Time.to_iso8601(t)

  defp do_serialize(%module{} = struct) do
    drop = @always_drop ++ Map.get(@struct_drop, module, [])

    struct
    |> Map.from_struct()
    |> Map.drop(drop)
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      case val do
        %Ecto.Association.NotLoaded{} ->
          acc

        _ ->
          Map.put(acc, key, do_serialize(val))
      end
    end)
  end

  defp do_serialize(list) when is_list(list), do: Enum.map(list, &do_serialize/1)

  defp do_serialize(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      Map.put(acc, key, do_serialize(val))
    end)
  end

  defp do_serialize(other), do: other
end
