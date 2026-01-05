defmodule Mercato.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/0xMikeAdams/mercato"
  @homepage_url "https://github.com/0xMikeAdams/mercato"

  def project do
    [
      app: :mercato,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Hex package configuration
      description: description(),
      package: package(),

      # Documentation configuration
      docs: docs(),

      # Additional metadata
      name: "Mercato",
      source_url: @source_url,
      homepage_url: @homepage_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mercato.Application, []}
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies
      {:ecto, "~> 3.11"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},
      {:phoenix, "~> 1.7", optional: true},
      {:phoenix_pubsub, "~> 2.1"},
      {:decimal, "~> 2.0"},
      {:jason, "~> 1.4"},

      # Development and test dependencies
      {:ex_machina, "~> 2.7", only: :test},
      {:stream_data, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A production-ready, open-source e-commerce engine for Elixir/Phoenix applications.
    Provides real-time capabilities, extensible architecture, and comprehensive e-commerce
    features including product catalogs, shopping carts, order management, subscriptions, and referral systems.
    """
  end

  defp package do
    [
      name: "mercato",
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md CONTRIBUTING.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Documentation" => "https://hexdocs.pm/mercato"
      },
      maintainers: ["Mercato Contributors"]
    ]
  end

  defp docs do
    [
      main: "Mercato",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Core Contexts": [
          Mercato.Catalog,
          Mercato.Cart,
          Mercato.Orders,
          Mercato.Customers,
          Mercato.Coupons,
          Mercato.Subscriptions,
          Mercato.Referrals,
          Mercato.Config
        ],
        "Schemas": [
          Mercato.Catalog.Product,
          Mercato.Catalog.ProductVariant,
          Mercato.Cart.Cart,
          Mercato.Orders.Order,
          Mercato.Orders.OrderItem,
          Mercato.Coupons.Coupon,
          Mercato.Subscriptions.Subscription
        ],
        "Behaviors": [
          Mercato.Behaviours.PaymentGateway,
          Mercato.Behaviours.ShippingCalculator,
          Mercato.Behaviours.TaxCalculator
        ],
        "Phoenix Integration": [
          Mercato.Router,
          Mercato.ReferralController,
          Mercato.Events
        ],
        "Utilities": [
          Mercato.Cart.Calculator,
          Mercato.Cart.Manager,
          Mercato.Subscriptions.Scheduler
        ]
      ]
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
