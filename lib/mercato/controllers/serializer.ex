defmodule Mercato.Controllers.Serializer do
  @moduledoc false

  # Per-resource field allowlists. Only these fields are ever serialized for a given
  # schema, so anything added to a schema later is hidden by default (fail-closed) —
  # the opposite of a denylist, which leaks new fields until someone remembers to add
  # them. Sensitive/internal columns (idempotency_key, payment_transaction_id,
  # source_cart_id) are simply absent from the lists.
  #
  # Convention: expose the resource's own columns, its useful foreign keys, and the
  # associations that point *downward* (contained records). Upward back-references
  # (belongs_to parents) are intentionally omitted to avoid cyclic/over-deep output.
  @public_fields %{
    Mercato.Catalog.Product => [
      :id,
      :name,
      :slug,
      :description,
      :images,
      :price,
      :sale_price,
      :sku,
      :stock_quantity,
      :manage_stock,
      :backorders,
      :status,
      :product_type,
      :subscription_settings,
      :meta_title,
      :meta_description,
      :variants,
      :categories,
      :tags,
      :inserted_at,
      :updated_at
    ],
    Mercato.Catalog.ProductVariant => [
      :id,
      :sku,
      :price,
      :sale_price,
      :stock_quantity,
      :attributes,
      :product_id,
      :inserted_at,
      :updated_at
    ],
    Mercato.Catalog.Category => [
      :id,
      :name,
      :slug,
      :description,
      :parent_id,
      :children,
      :products,
      :inserted_at,
      :updated_at
    ],
    Mercato.Catalog.Tag => [:id, :name, :slug, :products, :inserted_at, :updated_at],
    Mercato.Cart.Cart => [
      :id,
      :cart_token,
      :user_id,
      :status,
      :buyer_identity,
      :shipping_address,
      :shipping_method,
      :subtotal,
      :discount_total,
      :shipping_total,
      :tax_total,
      :duties_total,
      :grand_total,
      :expires_at,
      :applied_coupon_id,
      :items,
      :applied_coupon,
      :inserted_at,
      :updated_at
    ],
    Mercato.Cart.CartItem => [
      :id,
      :quantity,
      :unit_price,
      :total_price,
      :cart_id,
      :product_id,
      :variant_id,
      :product,
      :variant,
      :inserted_at,
      :updated_at
    ],
    Mercato.Orders.Order => [
      :id,
      :order_number,
      :user_id,
      :status,
      :subtotal,
      :discount_total,
      :shipping_total,
      :tax_total,
      :duties_total,
      :grand_total,
      :billing_address,
      :shipping_address,
      :customer_notes,
      :payment_method,
      :applied_coupon_id,
      :referral_code_id,
      :items,
      :status_history,
      :inserted_at,
      :updated_at
    ],
    Mercato.Orders.OrderItem => [
      :id,
      :quantity,
      :unit_price,
      :total_price,
      :product_snapshot,
      :order_id,
      :product_id,
      :variant_id,
      :inserted_at,
      :updated_at
    ],
    Mercato.Orders.OrderStatusHistory => [
      :id,
      :from_status,
      :to_status,
      :notes,
      :changed_by,
      :changed_at,
      :order_id,
      :inserted_at,
      :updated_at
    ],
    Mercato.Customers.Customer => [
      :id,
      :user_id,
      :email,
      :first_name,
      :last_name,
      :phone,
      :addresses,
      :inserted_at,
      :updated_at
    ],
    Mercato.Customers.Address => [
      :id,
      :customer_id,
      :address_type,
      :line1,
      :line2,
      :city,
      :state,
      :postal_code,
      :country,
      :is_default,
      :inserted_at,
      :updated_at
    ],
    Mercato.Coupons.Coupon => [
      :id,
      :code,
      :discount_type,
      :discount_value,
      :min_spend,
      :max_discount,
      :usage_limit,
      :usage_limit_per_customer,
      :usage_count,
      :valid_from,
      :valid_until,
      :included_product_ids,
      :excluded_product_ids,
      :included_category_ids,
      :excluded_category_ids,
      :inserted_at,
      :updated_at
    ],
    Mercato.Coupons.CouponUsage => [
      :id,
      :coupon_id,
      :user_id,
      :order_id,
      :used_at,
      :inserted_at,
      :updated_at
    ],
    Mercato.Subscriptions.Subscription => [
      :id,
      :user_id,
      :product_id,
      :variant_id,
      :status,
      :billing_cycle,
      :trial_end_date,
      :start_date,
      :next_billing_date,
      :end_date,
      :billing_amount,
      :cycles,
      :inserted_at,
      :updated_at
    ],
    Mercato.Subscriptions.SubscriptionCycle => [
      :id,
      :cycle_number,
      :billing_date,
      :amount,
      :order_id,
      :status,
      :subscription_id,
      :inserted_at,
      :updated_at
    ],
    Mercato.Referrals.ReferralCode => [
      :id,
      :user_id,
      :code,
      :status,
      :commission_type,
      :commission_value,
      :clicks_count,
      :conversions_count,
      :total_commission,
      :inserted_at,
      :updated_at
    ],
    Mercato.Referrals.Commission => [
      :id,
      :referral_code_id,
      :order_id,
      :referee_id,
      :amount,
      :status,
      :paid_at,
      :inserted_at,
      :updated_at
    ],
    Mercato.Referrals.ReferralClick => [
      :id,
      :referral_code_id,
      :ip_address,
      :user_agent,
      :referrer_url,
      :clicked_at
    ]
  }

  def serialize(value) do
    do_serialize(value)
  end

  defp do_serialize(%Ecto.Association.NotLoaded{}), do: nil
  defp do_serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp do_serialize(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp do_serialize(%Date{} = d), do: Date.to_iso8601(d)
  defp do_serialize(%Time{} = t), do: Time.to_iso8601(t)
  defp do_serialize(%Decimal{} = d), do: Decimal.to_string(d)

  defp do_serialize(%module{} = struct) do
    case Map.fetch(@public_fields, module) do
      {:ok, fields} ->
        struct |> Map.take(fields) |> serialize_map()

      :error ->
        # No allowlist entry. A *persisted* Ecto schema is failed closed (never leak a
        # DB record we didn't explicitly expose); embedded/value structs pass through
        # as plain maps (they're value objects, e.g. Decimal is handled above).
        if persisted_schema?(module) do
          %{}
        else
          struct |> Map.from_struct() |> Map.delete(:__meta__) |> serialize_map()
        end
    end
  end

  defp do_serialize(list) when is_list(list), do: Enum.map(list, &do_serialize/1)
  defp do_serialize(map) when is_map(map), do: serialize_map(map)
  defp do_serialize(other), do: other

  defp serialize_map(map) do
    Enum.reduce(map, %{}, fn {key, val}, acc ->
      case val do
        %Ecto.Association.NotLoaded{} -> acc
        _ -> Map.put(acc, key, do_serialize(val))
      end
    end)
  end

  defp persisted_schema?(module) do
    function_exported?(module, :__schema__, 1) and module.__schema__(:source) != nil
  end
end
