defmodule Mercato.Checkout.CheckoutLineItem do
  @moduledoc """
  Stable line item shape returned by programmatic checkout APIs.
  """

  alias Mercato.Checkout.Money

  @enforce_keys [:id, :product_id, :quantity, :unit_price, :line_total]
  defstruct [
    :id,
    :product_id,
    :variant_id,
    :sku,
    :title,
    :quantity,
    :unit_price,
    :line_total
  ]

  @type t :: %__MODULE__{}

  def from_cart_item(item, currency_code) do
    variant_sku =
      case item.variant do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> nil
        variant -> variant.sku
      end

    product_sku =
      case item.product do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> nil
        product -> product.sku
      end

    title =
      case item.product do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> nil
        product -> product.name
      end

    %__MODULE__{
      id: item.id,
      product_id: item.product_id,
      variant_id: item.variant_id,
      sku: variant_sku || product_sku,
      title: title,
      quantity: item.quantity,
      unit_price: Money.new(item.unit_price, currency_code),
      line_total: Money.new(item.total_price, currency_code)
    }
  end
end
