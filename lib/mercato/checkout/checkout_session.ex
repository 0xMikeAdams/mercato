defmodule Mercato.Checkout.CheckoutSession do
  @moduledoc """
  Checkout handoff or payment session returned by programmatic checkout APIs.
  """

  alias Mercato.Checkout.CheckoutPriceBreakdown

  @enforce_keys [:id, :kind, :status, :currency, :totals, :retry_safe]
  defstruct [
    :id,
    :kind,
    :status,
    :provider,
    :currency,
    :totals,
    :redirect_url,
    :payment_client_secret,
    :provider_reference,
    :expires_at,
    :idempotency_key,
    :retry_safe,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          kind: String.t(),
          status: String.t(),
          provider: String.t() | nil,
          currency: String.t(),
          totals: CheckoutPriceBreakdown.t(),
          redirect_url: String.t() | nil,
          payment_client_secret: String.t() | nil,
          provider_reference: String.t() | nil,
          expires_at: DateTime.t() | nil,
          idempotency_key: String.t() | nil,
          retry_safe: boolean(),
          metadata: map()
        }
end
