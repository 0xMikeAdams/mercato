defmodule Mercato.Customers do
  @moduledoc """
  The Customers context provides functions for managing customers and their addresses.

  This context handles all customer-related operations including:
  - Customer CRUD operations
  - Address management for billing and shipping
  - Order history retrieval
  - Integration with host application's user system

  ## Examples

      # Create a customer
      {:ok, customer} = Customers.create_customer(%{
        user_id: "123e4567-e89b-12d3-a456-426614174000",
        email: "john@example.com",
        first_name: "John",
        last_name: "Doe",
        phone: "+1-555-123-4567"
      })

      # Add a billing address
      {:ok, address} = Customers.add_address(customer.id, %{
        address_type: "billing",
        line1: "123 Main St",
        city: "Anytown",
        state: "CA",
        postal_code: "12345",
        country: "US",
        is_default: true
      })

      # Get customer's order history
      orders = Customers.get_order_history(customer.id)
  """

  import Ecto.Query, warn: false
  alias Mercato.Repo
  alias Mercato.Customers.{Customer, Address}

  ## Customer Management

  @doc """
  Gets a customer by user_id.

  Returns `{:ok, customer}` if found, `{:error, :not_found}` otherwise.

  ## Options

  - `:preload` - List of associations to preload (e.g., [:addresses])

  ## Examples

      iex> get_customer("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %Customer{}}

      iex> get_customer("invalid-id")
      {:error, :not_found}

      iex> get_customer(user_id, preload: [:addresses])
      {:ok, %Customer{addresses: [...]}}
  """
  def get_customer(user_id, opts \\ []) do
    query = from c in Customer, where: c.user_id == ^user_id

    case query |> maybe_preload(opts[:preload]) |> Repo.one() do
      nil -> {:error, :not_found}
      customer -> {:ok, customer}
    end
  end

  @doc """
  Gets a customer by customer ID.

  Returns `{:ok, customer}` if found, `{:error, :not_found}` otherwise.

  ## Options

  - `:preload` - List of associations to preload (e.g., [:addresses])

  ## Examples

      iex> get_customer_by_id("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %Customer{}}

      iex> get_customer_by_id("invalid-id")
      {:error, :not_found}
  """
  def get_customer_by_id(customer_id, opts \\ []) do
    query = from c in Customer, where: c.id == ^customer_id

    case query |> maybe_preload(opts[:preload]) |> Repo.one() do
      nil -> {:error, :not_found}
      customer -> {:ok, customer}
    end
  end

  @doc """
  Creates a customer.

  ## Examples

      iex> create_customer(%{
      ...>   user_id: "123e4567-e89b-12d3-a456-426614174000",
      ...>   email: "john@example.com",
      ...>   first_name: "John",
      ...>   last_name: "Doe"
      ...> })
      {:ok, %Customer{}}

      iex> create_customer(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def create_customer(attrs \\ %{}) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a customer.

  ## Examples

      iex> update_customer(customer, %{first_name: "Jane"})
      {:ok, %Customer{}}

      iex> update_customer(customer, %{email: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a customer.

  ## Examples

      iex> delete_customer(customer)
      {:ok, %Customer{}}

      iex> delete_customer(customer)
      {:error, %Ecto.Changeset{}}
  """
  def delete_customer(%Customer{} = customer) do
    Repo.delete(customer)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking customer changes.

  ## Examples

      iex> change_customer(customer)
      %Ecto.Changeset{data: %Customer{}}
  """
  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  ## Address Management

  @doc """
  Returns a list of addresses for a customer.

  ## Options

  - `:address_type` - Filter by address type ("billing" or "shipping")

  ## Examples

      iex> list_addresses(customer_id)
      [%Address{}, ...]

      iex> list_addresses(customer_id, address_type: "billing")
      [%Address{address_type: "billing"}, ...]
  """
  def list_addresses(customer_id, opts \\ []) do
    query = from a in Address, where: a.customer_id == ^customer_id

    query
    |> filter_by_address_type(opts[:address_type])
    |> order_by([a], [desc: a.is_default, asc: a.inserted_at])
    |> Repo.all()
  end

  defp filter_by_address_type(query, nil), do: query
  defp filter_by_address_type(query, type), do: from(a in query, where: a.address_type == ^type)

  @doc """
  Gets a single address by ID.

  Returns `{:ok, address}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_address("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %Address{}}

      iex> get_address("invalid-id")
      {:error, :not_found}
  """
  def get_address(address_id) do
    case Repo.get(Address, address_id) do
      nil -> {:error, :not_found}
      address -> {:ok, address}
    end
  end

  @doc """
  Adds an address to a customer.

  If `is_default` is true, this will unset any existing default address of the same type.

  ## Examples

      iex> add_address(customer_id, %{
      ...>   address_type: "billing",
      ...>   line1: "123 Main St",
      ...>   city: "Anytown",
      ...>   state: "CA",
      ...>   postal_code: "12345",
      ...>   country: "US"
      ...> })
      {:ok, %Address{}}

      iex> add_address(customer_id, %{line1: ""})
      {:error, %Ecto.Changeset{}}
  """
  def add_address(customer_id, attrs \\ %{}) do
    attrs = Map.put(attrs, :customer_id, customer_id)

    Repo.transaction(fn ->
      # If this is being set as default, unset existing defaults of the same type
      if Map.get(attrs, :is_default) || Map.get(attrs, "is_default") do
        address_type = Map.get(attrs, :address_type) || Map.get(attrs, "address_type")
        unset_default_address(customer_id, address_type)
      end

      %Address{}
      |> Address.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, address} -> address
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates an address.

  If `is_default` is being set to true, this will unset any existing default address of the same type.

  ## Examples

      iex> update_address(address, %{line1: "456 Oak St"})
      {:ok, %Address{}}

      iex> update_address(address, %{postal_code: ""})
      {:error, %Ecto.Changeset{}}
  """
  def update_address(%Address{} = address, attrs) do
    Repo.transaction(fn ->
      # If this is being set as default, unset existing defaults of the same type
      if Map.get(attrs, :is_default) || Map.get(attrs, "is_default") do
        address_type = Map.get(attrs, :address_type) || Map.get(attrs, "address_type") || address.address_type
        unset_default_address(address.customer_id, address_type, address.id)
      end

      address
      |> Address.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, address} -> address
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Deletes an address.

  ## Examples

      iex> delete_address(address)
      {:ok, %Address{}}
  """
  def delete_address(%Address{} = address) do
    Repo.delete(address)
  end

  @doc """
  Gets the default address for a customer and address type.

  Returns `{:ok, address}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_default_address(customer_id, "billing")
      {:ok, %Address{}}

      iex> get_default_address(customer_id, "shipping")
      {:error, :not_found}
  """
  def get_default_address(customer_id, address_type) do
    query = from a in Address,
      where: a.customer_id == ^customer_id and a.address_type == ^address_type and a.is_default == true

    case Repo.one(query) do
      nil -> {:error, :not_found}
      address -> {:ok, address}
    end
  end

  @doc """
  Sets an address as the default for its type.

  This will unset any existing default address of the same type.

  ## Examples

      iex> set_default_address(address)
      {:ok, %Address{}}
  """
  def set_default_address(%Address{} = address) do
    Repo.transaction(fn ->
      unset_default_address(address.customer_id, address.address_type, address.id)

      address
      |> Address.changeset(%{is_default: true})
      |> Repo.update()
      |> case do
        {:ok, address} -> address
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  ## Order History

  @doc """
  Gets the order history for a customer.

  Returns a list of orders associated with the customer's user_id.

  ## Options

  - `:limit` - Limit the number of orders returned
  - `:preload` - List of associations to preload (e.g., [:items])

  ## Examples

      iex> get_order_history(customer_id)
      [%Order{}, ...]

      iex> get_order_history(customer_id, limit: 10, preload: [:items])
      [%Order{items: [...]}, ...]
  """
  def get_order_history(customer_id, opts \\ []) do
    with {:ok, customer} <- get_customer_by_id(customer_id) do
      query = from o in Mercato.Orders.Order,
        where: o.user_id == ^customer.user_id,
        order_by: [desc: o.inserted_at]

      query
      |> maybe_limit(opts[:limit])
      |> maybe_preload(opts[:preload])
      |> Repo.all()
    else
      {:error, :not_found} -> []
    end
  end

  @doc """
  Gets the order history for a user by user_id.

  Returns a list of orders associated with the user_id.

  ## Options

  - `:limit` - Limit the number of orders returned
  - `:preload` - List of associations to preload (e.g., [:items])

  ## Examples

      iex> get_order_history_by_user_id(user_id)
      [%Order{}, ...]

      iex> get_order_history_by_user_id(user_id, limit: 10, preload: [:items])
      [%Order{items: [...]}, ...]
  """
  def get_order_history_by_user_id(user_id, opts \\ []) do
    query = from o in Mercato.Orders.Order,
      where: o.user_id == ^user_id,
      order_by: [desc: o.inserted_at]

    query
    |> maybe_limit(opts[:limit])
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  # Private Functions

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: from(q in query, preload: ^preloads)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: from(q in query, limit: ^limit)

  defp unset_default_address(customer_id, address_type, exclude_id \\ nil) do
    query = from a in Address,
      where: a.customer_id == ^customer_id and a.address_type == ^address_type and a.is_default == true

    query = if exclude_id do
      from a in query, where: a.id != ^exclude_id
    else
      query
    end

    Repo.update_all(query, set: [is_default: false])
  end
end
