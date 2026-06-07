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

      # Test coverage (excoveralls)
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      dialyzer: [plt_add_apps: [:ex_unit, :mix]],

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

  # Env in which coverage/quality CLI tasks should run.
  def cli do
    [
      preferred_envs: [
        check: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
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
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:decimal, "~> 2.0"},
      {:jason, "~> 1.4"},

      # Development and test dependencies
      {:ex_machina, "~> 2.7", only: :test},
      {:stream_data, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Quality / security tooling
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    """
    An embedded e-commerce engine for Elixir/Phoenix applications with contexts,
    route macros, and extension points for payments, subscriptions, and referrals.
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
        "docs/production_integration.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE"
      ],
      groups_for_modules: [
        "Core Contexts": [
          Mercato.Catalog,
          Mercato.Cart,
          Mercato.Checkout,
          Mercato.Orders,
          Mercato.Customers,
          Mercato.Coupons,
          Mercato.Subscriptions,
          Mercato.Referrals,
          Mercato.Config
        ],
        Schemas: [
          Mercato.Catalog.Product,
          Mercato.Catalog.ProductVariant,
          Mercato.Cart.Cart,
          Mercato.Orders.Order,
          Mercato.Orders.OrderItem,
          Mercato.Coupons.Coupon,
          Mercato.Subscriptions.Subscription
        ],
        Behaviors: [
          Mercato.Behaviours.PaymentGateway,
          Mercato.Behaviours.ShippingCalculator,
          Mercato.Behaviours.TaxCalculator
        ],
        "Phoenix Integration": [
          Mercato.Router,
          Mercato.ReferralController,
          Mercato.Events
        ],
        Utilities: [
          Mercato.Cart.Calculator,
          Mercato.Cart.Manager,
          Mercato.Subscriptions.Scheduler
        ]
      ]
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # Green quality gate for CI: compile cleanly, format, security-scan, audit deps, test.
      #
      # deps.audit ignores GHSA-rhv4-8758-jx7v (Decimal unbounded-exponent DoS): the only
      # fix is decimal 3.0, which ecto (~> 2.0) does not yet allow. Revisit when ecto ships
      # decimal 3.x support. postgrex/jason already permit it.
      # NOTE: `format --check-formatted` is intentionally omitted — the existing codebase
      # is not yet formatted to .formatter.exs. Run a one-time repo-wide `mix format` in a
      # dedicated commit, then add the check here.
      check: [
        "compile --warnings-as-errors",
        "sobelow --config",
        "deps.audit --ignore-advisory-ids GHSA-rhv4-8758-jx7v",
        "test"
      ],
      # Advisory static analysis. Not yet in `check`: the codebase has a pre-existing
      # complexity/readability backlog (tracked in the audit's long-term items). Burn it
      # down, then promote `credo --strict` into `check`.
      lint: ["credo --strict"]
    ]
  end
end
