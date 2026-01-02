defmodule Mix.Tasks.Mercato.Install do
  @moduledoc """
  Installs Mercato into a Phoenix application.

  This task copies the Mercato migrations into your application and injects the required
  configuration and router wiring directly (no manual copy/paste).

  ## Usage

      mix mercato.install
      mix mercato.install --force

  ## What it does

  1. Copies all Mercato migrations to `priv/repo/migrations`
  2. Creates/updates `config/mercato.exs` and ensures `config/config.exs` imports it
  3. Injects Mercato routes into your Phoenix router (basic API + referral shortlink)

  ## Options

  * `--force` or `-f` - Overwrite existing migrations and configuration files
  """

  use Mix.Task

  @shortdoc "Installs Mercato migrations and injects config/routes"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, switches: [force: :boolean], aliases: [f: :force])

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

    force? = opts[:force] || false

    ensure_config_imported!("config/config.exs", "mercato.exs")
    upsert_mercato_config!("config/mercato.exs", force?)
    inject_router!("", force?)

    Mix.shell().info("""

    #{IO.ANSI.green()}Mercato installation complete!#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Next steps:#{IO.ANSI.reset()}

    1. Run migrations:

        mix ecto.migrate

    2. Start your server and hit:

        GET /api/mercato/products
        POST /api/mercato/carts
        GET /r/:code
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

  defp ensure_config_imported!(config_path, imported_file) do
    unless File.exists?(config_path) do
      Mix.raise("Expected #{config_path} to exist")
    end

    line = "import_config \"#{imported_file}\""
    contents = File.read!(config_path)

    if String.contains?(contents, line) do
      :ok
    else
      env_import_re = ~r/^\s*import_config\s+"#\{config_env\(\)\}\.exs"\s*$/m

      updated =
        if Regex.match?(env_import_re, contents) do
          # Typical pattern: `import_config "#{config_env()}.exs"`
          Regex.replace(env_import_re, contents, line <> "\n\\0")
        else
          contents <> "\n\n" <> line <> "\n"
        end

      File.write!(config_path, updated)
      Mix.shell().info("* updated #{config_path} (import_config #{imported_file})")
    end
  end

  defp upsert_mercato_config!(path, force?) do
    {app_module, repo_module, pubsub_module} = detect_app_modules()

    file_header =
      if File.exists?(path) do
        File.read!(path)
      else
        "import Config\n"
      end

    block = """
    # BEGIN MERCATO
    config :mercato,
      repo: #{inspect(repo_module)},
      pubsub: #{inspect(pubsub_module)},
      payment_gateway: Mercato.PaymentGateways.Dummy,
      shipping_calculator: Mercato.ShippingCalculators.FlatRate,
      tax_calculator: Mercato.TaxCalculators.Simple,
      store_url: "/",
      referral_cookie_name: "mercato_referral",
      referral_cookie_max_age: 30 * 24 * 60 * 60,
      referral_cookie_http_only: true,
      referral_cookie_same_site: "Lax",
      trust_forwarded_headers: false

    config :mercato, Mercato.Subscriptions.Scheduler,
      enabled: false
    # END MERCATO
    """

    updated = upsert_block(file_header, "MERCATO", block, force?)
    File.write!(path, updated)
    Mix.shell().info("* updated #{path}")
  end

  defp inject_router!(_root, force?) do
    router_path = find_router_path!()
    router_contents = File.read!(router_path)

    {app_module, _repo_module, _pubsub_module} = detect_app_modules()

    web_module =
      case Regex.run(~r/^\s*defmodule\s+([A-Za-z0-9_.]+)\.Router\s+do\s*$/m, router_contents) do
        [_, mod] -> Module.concat([mod])
        _ -> nil
      end

    scope_module =
      case web_module do
        nil -> app_module <> "Web"
        mod -> mod |> Atom.to_string() |> String.trim_leading("Elixir.")
      end

    block = """
      # BEGIN MERCATO
      import Mercato.Router

      pipeline :mercato_api do
        plug :accepts, ["json"]
      end

      scope "/api/mercato", #{scope_module} do
        pipe_through :mercato_api
        mercato_basic_routes(controllers: Mercato.Controllers)
      end

      mercato_referral_routes(api_prefix: "/api/mercato")
      # END MERCATO
    """

    updated = upsert_block_before_last_end(router_contents, "MERCATO", block, force?)

    if updated != router_contents do
      File.write!(router_path, updated)
      Mix.shell().info("* updated #{router_path} (routes)")
    end
  end

  defp upsert_block_before_last_end(contents, marker, block, force?) do
    begin_marker = "# BEGIN #{marker}"
    end_marker = "# END #{marker}"

    cond do
      String.contains?(contents, begin_marker) and String.contains?(contents, end_marker) ->
        upsert_block(contents, marker, block, force?)

      true ->
        case Regex.scan(~r/^end\s*$/m, contents, return: :index) do
          [] ->
            String.trim_trailing(contents) <> "\n\n" <> String.trim_trailing(block) <> "\n"

          matches ->
            {start, _len} = List.last(matches) |> hd()
            {head, tail} = String.split_at(contents, start)
            String.trim_trailing(head) <> "\n\n" <> String.trim_trailing(block) <> "\n\n" <> tail
        end
    end
  end

  defp upsert_block(contents, marker, block, _force?) do
    begin_marker = "# BEGIN #{marker}"
    end_marker = "# END #{marker}"

    cond do
      String.contains?(contents, begin_marker) and String.contains?(contents, end_marker) ->
        Regex.replace(
          ~r/^\s*#{Regex.escape(begin_marker)}.*?^\s*#{Regex.escape(end_marker)}\s*$/ms,
          contents,
          String.trim_trailing(block)
        )

      true ->
        String.trim_trailing(contents) <> "\n\n" <> String.trim_trailing(block) <> "\n"
    end
  end

  defp find_router_path! do
    candidates =
      ["lib/**/*router.ex", "apps/*/lib/**/*router.ex"]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()

    case Enum.find(candidates, &router_file?/1) do
      nil -> Mix.raise("Could not find a Phoenix router file (looked for lib/**/*router.ex)")
      path -> path
    end
  end

  defp router_file?(path) do
    content = File.read!(path)
    String.contains?(content, "defmodule") and String.contains?(content, ".Router") and
      (String.contains?(content, ":router") or String.contains?(content, "use Phoenix.Router"))
  end

  defp detect_app_modules do
    app = Mix.Project.config()[:app] || :app
    app_module = app |> to_string() |> Macro.camelize()

    repo_module = Module.concat([app_module, "Repo"])
    pubsub_module = Module.concat([app_module, "PubSub"])

    {app_module, repo_module, pubsub_module}
  end
end
