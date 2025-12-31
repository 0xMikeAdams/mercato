defmodule Mix.Tasks.Mercato.Install do
  @moduledoc """
  Installs Mercato into a Phoenix application.

  This task copies the necessary migrations to your application's priv/repo/migrations
  directory, generates configuration templates, and provides setup instructions.

  ## Usage

      mix mercato.install              # Install with prompts for existing files
      mix mercato.install --force      # Overwrite existing files

  ## What it does

  1. Copies all Mercato migrations to your application
  2. Creates configuration template (config/mercato.exs)
  3. Generates sample router integration (lib/mercato_router_sample.ex)
  4. Creates sample LiveView integration (lib/mercato_liveview_sample.ex)
  5. Displays configuration instructions
  6. Provides next steps for setup

  ## Options

  * `--force` or `-f` - Overwrite existing migrations and configuration files

  ## Configuration

  After running this task, review the generated config/mercato.exs file and copy
  the relevant sections to your application's configuration files.

  Then add Mercato.Repo to your application's supervision tree in application.ex:

      children = [
        # ... your existing children
        Mercato.Repo,
        {Phoenix.PubSub, name: Mercato.PubSub}
      ]

  Finally, run migrations:

      mix ecto.create
      mix ecto.migrate
  """

  use Mix.Task

  @shortdoc "Installs Mercato migrations and provides setup instructions"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean], aliases: [f: :force])

    # Ensure the migrations directory exists
    migrations_path = Path.join([File.cwd!(), "priv", "repo", "migrations"])
    File.mkdir_p!(migrations_path)

    # Copy migrations from Mercato to the host application
    source_migrations = Path.join([:code.priv_dir(:mercato), "repo", "migrations"])

    if File.exists?(source_migrations) do
      copied_count = copy_migrations(source_migrations, migrations_path, opts[:force] || false)

      if copied_count > 0 do
        Mix.shell().info("\n✓ #{copied_count} migrations copied successfully!")
      else
        Mix.shell().info("\n✓ All migrations are already up to date!")
      end
    else
      Mix.shell().info("\nNo migrations found. They will be available in future releases.")
    end

    # Generate configuration template if it doesn't exist
    generate_config_template()

    # Create sample configuration files
    create_sample_configs()

    # Display configuration instructions
    Mix.shell().info("""

    #{IO.ANSI.green()}Mercato installation complete!#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Next steps:#{IO.ANSI.reset()}

    1. Add Mercato configuration to your config/config.exs:

        config :mercato, Mercato.Repo,
          database: "your_app_dev",
          username: "postgres",
          password: "postgres",
          hostname: "localhost"

        config :mercato,
          ecto_repos: [Mercato.Repo]

    2. Update your config/test.exs:

        config :mercato, Mercato.Repo,
          database: "your_app_test\#{System.get_env("MIX_TEST_PARTITION")}",
          pool: Ecto.Adapters.SQL.Sandbox

    3. Add Mercato to your application supervision tree (lib/your_app/application.ex):

        children = [
          # ... your existing children
          Mercato.Repo,
          {Phoenix.PubSub, name: Mercato.PubSub}
        ]

    4. Run migrations:

        mix ecto.create
        mix ecto.migrate

    5. Start using Mercato in your application!

    For more information, visit: https://hexdocs.pm/mercato
    """)
  end

  defp copy_migrations(source_path, dest_path, force?) do
    source_path
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".exs"))
    |> Enum.reduce(0, fn file, count ->
      source = Path.join(source_path, file)
      destination = Path.join(dest_path, file)

      cond do
        not File.exists?(destination) ->
          File.cp!(source, destination)
          Mix.shell().info("* copying #{file}")
          count + 1

        force? ->
          File.cp!(source, destination)
          Mix.shell().info("* overwriting #{file}")
          count + 1

        true ->
          Mix.shell().info("* skipping #{file} (already exists)")
          count
      end
    end)
  end

  defp generate_config_template do
    config_path = "config/mercato.exs"

    unless File.exists?(config_path) do
      config_content = """
      # Mercato Configuration Template
      # Copy the relevant sections to your config files

      # config/config.exs
      config :mercato, Mercato.Repo,
        database: "your_app_dev",
        username: "postgres",
        password: "postgres",
        hostname: "localhost",
        show_sensitive_data_on_connection_error: true,
        pool_size: 10

      config :mercato,
        ecto_repos: [Mercato.Repo],
        # Payment gateway configuration
        payment_gateway: Mercato.PaymentGateways.Dummy,
        # Shipping calculator configuration
        shipping_calculator: Mercato.ShippingCalculators.FlatRate,
        # Tax calculator configuration
        tax_calculator: Mercato.TaxCalculators.Simple,
        # Store settings
        store_settings: %{
          currency: "USD",
          locale: "en",
          default_tax_rate: 0.08,
          store_address: %{
            line1: "123 Store St",
            city: "Store City",
            state: "ST",
            postal_code: "12345",
            country: "US"
          }
        }

      # config/dev.exs
      config :mercato, Mercato.Repo,
        database: "your_app_dev",
        show_sensitive_data_on_connection_error: true,
        pool_size: 10

      # config/test.exs
      config :mercato, Mercato.Repo,
        database: "your_app_test\#{System.get_env("MIX_TEST_PARTITION")}",
        pool: Ecto.Adapters.SQL.Sandbox,
        pool_size: 10

      # config/prod.exs
      config :mercato, Mercato.Repo,
        # Configure your production database URL
        # url: database_url,
        pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
        ssl: true
      """

      File.write!(config_path, config_content)
      Mix.shell().info("* created #{config_path}")
    end
  end

  defp create_sample_configs do
    # Create sample router integration
    router_sample_path = "lib/mercato_router_sample.ex"

    unless File.exists?(router_sample_path) do
      router_content = """
      # Sample Router Integration
      # Add this to your existing router or create a new scope

      defmodule YourAppWeb.Router do
        use YourAppWeb, :router
        import Mercato.Router

        # ... your existing routes

        scope "/api", YourAppWeb do
          pipe_through :api

          # Mount Mercato API routes
          mercato_api_routes()
        end

        # Referral shortlinks
        scope "/", YourAppWeb do
          pipe_through :browser

          get "/r/:code", Mercato.ReferralController, :redirect
        end
      end
      """

      File.write!(router_sample_path, router_content)
      Mix.shell().info("* created #{router_sample_path}")
    end

    # Create sample LiveView integration
    liveview_sample_path = "lib/mercato_liveview_sample.ex"

    unless File.exists?(liveview_sample_path) do
      liveview_content = """
      # Sample LiveView Integration
      # Example of how to integrate Mercato with Phoenix LiveView

      defmodule YourAppWeb.CartLive do
        use YourAppWeb, :live_view
        alias Mercato.{Cart, Events}

        def mount(_params, %{"cart_token" => cart_token}, socket) do
          if connected?(socket) do
            Events.subscribe_to_cart(cart_token)
          end

          {:ok, cart} = Cart.get_cart(cart_token)
          {:ok, assign(socket, cart: cart)}
        end

        def handle_info({:cart_updated, cart}, socket) do
          {:noreply, assign(socket, cart: cart)}
        end

        def handle_event("add_item", %{"product_id" => product_id}, socket) do
          {:ok, cart} = Cart.add_item(socket.assigns.cart.id, product_id, 1)
          {:noreply, assign(socket, cart: cart)}
        end

        def render(assigns) do
          ~H\"\"\"
          <div>
            <h2>Shopping Cart</h2>
            <div>Items: <%= length(@cart.cart_items) %></div>
            <div>Total: $<%= @cart.grand_total %></div>
          </div>
          \"\"\"
        end
      end
      """

      File.write!(liveview_sample_path, liveview_content)
      Mix.shell().info("* created #{liveview_sample_path}")
    end
  end
end
