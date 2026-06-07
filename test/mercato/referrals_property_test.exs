defmodule Mercato.ReferralsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Mercato.Factory

  alias Mercato.Referrals

  describe "calculate_commission/2 invariants" do
    property "commission is always within [0, grand_total] for any config" do
      check all(
              total_cents <- integer(0..10_000_000),
              type <- member_of(["percentage", "fixed"]),
              raw_value <- integer(1..1_000_000)
            ) do
        grand_total = Decimal.div(Decimal.new(total_cents), 100)

        value =
          case type do
            # percentage validation bounds the rate to 1..100
            "percentage" -> Decimal.new(rem(raw_value, 100) + 1)
            "fixed" -> Decimal.div(Decimal.new(raw_value), 100)
          end

        order = build(:order, grand_total: grand_total)
        code = build(:referral_code, commission_type: type, commission_value: value)

        commission = Referrals.calculate_commission(order, code)

        assert Decimal.compare(commission, Decimal.new(0)) != :lt,
               "commission #{commission} was negative"

        assert Decimal.compare(commission, grand_total) != :gt,
               "commission #{commission} exceeded grand_total #{grand_total}"
      end
    end
  end
end
