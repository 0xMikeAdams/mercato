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
    {_app_module, repo_module, pubsub_module} = detect_app_modules()

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

    updated = inject_router_contents(router_contents, force?)

    if updated != router_contents do
      File.write!(router_path, updated)
      Mix.shell().info("* updated #{router_path} (routes)")
    end
  end

  @doc false
  def inject_router_contents(router_contents, force? \\ false) when is_binary(router_contents) do
    router_contents
    |> remove_block("MERCATO")
    |> remove_block("MERCATO_IMPORT")
    |> remove_block("MERCATO_API")
    |> remove_block("MERCATO_REFERRAL")
    |> upsert_router_import!(force?)
    |> upsert_api_routes!(force?)
    |> upsert_referral_routes!(force?)
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
          ~r/^\s*#{Regex.escape(begin_marker)}\s*$.*?^\s*#{Regex.escape(end_marker)}\s*$/ms,
          contents,
          String.trim_trailing(block)
        )

      true ->
        String.trim_trailing(contents) <> "\n\n" <> String.trim_trailing(block) <> "\n"
    end
  end

  defp remove_block(contents, marker) do
    begin_marker = "# BEGIN #{marker}"
    end_marker = "# END #{marker}"

    Regex.replace(
      ~r/^\s*#{Regex.escape(begin_marker)}\s*$.*?^\s*#{Regex.escape(end_marker)}\s*$\n?/ms,
      contents,
      ""
    )
  end

  defp upsert_router_import!(router_contents, force?) do
    block = """
    # BEGIN MERCATO_IMPORT
    import Mercato.Router
    # END MERCATO_IMPORT
    """

    begin_marker = "# BEGIN MERCATO_IMPORT"

    if String.contains?(router_contents, begin_marker) do
      upsert_block(router_contents, "MERCATO_IMPORT", block, force?)
    else
      lines = String.split(router_contents, "\n", trim: false)

      use_line_idx =
        Enum.find_index(lines, fn line ->
          String.match?(line, ~r/^\s*use\s+.+,\s*:router\s*$/) or
            String.match?(line, ~r/^\s*use\s+Phoenix\.Router\s*$/)
        end)

      insert_after_idx =
        cond do
          is_integer(use_line_idx) -> use_line_idx + 1
          true -> 1
        end

      indent =
        lines
        |> Enum.at(max(insert_after_idx - 1, 0), "")
        |> leading_whitespace()

      indent = if indent == "", do: "  ", else: indent

      indented_block = indent_block(block, indent)
      block_lines = String.split(indented_block, "\n", trim: false)

      {head, tail} = Enum.split(lines, insert_after_idx)

      Enum.join(insert_lines_with_spacing(head, block_lines, tail), "\n")
    end
  end

  defp upsert_api_routes!(router_contents, force?) do
    api_block = """
    # BEGIN MERCATO_API
    scope "/mercato", alias: Mercato, as: false do
      mercato_basic_routes(controllers: Mercato.Controllers)
      get "/referrals/validate/:code", ReferralController, :validate
      get "/referrals/stats/:code", ReferralController, :stats
    end
    # END MERCATO_API
    """

    case find_best_scope(router_contents, &api_scope_path?/1, &scope_contains_api_pipe_through?/1) do
      {:ok, %{insert_before_end_line: insert_before_end_line, inner_indent: inner_indent}} ->
        inject_block_at_line(router_contents, insert_before_end_line, indent_block(api_block, inner_indent))

      :error ->
        # Fallback: append a self-contained API scope block near the bottom of the router module.
        fallback = """
        # BEGIN MERCATO_API
        scope "/api/mercato", alias: Mercato, as: false do
          pipe_through :api
          mercato_basic_routes(controllers: Mercato.Controllers)
          get "/referrals/validate/:code", ReferralController, :validate
          get "/referrals/stats/:code", ReferralController, :stats
        end
        # END MERCATO_API
        """

        upsert_block_before_last_end(router_contents, "MERCATO_API", fallback, force?)
    end
  end

  defp upsert_referral_routes!(router_contents, force?) do
    block = """
    # BEGIN MERCATO_REFERRAL
    scope "/", alias: Mercato, as: false do
      get "/r/:code", ReferralController, :redirect
    end
    # END MERCATO_REFERRAL
    """

    case find_best_scope(router_contents, &browser_scope_path?/1, &scope_contains_browser_pipe_through?/1) do
      {:ok, %{insert_before_end_line: insert_before_end_line, inner_indent: inner_indent}} ->
        inject_block_at_line(router_contents, insert_before_end_line, indent_block(block, inner_indent))

      :error ->
        # Fallback: inject at module level near the bottom.
        upsert_block_before_last_end(router_contents, "MERCATO_REFERRAL", indent_block(block, "  "), force?)
    end
  end

  defp inject_block_at_line(contents, insert_before_end_line, indented_block) do
    lines = String.split(contents, "\n", trim: false)
    {head, tail} = Enum.split(lines, insert_before_end_line)
    block_lines = String.split(indented_block, "\n", trim: false)
    Enum.join(insert_lines_with_spacing(head, block_lines, tail), "\n")
  end

  defp insert_lines_with_spacing(head, block_lines, tail) do
    head =
      case List.last(head) do
        nil -> head
        last ->
          if String.trim(last) == "" do
            head
          else
            head ++ [""]
          end
      end

    tail =
      case tail do
        [] -> tail
        [first | _] ->
          if String.trim(first) == "" do
            tail
          else
            [""] ++ tail
          end
      end

    head ++ block_lines ++ tail
  end

  defp find_best_scope(contents, path_pred, pipe_pred) do
    lines = String.split(contents, "\n", trim: false)

    scope_starts =
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} -> String.match?(line, ~r/^\s*scope\s+"/) and String.contains?(line, " do") end)
      |> Enum.map(fn {line, idx} -> {idx, line} end)

    candidates =
      Enum.flat_map(scope_starts, fn {idx, line} ->
        case Regex.run(~r/^\s*scope\s+"([^"]+)"/, line) do
          [_, path] ->
            if path_pred.(path) do
              case scope_region(lines, idx) do
                {:ok, %{end_idx: end_idx, body: body}} ->
                  scope_indent = leading_whitespace(line)
                  inner_indent = scope_indent <> "  "

                  [
                    %{
                      start_idx: idx,
                      end_idx: end_idx,
                      insert_before_end_line: end_idx,
                      inner_indent: inner_indent,
                      pipe_match?: pipe_pred.(body)
                    }
                  ]

                :error ->
                  []
              end
            else
              []
            end

          _ ->
            []
        end
      end)

    best =
      candidates
      |> Enum.sort_by(fn c -> {if(c.pipe_match?, do: 0, else: 1), c.start_idx} end)
      |> List.first()

    if best, do: {:ok, best}, else: :error
  end

  defp scope_region(lines, start_idx) do
    with {:ok, end_idx} <- find_matching_end(lines, start_idx) do
      body = Enum.slice(lines, start_idx, end_idx - start_idx + 1) |> Enum.join("\n")
      {:ok, %{end_idx: end_idx, body: body}}
    end
  end

  defp find_matching_end(lines, start_idx) do
    initial = Enum.at(lines, start_idx, "")
    depth = do_count(initial) - end_count(initial)

    if depth <= 0 do
      :error
    else
      result =
        Enum.reduce_while((start_idx + 1)..(length(lines) - 1), depth, fn idx, acc ->
          line = Enum.at(lines, idx, "")
          next = acc + do_count(line) - end_count(line)

          if next == 0 do
            {:halt, {:ok, idx}}
          else
            {:cont, next}
          end
        end)

      case result do
        {:ok, _idx} = ok -> ok
        _ -> :error
      end
    end
  end

  defp do_count(line) do
    line
    |> strip_comments()
    |> strip_double_quoted_strings()
    |> then(fn cleaned -> Regex.scan(~r/\bdo\b/, cleaned) |> length() end)
  end

  defp end_count(line) do
    line
    |> strip_comments()
    |> strip_double_quoted_strings()
    |> then(fn cleaned -> Regex.scan(~r/\bend\b/, cleaned) |> length() end)
  end

  defp strip_comments(line) do
    case String.split(line, "#", parts: 2) do
      [code] -> code
      [code, _comment] -> code
    end
  end

  defp strip_double_quoted_strings(line) do
    # Good-enough for router files; avoids counting `do`/`end` in string literals.
    Regex.replace(~r/"(?:\\.|[^"\\])*"/, line, "\"\"")
  end

  defp leading_whitespace(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, ws] -> ws
      _ -> ""
    end
  end

  defp indent_block(block, indent) do
    block
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      if String.trim(line) == "" do
        ""
      else
        indent <> String.trim_trailing(line)
      end
    end)
  end

  defp api_scope_path?(path) when is_binary(path) do
    String.starts_with?(path, "/api")
  end

  defp browser_scope_path?(path) when is_binary(path) do
    path == "/" or path == ""
  end

  defp scope_contains_api_pipe_through?(body) do
    String.contains?(body, "pipe_through :api") or String.contains?(body, "pipe_through [:api")
  end

  defp scope_contains_browser_pipe_through?(body) do
    String.contains?(body, "pipe_through :browser") or String.contains?(body, "pipe_through [:browser")
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
