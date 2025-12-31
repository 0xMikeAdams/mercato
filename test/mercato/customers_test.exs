defmodule Mercato.CustomersTest do
  use ExUnit.Case, async: true
  alias Mercato.Customers
  alias Mercato.Customers.{Customer, Address}

  setup do
    # Ensure we're using the test database
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mercato.Repo)
  end

  describe "customers" do
    @valid_customer_attrs %{
      user_id: "123e4567-e89b-12d3-a456-426614174000",
      email: "test@example.com",
      first_name: "John",
      last_name: "Doe",
      phone: "+1-555-123-4567"
    }

    @invalid_customer_attrs %{email: "invalid", first_name: "", last_name: ""}

    test "create_customer/1 with valid data creates a customer" do
      assert {:ok, %Customer{} = customer} = Customers.create_customer(@valid_customer_attrs)
      assert customer.email == "test@example.com"
      assert customer.first_name == "John"
      assert customer.last_name == "Doe"
      assert customer.phone == "+1-555-123-4567"
    end

    test "create_customer/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Customers.create_customer(@invalid_customer_attrs)
    end

    test "get_customer/1 returns the customer with given user_id" do
      {:ok, customer} = Customers.create_customer(@valid_customer_attrs)
      assert {:ok, found_customer} = Customers.get_customer(customer.user_id)
      assert found_customer.id == customer.id
    end

    test "get_customer/1 returns error when customer not found" do
      assert {:error, :not_found} = Customers.get_customer("123e4567-e89b-12d3-a456-426614174999")
    end

    test "update_customer/2 with valid data updates the customer" do
      {:ok, customer} = Customers.create_customer(@valid_customer_attrs)
      update_attrs = %{first_name: "Jane", last_name: "Smith"}

      assert {:ok, %Customer{} = customer} = Customers.update_customer(customer, update_attrs)
      assert customer.first_name == "Jane"
      assert customer.last_name == "Smith"
    end

    test "update_customer/2 with invalid data returns error changeset" do
      {:ok, customer} = Customers.create_customer(@valid_customer_attrs)
      assert {:error, %Ecto.Changeset{}} = Customers.update_customer(customer, @invalid_customer_attrs)
      assert {:ok, customer} = Customers.get_customer(customer.user_id)
      assert customer.first_name == "John"
    end

    test "delete_customer/1 deletes the customer" do
      {:ok, customer} = Customers.create_customer(@valid_customer_attrs)
      assert {:ok, %Customer{}} = Customers.delete_customer(customer)
      assert {:error, :not_found} = Customers.get_customer(customer.user_id)
    end

    test "change_customer/1 returns a customer changeset" do
      {:ok, customer} = Customers.create_customer(@valid_customer_attrs)
      assert %Ecto.Changeset{} = Customers.change_customer(customer)
    end
  end

  describe "addresses" do
    @valid_address_attrs %{
      address_type: "billing",
      line1: "123 Main St",
      line2: "Apt 4B",
      city: "Anytown",
      state: "CA",
      postal_code: "12345",
      country: "US",
      is_default: true
    }

    @invalid_address_attrs %{address_type: "invalid", line1: "", city: "", state: "", postal_code: "", country: ""}

    setup do
      {:ok, customer} = Customers.create_customer(@valid_customer_attrs)
      %{customer: customer}
    end

    test "add_address/2 with valid data creates an address", %{customer: customer} do
      assert {:ok, %Address{} = address} = Customers.add_address(customer.id, @valid_address_attrs)
      assert address.address_type == "billing"
      assert address.line1 == "123 Main St"
      assert address.line2 == "Apt 4B"
      assert address.city == "Anytown"
      assert address.state == "CA"
      assert address.postal_code == "12345"
      assert address.country == "US"
      assert address.is_default == true
    end

    test "add_address/2 with invalid data returns error changeset", %{customer: customer} do
      assert {:error, %Ecto.Changeset{}} = Customers.add_address(customer.id, @invalid_address_attrs)
    end

    test "list_addresses/1 returns all addresses for a customer", %{customer: customer} do
      {:ok, address1} = Customers.add_address(customer.id, @valid_address_attrs)
      {:ok, address2} = Customers.add_address(customer.id, Map.put(@valid_address_attrs, :address_type, "shipping"))

      addresses = Customers.list_addresses(customer.id)
      assert length(addresses) == 2
      assert Enum.any?(addresses, &(&1.id == address1.id))
      assert Enum.any?(addresses, &(&1.id == address2.id))
    end

    test "list_addresses/2 with address_type filter returns filtered addresses", %{customer: customer} do
      {:ok, _billing} = Customers.add_address(customer.id, @valid_address_attrs)
      {:ok, shipping} = Customers.add_address(customer.id, Map.put(@valid_address_attrs, :address_type, "shipping"))

      shipping_addresses = Customers.list_addresses(customer.id, address_type: "shipping")
      assert length(shipping_addresses) == 1
      assert hd(shipping_addresses).id == shipping.id
    end

    test "get_address/1 returns the address with given id", %{customer: customer} do
      {:ok, address} = Customers.add_address(customer.id, @valid_address_attrs)
      assert {:ok, found_address} = Customers.get_address(address.id)
      assert found_address.id == address.id
    end

    test "get_address/1 returns error when address not found" do
      assert {:error, :not_found} = Customers.get_address("123e4567-e89b-12d3-a456-426614174999")
    end

    test "update_address/2 with valid data updates the address", %{customer: customer} do
      {:ok, address} = Customers.add_address(customer.id, @valid_address_attrs)
      update_attrs = %{line1: "456 Oak St", city: "Newtown"}

      assert {:ok, %Address{} = address} = Customers.update_address(address, update_attrs)
      assert address.line1 == "456 Oak St"
      assert address.city == "Newtown"
    end

    test "update_address/2 with invalid data returns error changeset", %{customer: customer} do
      {:ok, address} = Customers.add_address(customer.id, @valid_address_attrs)
      assert {:error, %Ecto.Changeset{}} = Customers.update_address(address, @invalid_address_attrs)
      assert {:ok, address} = Customers.get_address(address.id)
      assert address.line1 == "123 Main St"
    end

    test "delete_address/1 deletes the address", %{customer: customer} do
      {:ok, address} = Customers.add_address(customer.id, @valid_address_attrs)
      assert {:ok, %Address{}} = Customers.delete_address(address)
      assert {:error, :not_found} = Customers.get_address(address.id)
    end

    test "get_default_address/2 returns the default address for a type", %{customer: customer} do
      {:ok, address} = Customers.add_address(customer.id, @valid_address_attrs)
      assert {:ok, default_address} = Customers.get_default_address(customer.id, "billing")
      assert default_address.id == address.id
    end

    test "get_default_address/2 returns error when no default address exists", %{customer: customer} do
      assert {:error, :not_found} = Customers.get_default_address(customer.id, "billing")
    end

    test "set_default_address/1 sets address as default and unsets others", %{customer: customer} do
      {:ok, address1} = Customers.add_address(customer.id, @valid_address_attrs)
      {:ok, address2} = Customers.add_address(customer.id, Map.put(@valid_address_attrs, :is_default, false))

      assert {:ok, %Address{} = updated_address2} = Customers.set_default_address(address2)
      assert updated_address2.is_default == true

      # Verify the first address is no longer default
      {:ok, updated_address1} = Customers.get_address(address1.id)
      assert updated_address1.is_default == false
    end

    test "adding default address unsets existing default of same type", %{customer: customer} do
      {:ok, address1} = Customers.add_address(customer.id, @valid_address_attrs)
      {:ok, address2} = Customers.add_address(customer.id, @valid_address_attrs)

      # Verify the second address is default and first is not
      {:ok, updated_address1} = Customers.get_address(address1.id)
      {:ok, updated_address2} = Customers.get_address(address2.id)
      assert updated_address1.is_default == false
      assert updated_address2.is_default == true
    end
  end

  describe "order_history" do
    setup do
      {:ok, customer} = Customers.create_customer(@valid_customer_attrs)
      %{customer: customer}
    end

    test "get_order_history/1 returns empty list when customer has no orders", %{customer: customer} do
      orders = Customers.get_order_history(customer.id)
      assert orders == []
    end

    test "get_order_history_by_user_id/1 returns empty list when user has no orders", %{customer: customer} do
      orders = Customers.get_order_history_by_user_id(customer.user_id)
      assert orders == []
    end

    test "get_order_history/1 returns empty list for nonexistent customer" do
      orders = Customers.get_order_history("123e4567-e89b-12d3-a456-426614174999")
      assert orders == []
    end
  end
end
