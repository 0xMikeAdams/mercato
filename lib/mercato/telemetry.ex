defmodule Mercato.Telemetry do
  @moduledoc """
  Telemetry helpers for Mercato events.
  """

  @event_prefix [:mercato]

  def execute(event, measurements \\ %{}, metadata \\ %{}) when is_list(event) do
    :telemetry.execute(@event_prefix ++ event, measurements, metadata)
  end
end
