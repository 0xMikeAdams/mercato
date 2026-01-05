defmodule Mercato.Controllers.Serializer do
  @moduledoc false

  def serialize(value) do
    do_serialize(value)
  end

  defp do_serialize(%Ecto.Association.NotLoaded{}), do: nil
  defp do_serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp do_serialize(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp do_serialize(%Date{} = d), do: Date.to_iso8601(d)
  defp do_serialize(%Time{} = t), do: Time.to_iso8601(t)

  defp do_serialize(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
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
