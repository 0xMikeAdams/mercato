defmodule Mercato.Checkout.CheckoutPriceBreakdown do
  @moduledoc """
  Explicit deterministic totals returned before checkout handoff or payment creation.
  """

  alias Mercato.Checkout.Money

  @enforce_keys [
    :currency,
    :subtotal,
    :discount_total,
    :shipping_total,
    :tax_total,
    :duties_total,
    :grand_total
  ]
  defstruct [
    :currency,
    :subtotal,
    :discount_total,
    :shipping_total,
    :tax_total,
    :duties_total,
    :grand_total
  ]

  @type t :: %__MODULE__{}

  def from_totals(totals, currency_code) do
    %__MODULE__{
      currency: currency_code,
      subtotal: Money.new(totals.subtotal, currency_code),
      discount_total: Money.new(totals.discount_total, currency_code),
      shipping_total: Money.new(totals.shipping_total, currency_code),
      tax_total: Money.new(totals.tax_total, currency_code),
      duties_total: Money.new(totals.duties_total, currency_code),
      grand_total: Money.new(totals.grand_total, currency_code)
    }
  end
end
