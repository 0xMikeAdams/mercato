defmodule Mercato.CatalogTest do
  use ExUnit.Case, async: true
  alias Mercato.Catalog

  setup do
    # Ensure we're using the test database
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mercato.Repo)
  end

  describe "products" do
    test "create_product/1 creates a product with valid attributes" do
      attrs = %{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple",
        status: "published"
      }

      assert {:ok, product} = Catalog.create_product(attrs)
      assert product.name == "Test Product"
      assert product.slug == "test-product"
      assert Decimal.equal?(product.price, Decimal.new("29.99"))
      assert product.sku == "TEST-001"
      assert product.product_type == "simple"
      assert product.status == "published"
    end

    test "list_products/0 returns all products" do
      {:ok, _product1} = Catalog.create_product(%{
        name: "Product 1",
        slug: "product-1",
        price: Decimal.new("10.00"),
        sku: "PROD-001",
        product_type: "simple"
      })

      {:ok, _product2} = Catalog.create_product(%{
        name: "Product 2",
        slug: "product-2",
        price: Decimal.new("20.00"),
        sku: "PROD-002",
        product_type: "simple"
      })

      products = Catalog.list_products()
      assert length(products) == 2
    end

    test "get_product!/1 returns the product with given id" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple"
      })

      found_product = Catalog.get_product!(product.id)
      assert found_product.id == product.id
      assert found_product.name == "Test Product"
    end

    test "update_product/2 updates the product" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple"
      })

      assert {:ok, updated_product} = Catalog.update_product(product, %{name: "Updated Product"})
      assert updated_product.name == "Updated Product"
      assert updated_product.slug == "test-product"
    end

    test "delete_product/1 deletes the product" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple"
      })

      assert {:ok, _} = Catalog.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_product!(product.id) end
    end
  end

  describe "inventory management" do
    test "check_stock/1 returns the stock quantity" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple",
        stock_quantity: 100
      })

      assert {:ok, 100} = Catalog.check_stock(product.id)
    end

    test "reserve_stock/2 decreases stock quantity" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple",
        stock_quantity: 100
      })

      assert :ok = Catalog.reserve_stock(product.id, 10)
      assert {:ok, 90} = Catalog.check_stock(product.id)
    end

    test "reserve_stock/2 returns error when insufficient stock" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple",
        stock_quantity: 5
      })

      assert {:error, :insufficient_stock} = Catalog.reserve_stock(product.id, 10)
      assert {:ok, 5} = Catalog.check_stock(product.id)
    end

    test "release_stock/2 increases stock quantity" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple",
        stock_quantity: 100
      })

      assert :ok = Catalog.release_stock(product.id, 10)
      assert {:ok, 110} = Catalog.check_stock(product.id)
    end
  end

  describe "variants" do
    test "create_variant/2 creates a variant for a product" do
      {:ok, product} = Catalog.create_product(%{
        name: "Variable Product",
        slug: "variable-product",
        price: Decimal.new("29.99"),
        sku: "VAR-001",
        product_type: "variable"
      })

      attrs = %{
        sku: "VAR-001-L-BLUE",
        price: Decimal.new("29.99"),
        stock_quantity: 50,
        attributes: %{"size" => "L", "color" => "blue"}
      }

      assert {:ok, variant} = Catalog.create_variant(product.id, attrs)
      assert variant.product_id == product.id
      assert variant.sku == "VAR-001-L-BLUE"
      assert variant.attributes == %{"size" => "L", "color" => "blue"}
    end

    test "list_variants/1 returns all variants for a product" do
      {:ok, product} = Catalog.create_product(%{
        name: "Variable Product",
        slug: "variable-product",
        price: Decimal.new("29.99"),
        sku: "VAR-001",
        product_type: "variable"
      })

      {:ok, _variant1} = Catalog.create_variant(product.id, %{
        sku: "VAR-001-L",
        price: Decimal.new("29.99")
      })

      {:ok, _variant2} = Catalog.create_variant(product.id, %{
        sku: "VAR-001-XL",
        price: Decimal.new("31.99")
      })

      variants = Catalog.list_variants(product.id)
      assert length(variants) == 2
    end
  end

  describe "categories" do
    test "create_category/1 creates a category" do
      attrs = %{
        name: "Clothing",
        slug: "clothing",
        description: "All clothing items"
      }

      assert {:ok, category} = Catalog.create_category(attrs)
      assert category.name == "Clothing"
      assert category.slug == "clothing"
    end

    test "list_categories/0 returns all categories" do
      {:ok, _cat1} = Catalog.create_category(%{name: "Category 1", slug: "category-1"})
      {:ok, _cat2} = Catalog.create_category(%{name: "Category 2", slug: "category-2"})

      categories = Catalog.list_categories()
      assert length(categories) == 2
    end
  end

  describe "tags" do
    test "create_tag/1 creates a tag" do
      attrs = %{
        name: "Summer",
        slug: "summer"
      }

      assert {:ok, tag} = Catalog.create_tag(attrs)
      assert tag.name == "Summer"
      assert tag.slug == "summer"
    end

    test "list_tags/0 returns all tags" do
      {:ok, _tag1} = Catalog.create_tag(%{name: "Tag 1", slug: "tag-1"})
      {:ok, _tag2} = Catalog.create_tag(%{name: "Tag 2", slug: "tag-2"})

      tags = Catalog.list_tags()
      assert length(tags) == 2
    end
  end

  describe "product associations" do
    test "set_product_categories/2 associates categories with a product" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple"
      })

      {:ok, cat1} = Catalog.create_category(%{name: "Category 1", slug: "category-1"})
      {:ok, cat2} = Catalog.create_category(%{name: "Category 2", slug: "category-2"})

      assert {:ok, updated_product} = Catalog.set_product_categories(product, [cat1.id, cat2.id])
      updated_product = Mercato.Repo.preload(updated_product, :categories)
      assert length(updated_product.categories) == 2
    end

    test "set_product_tags/2 associates tags with a product" do
      {:ok, product} = Catalog.create_product(%{
        name: "Test Product",
        slug: "test-product",
        price: Decimal.new("29.99"),
        sku: "TEST-001",
        product_type: "simple"
      })

      {:ok, tag1} = Catalog.create_tag(%{name: "Tag 1", slug: "tag-1"})
      {:ok, tag2} = Catalog.create_tag(%{name: "Tag 2", slug: "tag-2"})

      assert {:ok, updated_product} = Catalog.set_product_tags(product, [tag1.id, tag2.id])
      updated_product = Mercato.Repo.preload(updated_product, :tags)
      assert length(updated_product.tags) == 2
    end
  end
end
