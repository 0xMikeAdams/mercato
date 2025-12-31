defmodule Mercato.Catalog do
  @moduledoc """
  The Catalog context provides functions for managing products, variants, categories, and tags.

  This context handles all product catalog operations including:
  - Product CRUD operations
  - Product variant management
  - Category and tag associations
  - Inventory tracking (see also inventory management functions)

  ## Examples

      # Create a product
      {:ok, product} = Catalog.create_product(%{
        name: "T-Shirt",
        slug: "t-shirt",
        price: Decimal.new("29.99"),
        sku: "TSHIRT-001",
        product_type: "simple",
        status: "published"
      })

      # List all published products
      products = Catalog.list_products(status: "published")

      # Add a variant to a variable product
      {:ok, variant} = Catalog.create_variant(product.id, %{
        sku: "TSHIRT-L-BLUE",
        price: Decimal.new("29.99"),
        attributes: %{"size" => "L", "color" => "blue"}
      })
  """

  import Ecto.Query, warn: false
  alias Mercato.Repo
  alias Mercato.Catalog.{Product, ProductVariant, Category, Tag}

  ## Product Management

  @doc """
  Returns a list of products with optional filters.

  ## Options

  - `:status` - Filter by status ("draft", "published", "archived")
  - `:product_type` - Filter by product type
  - `:preload` - List of associations to preload (e.g., [:variants, :categories, :tags])

  ## Examples

      iex> list_products()
      [%Product{}, ...]

      iex> list_products(status: "published", preload: [:categories])
      [%Product{categories: [...]}, ...]
  """
  def list_products(opts \\ []) do
    query = from p in Product

    query
    |> filter_by_status(opts[:status])
    |> filter_by_product_type(opts[:product_type])
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: from(p in query, where: p.status == ^status)

  defp filter_by_product_type(query, nil), do: query
  defp filter_by_product_type(query, type), do: from(p in query, where: p.product_type == ^type)

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: from(p in query, preload: ^preloads)

  @doc """
  Gets a single product by ID.

  Raises `Ecto.NoResultsError` if the product does not exist.

  ## Options

  - `:preload` - List of associations to preload

  ## Examples

      iex> get_product!("123e4567-e89b-12d3-a456-426614174000")
      %Product{}

      iex> get_product!("invalid-id")
      ** (Ecto.NoResultsError)
  """
  def get_product!(id, opts \\ []) do
    query = from p in Product, where: p.id == ^id

    query
    |> maybe_preload(opts[:preload])
    |> Repo.one!()
  end

  @doc """
  Gets a single product by slug.

  Returns `{:ok, product}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_product_by_slug("t-shirt")
      {:ok, %Product{}}

      iex> get_product_by_slug("nonexistent")
      {:error, :not_found}
  """
  def get_product_by_slug(slug, opts \\ []) do
    query = from p in Product, where: p.slug == ^slug

    case query |> maybe_preload(opts[:preload]) |> Repo.one() do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc """
  Creates a product.

  ## Examples

      iex> create_product(%{name: "T-Shirt", slug: "t-shirt", price: Decimal.new("29.99"), sku: "TSHIRT-001", product_type: "simple"})
      {:ok, %Product{}}

      iex> create_product(%{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_product(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{name: "New Name"})
      {:ok, %Product{}}

      iex> update_product(product, %{price: -10})
      {:error, %Ecto.Changeset{}}
  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product.

  ## Examples

      iex> delete_product(product)
      {:ok, %Product{}}

      iex> delete_product(product)
      {:error, %Ecto.Changeset{}}
  """
  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{data: %Product{}}
  """
  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  ## Product Variant Management

  @doc """
  Returns a list of variants for a product.

  ## Examples

      iex> list_variants(product_id)
      [%ProductVariant{}, ...]
  """
  def list_variants(product_id) do
    from(v in ProductVariant, where: v.product_id == ^product_id)
    |> Repo.all()
  end

  @doc """
  Gets a single variant by ID.

  Returns `{:ok, variant}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_variant("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %ProductVariant{}}

      iex> get_variant("invalid-id")
      {:error, :not_found}
  """
  def get_variant(id) do
    case Repo.get(ProductVariant, id) do
      nil -> {:error, :not_found}
      variant -> {:ok, variant}
    end
  end

  @doc """
  Creates a variant for a product.

  ## Examples

      iex> create_variant(product_id, %{sku: "TSHIRT-L", price: Decimal.new("29.99")})
      {:ok, %ProductVariant{}}

      iex> create_variant(product_id, %{sku: ""})
      {:error, %Ecto.Changeset{}}
  """
  def create_variant(product_id, attrs \\ %{}) do
    attrs = Map.put(attrs, :product_id, product_id)

    %ProductVariant{}
    |> ProductVariant.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a variant.

  ## Examples

      iex> update_variant(variant, %{price: Decimal.new("24.99")})
      {:ok, %ProductVariant{}}

      iex> update_variant(variant, %{price: -10})
      {:error, %Ecto.Changeset{}}
  """
  def update_variant(%ProductVariant{} = variant, attrs) do
    variant
    |> ProductVariant.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a variant.

  ## Examples

      iex> delete_variant(variant)
      {:ok, %ProductVariant{}}
  """
  def delete_variant(%ProductVariant{} = variant) do
    Repo.delete(variant)
  end

  ## Category Management

  @doc """
  Returns a list of all categories.

  ## Options

  - `:preload` - List of associations to preload (e.g., [:products, :children, :parent])

  ## Examples

      iex> list_categories()
      [%Category{}, ...]

      iex> list_categories(preload: [:children])
      [%Category{children: [...]}, ...]
  """
  def list_categories(opts \\ []) do
    from(c in Category)
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  @doc """
  Gets a single category by ID.

  Returns `{:ok, category}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_category("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %Category{}}
  """
  def get_category(id, opts \\ []) do
    query = from c in Category, where: c.id == ^id

    case query |> maybe_preload(opts[:preload]) |> Repo.one() do
      nil -> {:error, :not_found}
      category -> {:ok, category}
    end
  end

  @doc """
  Creates a category.

  ## Examples

      iex> create_category(%{name: "Clothing", slug: "clothing"})
      {:ok, %Category{}}
  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(category, %{name: "New Name"})
      {:ok, %Category{}}
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.

  ## Examples

      iex> delete_category(category)
      {:ok, %Category{}}
  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  ## Tag Management

  @doc """
  Returns a list of all tags.

  ## Options

  - `:preload` - List of associations to preload (e.g., [:products])

  ## Examples

      iex> list_tags()
      [%Tag{}, ...]
  """
  def list_tags(opts \\ []) do
    from(t in Tag)
    |> maybe_preload(opts[:preload])
    |> Repo.all()
  end

  @doc """
  Gets a single tag by ID.

  Returns `{:ok, tag}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_tag("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %Tag{}}
  """
  def get_tag(id, opts \\ []) do
    query = from t in Tag, where: t.id == ^id

    case query |> maybe_preload(opts[:preload]) |> Repo.one() do
      nil -> {:error, :not_found}
      tag -> {:ok, tag}
    end
  end

  @doc """
  Creates a tag.

  ## Examples

      iex> create_tag(%{name: "Summer", slug: "summer"})
      {:ok, %Tag{}}
  """
  def create_tag(attrs \\ %{}) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tag.

  ## Examples

      iex> update_tag(tag, %{name: "New Name"})
      {:ok, %Tag{}}
  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tag.

  ## Examples

      iex> delete_tag(tag)
      {:ok, %Tag{}}
  """
  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  ## Category and Tag Associations

  @doc """
  Associates a product with categories.

  Replaces existing category associations with the provided list.

  ## Examples

      iex> set_product_categories(product, [category1.id, category2.id])
      {:ok, %Product{}}
  """
  def set_product_categories(%Product{} = product, category_ids) do
    product = Repo.preload(product, :categories)
    categories = Repo.all(from c in Category, where: c.id in ^category_ids)

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:categories, categories)
    |> Repo.update()
  end

  @doc """
  Associates a product with tags.

  Replaces existing tag associations with the provided list.

  ## Examples

      iex> set_product_tags(product, [tag1.id, tag2.id])
      {:ok, %Product{}}
  """
  def set_product_tags(%Product{} = product, tag_ids) do
    product = Repo.preload(product, :tags)
    tags = Repo.all(from t in Tag, where: t.id in ^tag_ids)

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, tags)
    |> Repo.update()
  end

  @doc """
  Adds a category to a product.

  ## Examples

      iex> add_product_category(product, category_id)
      {:ok, %Product{}}
  """
  def add_product_category(%Product{} = product, category_id) do
    product = Repo.preload(product, :categories)
    {:ok, category} = get_category(category_id)

    if category in product.categories do
      {:ok, product}
    else
      product
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:categories, [category | product.categories])
      |> Repo.update()
    end
  end

  @doc """
  Adds a tag to a product.

  ## Examples

      iex> add_product_tag(product, tag_id)
      {:ok, %Product{}}
  """
  def add_product_tag(%Product{} = product, tag_id) do
    product = Repo.preload(product, :tags)
    {:ok, tag} = get_tag(tag_id)

    if tag in product.tags do
      {:ok, product}
    else
      product
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:tags, [tag | product.tags])
      |> Repo.update()
    end
  end

  @doc """
  Removes a category from a product.

  ## Examples

      iex> remove_product_category(product, category_id)
      {:ok, %Product{}}
  """
  def remove_product_category(%Product{} = product, category_id) do
    product = Repo.preload(product, :categories)
    categories = Enum.reject(product.categories, &(&1.id == category_id))

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:categories, categories)
    |> Repo.update()
  end

  @doc """
  Removes a tag from a product.

  ## Examples

      iex> remove_product_tag(product, tag_id)
      {:ok, %Product{}}
  """
  def remove_product_tag(%Product{} = product, tag_id) do
    product = Repo.preload(product, :tags)
    tags = Enum.reject(product.tags, &(&1.id == tag_id))

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, tags)
    |> Repo.update()
  end

  ## Inventory Management

  @doc """
  Checks the available stock for a product or variant.

  Returns `{:ok, quantity}` if the product/variant exists, `{:error, :not_found}` otherwise.

  ## Options

  - `:variant_id` - Check stock for a specific variant instead of the base product

  ## Examples

      iex> check_stock(product_id)
      {:ok, 100}

      iex> check_stock(product_id, variant_id: variant_id)
      {:ok, 50}

      iex> check_stock("invalid-id")
      {:error, :not_found}
  """
  def check_stock(product_id, opts \\ []) do
    case opts[:variant_id] do
      nil ->
        case Repo.get(Product, product_id) do
          nil -> {:error, :not_found}
          product -> {:ok, product.stock_quantity}
        end

      variant_id ->
        case Repo.get(ProductVariant, variant_id) do
          nil -> {:error, :not_found}
          variant -> {:ok, variant.stock_quantity}
        end
    end
  end

  @doc """
  Reserves stock for a product or variant.

  This function decreases the stock quantity by the specified amount within a database
  transaction to ensure consistency. It checks that sufficient stock is available before
  reserving.

  Returns `:ok` if successful, `{:error, :insufficient_stock}` if not enough stock is available,
  or `{:error, :not_found}` if the product/variant doesn't exist.

  ## Options

  - `:variant_id` - Reserve stock for a specific variant instead of the base product

  ## Examples

      iex> reserve_stock(product_id, 5)
      :ok

      iex> reserve_stock(product_id, 1000)
      {:error, :insufficient_stock}

      iex> reserve_stock(product_id, 5, variant_id: variant_id)
      :ok
  """
  def reserve_stock(product_id, quantity, opts \\ []) when quantity > 0 do
    Repo.transaction(fn ->
      case opts[:variant_id] do
        nil ->
          product = Repo.get!(Product, product_id)

          if product.manage_stock && product.stock_quantity < quantity do
            Repo.rollback(:insufficient_stock)
          else
            if product.manage_stock do
              product
              |> Ecto.Changeset.change(stock_quantity: product.stock_quantity - quantity)
              |> Repo.update!()
            end

            :ok
          end

        variant_id ->
          variant = Repo.get!(ProductVariant, variant_id)

          if variant.stock_quantity < quantity do
            Repo.rollback(:insufficient_stock)
          else
            variant
            |> Ecto.Changeset.change(stock_quantity: variant.stock_quantity - quantity)
            |> Repo.update!()

            :ok
          end
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, :insufficient_stock} -> {:error, :insufficient_stock}
      {:error, reason} -> {:error, reason}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  @doc """
  Releases (returns) stock for a product or variant.

  This function increases the stock quantity by the specified amount within a database
  transaction. This is typically used when an order is cancelled or refunded.

  Returns `:ok` if successful, or `{:error, :not_found}` if the product/variant doesn't exist.

  ## Options

  - `:variant_id` - Release stock for a specific variant instead of the base product

  ## Examples

      iex> release_stock(product_id, 5)
      :ok

      iex> release_stock(product_id, 5, variant_id: variant_id)
      :ok
  """
  def release_stock(product_id, quantity, opts \\ []) when quantity > 0 do
    Repo.transaction(fn ->
      case opts[:variant_id] do
        nil ->
          product = Repo.get!(Product, product_id)

          if product.manage_stock do
            product
            |> Ecto.Changeset.change(stock_quantity: product.stock_quantity + quantity)
            |> Repo.update!()
          end

          :ok

        variant_id ->
          variant = Repo.get!(ProductVariant, variant_id)

          variant
          |> Ecto.Changeset.change(stock_quantity: variant.stock_quantity + quantity)
          |> Repo.update!()

          :ok
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
