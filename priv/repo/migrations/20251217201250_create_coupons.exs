defmodule Mercato.Repo.Migrations.CreateCoupons do
  use Ecto.Migration

  def change do
    create table(:coupons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :discount_type, :string, null: false
      add :discount_value, :decimal, precision: 10, scale: 2, null: false
      add :min_spend, :decimal, precision: 10, scale: 2
      add :max_discount, :decimal, precision: 10, scale: 2
      add :usage_limit, :integer
      add :usage_limit_per_customer, :integer
      add :usage_count, :integer, null: false, default: 0
      add :valid_from, :utc_datetime, null: false
      add :valid_until, :utc_datetime
      add :included_product_ids, {:array, :binary_id}, default: []
      add :excluded_product_ids, {:array, :binary_id}, default: []
      add :included_category_ids, {:array, :binary_id}, default: []
      add :excluded_category_ids, {:array, :binary_id}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coupons, [:code])
    create index(:coupons, [:discount_type])
    create index(:coupons, [:valid_from])
    create index(:coupons, [:valid_until])
    create index(:coupons, [:usage_count])
    create index(:coupons, [:valid_from, :valid_until])

    # Check constraints for data integrity
    create constraint(:coupons, :valid_discount_type,
      check: "discount_type IN ('percentage', 'fixed_cart', 'fixed_product', 'free_shipping')")
    create constraint(:coupons, :positive_discount_value, check: "discount_value >= 0")
    create constraint(:coupons, :positive_min_spend, check: "min_spend IS NULL OR min_spend >= 0")
    create constraint(:coupons, :positive_max_discount, check: "max_discount IS NULL OR max_discount >= 0")
    create constraint(:coupons, :positive_usage_limits,
      check: "(usage_limit IS NULL OR usage_limit >= 0) AND (usage_limit_per_customer IS NULL OR usage_limit_per_customer >= 0)")
    create constraint(:coupons, :valid_date_range,
      check: "valid_until IS NULL OR valid_until > valid_from")
  end
end
