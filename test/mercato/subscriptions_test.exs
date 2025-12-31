defmodule Mercato.SubscriptionsTest do
  use ExUnit.Case, async: true

  alias Mercato.{Subscriptions, Repo}
  alias Mercato.Subscriptions.{Subscription, SubscriptionCycle}

  setup do
    # Explicitly get a connection for this test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "subscriptions" do
    @valid_attrs %{
      user_id: "01234567-89ab-cdef-0123-456789abcdef",
      product_id: "01234567-89ab-cdef-0123-456789abcdef",
      billing_cycle: "monthly",
      start_date: Date.utc_today(),
      billing_amount: Decimal.new("29.99")
    }

    @invalid_attrs %{
      user_id: nil,
      product_id: nil,
      billing_cycle: "invalid",
      billing_amount: nil
    }

    test "create_subscription/1 with valid data creates a subscription" do
      assert {:ok, %Subscription{} = subscription} = Subscriptions.create_subscription(@valid_attrs)
      assert subscription.user_id == @valid_attrs.user_id
      assert subscription.product_id == @valid_attrs.product_id
      assert subscription.billing_cycle == "monthly"
      assert subscription.status == "active"
      assert Decimal.equal?(subscription.billing_amount, Decimal.new("29.99"))
    end

    test "create_subscription/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Subscriptions.create_subscription(@invalid_attrs)
    end

    test "create_subscription/1 calculates next_billing_date correctly" do
      attrs = Map.put(@valid_attrs, :billing_cycle, "weekly")
      assert {:ok, %Subscription{} = subscription} = Subscriptions.create_subscription(attrs)

      expected_date = Date.add(@valid_attrs.start_date, 7)
      assert subscription.next_billing_date == expected_date
    end

    test "get_subscription!/1 returns the subscription with given id" do
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)
      assert %Subscription{} = found_subscription = Subscriptions.get_subscription!(subscription.id)
      assert found_subscription.id == subscription.id
    end

    test "get_subscription/1 returns {:ok, subscription} for existing subscription" do
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)
      assert {:ok, %Subscription{}} = Subscriptions.get_subscription(subscription.id)
    end

    test "get_subscription/1 returns {:error, :not_found} for non-existing subscription" do
      assert {:error, :not_found} = Subscriptions.get_subscription("01234567-89ab-cdef-0123-456789abcdef")
    end

    test "list_subscriptions/0 returns all subscriptions" do
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)
      assert [%Subscription{}] = Subscriptions.list_subscriptions()
      assert hd(Subscriptions.list_subscriptions()).id == subscription.id
    end

    test "list_subscriptions/1 filters by user_id" do
      user_id_1 = "01234567-89ab-cdef-0123-456789abcdef"
      user_id_2 = "11234567-89ab-cdef-0123-456789abcdef"

      {:ok, subscription1} = Subscriptions.create_subscription(Map.put(@valid_attrs, :user_id, user_id_1))
      {:ok, _subscription2} = Subscriptions.create_subscription(Map.put(@valid_attrs, :user_id, user_id_2))

      results = Subscriptions.list_subscriptions(user_id: user_id_1)
      assert length(results) == 1
      assert hd(results).id == subscription1.id
    end

    test "pause_subscription/1 pauses an active subscription" do
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)
      assert {:ok, %Subscription{} = paused_subscription} = Subscriptions.pause_subscription(subscription.id)
      assert paused_subscription.status == "paused"
    end

    test "pause_subscription/1 returns error for non-active subscription" do
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)
      {:ok, _paused} = Subscriptions.pause_subscription(subscription.id)
      assert {:error, :cannot_pause_subscription} = Subscriptions.pause_subscription(subscription.id)
    end

    test "resume_subscription/1 resumes a paused subscription" do
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)
      {:ok, _paused} = Subscriptions.pause_subscription(subscription.id)
      assert {:ok, %Subscription{} = resumed_subscription} = Subscriptions.resume_subscription(subscription.id)
      assert resumed_subscription.status == "active"
    end

    test "cancel_subscription/1 cancels an active subscription" do
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)
      assert {:ok, %Subscription{} = cancelled_subscription} = Subscriptions.cancel_subscription(subscription.id)
      assert cancelled_subscription.status == "cancelled"
    end

    test "get_subscriptions_due_for_renewal/0 returns subscriptions due for renewal" do
      # Create subscription normally first
      {:ok, subscription} = Subscriptions.create_subscription(@valid_attrs)

      # Update the next_billing_date to be in the past
      past_date = Date.add(Date.utc_today(), -1)
      {:ok, _updated_subscription} =
        subscription
        |> Subscription.billing_changeset(%{next_billing_date: past_date})
        |> Repo.update()

      due_subscriptions = Subscriptions.get_subscriptions_due_for_renewal()
      assert length(due_subscriptions) == 1
      assert hd(due_subscriptions).id == subscription.id
    end
  end

  describe "subscription cycles" do
    test "subscription cycle changeset validates required fields" do
      changeset = SubscriptionCycle.create_changeset(%SubscriptionCycle{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).subscription_id
      assert "can't be blank" in errors_on(changeset).cycle_number
      assert "can't be blank" in errors_on(changeset).billing_date
      assert "can't be blank" in errors_on(changeset).amount
    end

    test "subscription cycle changeset validates positive cycle_number" do
      changeset = SubscriptionCycle.create_changeset(%SubscriptionCycle{}, %{
        subscription_id: "01234567-89ab-cdef-0123-456789abcdef",
        cycle_number: 0,
        billing_date: Date.utc_today(),
        amount: Decimal.new("29.99"),
        status: "pending"
      })
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).cycle_number
    end

    test "subscription cycle changeset validates positive amount" do
      changeset = SubscriptionCycle.create_changeset(%SubscriptionCycle{}, %{
        subscription_id: "01234567-89ab-cdef-0123-456789abcdef",
        cycle_number: 1,
        billing_date: Date.utc_today(),
        amount: Decimal.new("0"),
        status: "pending"
      })
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).amount
    end
  end
end
