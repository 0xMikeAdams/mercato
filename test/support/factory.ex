defmodule Mercato.Factory do
  @moduledoc """
  ExMachina factories for tests.

  Use `sequence/2`-backed fields (slug, sku, code, order_number) to avoid the
  unique-constraint collisions that hardcoded literals invite. Prefer these over
  hand-built attribute maps in new tests:

      import Mercato.Factory

      product = insert(:product)
      order = build(:order, grand_total: Decimal.new("10.00"))
  """
  use ExMachina.Ecto, repo: Mercato.Repo

  def product_factory do
    %Mercato.Catalog.Product{
      name: sequence(:product_name, &"Product #{&1}"),
      slug: sequence(:product_slug, &"product-#{&1}"),
      sku: sequence(:product_sku, &"SKU-#{&1}"),
      price: Decimal.new("19.99"),
      product_type: "simple",
      status: "published",
      stock_quantity: 100
    }
  end

  def coupon_factory do
    %Mercato.Coupons.Coupon{
      code: sequence(:coupon_code, &"COUPON#{&1}"),
      discount_type: "percentage",
      discount_value: Decimal.new("10"),
      valid_from: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def referral_code_factory do
    %Mercato.Referrals.ReferralCode{
      user_id: Ecto.UUID.generate(),
      code: sequence(:referral_code, &"REF#{&1}"),
      commission_type: "percentage",
      commission_value: Decimal.new("5")
    }
  end

  def order_factory do
    %Mercato.Orders.Order{
      order_number: sequence(:order_number, &"ORD-#{&1}"),
      status: "pending",
      subtotal: Decimal.new("0.00"),
      discount_total: Decimal.new("0.00"),
      shipping_total: Decimal.new("0.00"),
      tax_total: Decimal.new("0.00"),
      duties_total: Decimal.new("0.00"),
      grand_total: Decimal.new("0.00")
    }
  end
end
