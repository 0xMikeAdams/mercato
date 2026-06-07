defmodule Mercato.ReferralsTest do
  # async: false — these tests read (and one overrides) the global
  # :referral_commission application env, which is process-global.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Mercato.{Referrals, Cart, Catalog, Orders, Repo}
  alias Mercato.Referrals.{ReferralCode, Commission}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  describe "generate_referral_code/2 — commission terms are server-controlled" do
    test "ignores caller-supplied commission terms and applies the default policy" do
      user_id = Ecto.UUID.generate()

      # A malicious caller attempts to pay themselves 100%.
      {:ok, code} =
        Referrals.generate_referral_code(user_id, %{
          "commission_type" => "fixed",
          "commission_value" => "100",
          "clicks_count" => 9999,
          "total_commission" => "500.00"
        })

      # Server policy wins: default is 5% percentage, counters start at zero.
      assert code.commission_type == "percentage"
      assert Decimal.equal?(code.commission_value, Decimal.new("5"))
      assert code.clicks_count == 0
      assert code.conversions_count == 0
      assert Decimal.equal?(code.total_commission, Decimal.new("0.00"))
      assert code.user_id == user_id
    end

    test "applies the configured commission policy when set" do
      Application.put_env(:mercato, :referral_commission, %{
        type: "fixed",
        value: Decimal.new("12.50")
      })

      on_exit(fn -> Application.delete_env(:mercato, :referral_commission) end)

      {:ok, code} = Referrals.generate_referral_code(Ecto.UUID.generate())

      assert code.commission_type == "fixed"
      assert Decimal.equal?(code.commission_value, Decimal.new("12.50"))
    end

    test "lets the caller suggest a custom code but never the commission" do
      {:ok, code} =
        Referrals.generate_referral_code(Ecto.UUID.generate(), %{
          code: "MYCODE",
          commission_value: "99"
        })

      assert code.code == "MYCODE"
      assert code.commission_type == "percentage"
      assert Decimal.equal?(code.commission_value, Decimal.new("5"))
    end

    test "generates a unique code when none is supplied" do
      {:ok, a} = Referrals.generate_referral_code(Ecto.UUID.generate())
      {:ok, b} = Referrals.generate_referral_code(Ecto.UUID.generate())
      assert a.code != b.code
      assert String.length(a.code) >= 4
    end
  end

  describe "calculate_commission/2" do
    test "percentage commission is a fraction of the order total" do
      order = %Orders.Order{grand_total: Decimal.new("200.00")}
      code = %ReferralCode{commission_type: "percentage", commission_value: Decimal.new("5")}

      assert Decimal.equal?(Referrals.calculate_commission(order, code), Decimal.new("10.00"))
    end

    test "fixed commission is the flat value regardless of order total" do
      order = %Orders.Order{grand_total: Decimal.new("200.00")}
      code = %ReferralCode{commission_type: "fixed", commission_value: Decimal.new("7.50")}

      assert Decimal.equal?(Referrals.calculate_commission(order, code), Decimal.new("7.50"))
    end
  end

  describe "track_conversion/2 — idempotency (no double-credit)" do
    test "credits a commission once and is idempotent on repeat calls" do
      user_id = Ecto.UUID.generate()
      {:ok, code} = Referrals.generate_referral_code(user_id)
      {:ok, order} = create_order(Ecto.UUID.generate())

      assert {:ok, %Commission{} = commission} =
               Referrals.track_conversion(code.code, order.id)

      # A second conversion for the SAME order must not create another commission
      # nor inflate total_commission (the order status machine can re-enter
      # "completed", which previously re-credited).
      assert {:ok, %Commission{} = again} = Referrals.track_conversion(code.code, order.id)
      assert again.id == commission.id

      assert Repo.aggregate(
               from(c in Commission, where: c.order_id == ^order.id),
               :count
             ) == 1

      reloaded = Repo.get!(ReferralCode, code.id)
      assert reloaded.conversions_count == 1
      assert Decimal.equal?(reloaded.total_commission, commission.amount)
    end

    test "returns an error for an unknown referral code" do
      {:ok, order} = create_order(Ecto.UUID.generate())
      assert {:error, :referral_code_not_found} = Referrals.track_conversion("NOPE", order.id)
    end

    test "returns an error for an unknown order" do
      {:ok, code} = Referrals.generate_referral_code(Ecto.UUID.generate())

      assert {:error, :order_not_found} =
               Referrals.track_conversion(code.code, Ecto.UUID.generate())
    end
  end

  describe "track_click/2" do
    test "records a click and increments the click count" do
      {:ok, code} = Referrals.generate_referral_code(Ecto.UUID.generate())

      assert {:ok, _click} = Referrals.track_click(code.code, %{ip_address: "1.2.3.4"})

      reloaded = Repo.get!(ReferralCode, code.id)
      assert reloaded.clicks_count == 1
    end

    test "returns an error for an unknown code" do
      assert {:error, :referral_code_not_found} =
               Referrals.track_click("NOPE", %{ip_address: "1.2.3.4"})
    end
  end

  defp create_order(user_id) do
    {:ok, product} =
      Catalog.create_product(%{
        name: "Ref Product #{System.unique_integer([:positive])}",
        slug: "ref-product-#{System.unique_integer([:positive])}",
        price: Decimal.new("100.00"),
        sku: "REF-#{System.unique_integer([:positive])}",
        product_type: "simple",
        stock_quantity: 50
      })

    {:ok, cart} =
      Cart.create_cart(%{
        cart_token: "ref-cart-#{System.unique_integer([:positive])}",
        user_id: user_id
      })

    {:ok, _cart} = Cart.add_item(cart.id, product.id, 1)

    Orders.create_order_from_cart(cart.id, %{
      billing_address: %{
        "line1" => "1 Ref St",
        "city" => "Toronto",
        "state" => "ON",
        "postal_code" => "A1A1A1",
        "country" => "CA"
      },
      payment_method: "invoice"
    })
  end
end
