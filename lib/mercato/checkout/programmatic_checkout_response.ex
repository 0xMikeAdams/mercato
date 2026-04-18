defmodule Mercato.Checkout.ProgrammaticCheckoutResponse do
  @moduledoc """
  Stable top-level response returned by the programmatic checkout API.
  """

  alias Mercato.Checkout.{
    Address,
    BuyerIdentity,
    CheckoutLineItem,
    CheckoutPriceBreakdown,
    CheckoutSession
  }

  @enforce_keys [
    :status,
    :cart_id,
    :cart_status,
    :currency,
    :line_items,
    :price_breakdown,
    :retry_safe
  ]
  defstruct [
    :status,
    :cart_id,
    :cart_token,
    :cart_status,
    :currency,
    :idempotency_key,
    :buyer_identity,
    :shipping_address,
    :shipping_method,
    :line_items,
    :price_breakdown,
    :checkout_session,
    :retry_safe
  ]

  @type t :: %__MODULE__{
          status: String.t(),
          cart_id: String.t(),
          cart_token: String.t() | nil,
          cart_status: String.t(),
          currency: String.t(),
          idempotency_key: String.t() | nil,
          buyer_identity: BuyerIdentity.t() | nil,
          shipping_address: Address.t() | nil,
          shipping_method: String.t() | nil,
          line_items: [CheckoutLineItem.t()],
          price_breakdown: CheckoutPriceBreakdown.t(),
          checkout_session: CheckoutSession.t() | nil,
          retry_safe: boolean()
        }
end
