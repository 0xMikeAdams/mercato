defmodule Mercato.Runtime do
  @moduledoc """
  Runtime validation helpers for Mercato integrations.
  """

  alias Mercato.PaymentGateways.Dummy

  def payment_gateway do
    Application.get_env(:mercato, :payment_gateway)
  end

  def fetch_payment_gateway(opts \\ []) do
    gateway = Keyword.get(opts, :payment_gateway, payment_gateway())
    allow_dummy_gateway? = Keyword.get(opts, :allow_dummy_gateway, false)

    case gateway do
      nil ->
        {:error, :payment_gateway_not_configured}

      Dummy when not allow_dummy_gateway? ->
        {:error, :dummy_payment_gateway_not_allowed}

      module when is_atom(module) ->
        {:ok, module}

      _ ->
        {:error, :payment_gateway_not_configured}
    end
  end
end
