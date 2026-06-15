defmodule Mercato.Controllers.Helpers do
  @moduledoc false

  import Phoenix.Controller
  import Plug.Conn, only: [put_status: 2]

  alias Mercato.Controllers.Serializer

  def render_data(conn, data, status \\ :ok) do
    conn
    |> put_status(status)
    |> json(%{data: Serializer.serialize(data)})
  end

  def render_error(conn, status, error, extra \\ %{}) do
    body =
      extra
      |> Map.new()
      |> Map.put(:error, error)
      |> Serializer.serialize()

    conn
    |> put_status(status)
    |> json(body)
  end

  @doc """
  Builds a safe error-detail map from an internal `reason`.

  Atom reasons are stable, intentional identifiers (e.g. `:out_of_stock`,
  `:invalid_quantity`) and are exposed as a string. Anything else — tuples,
  changesets, arbitrary terms — is omitted, so internal field names and control-flow
  detail never leak into a client response (replaces `inspect(reason)`).
  """
  def error_detail(reason) when is_atom(reason), do: %{reason: Atom.to_string(reason)}
  def error_detail(_reason), do: %{}

  def current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  def current_user_id(conn) do
    with {:ok, user} <- current_user(conn) do
      case user_id(user) do
        nil -> {:error, :unauthorized}
        user_id -> {:ok, user_id}
      end
    end
  end

  def admin_authorized?(conn), do: !!conn.assigns[:mercato_admin?]

  def ensure_admin(conn) do
    if admin_authorized?(conn) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  def maybe_put(opts, _key, nil), do: opts
  def maybe_put(opts, _key, ""), do: opts
  def maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  def parse_integer(nil), do: {:error, :missing_integer}
  def parse_integer(""), do: {:error, :missing_integer}
  def parse_integer(value) when is_integer(value), do: {:ok, value}

  def parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _ -> {:error, :invalid_integer}
    end
  end

  def parse_decimal(nil), do: {:error, :missing_decimal}
  def parse_decimal(""), do: {:error, :missing_decimal}
  def parse_decimal(%Decimal{} = value), do: {:ok, value}

  # Bound on the length of a money string accepted from a request. Real amounts are far
  # shorter; this caps the input that reaches Decimal.new.
  @max_decimal_string_length 32

  def parse_decimal(value) when is_binary(value) do
    cond do
      String.length(value) > @max_decimal_string_length ->
        {:error, :invalid_decimal}

      # Reject scientific/exponent notation. Money values never use it, and an unbounded
      # exponent (e.g. "1E2147483647") is the DoS vector behind GHSA-rhv4-8758-jx7v for
      # consumers that resolve decimal < 3.0 (our constraint allows `~> 2.0 or ~> 3.0`).
      String.contains?(value, ["e", "E"]) ->
        {:error, :invalid_decimal}

      true ->
        try do
          {:ok, Decimal.new(value)}
        rescue
          _error -> {:error, :invalid_decimal}
        end
    end
  end

  def parse_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}
  def parse_decimal(value) when is_float(value), do: {:ok, Decimal.from_float(value)}

  def fetch_required(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing, key}}
      "" -> {:error, {:missing, key}}
      value -> {:ok, value}
    end
  end

  defp user_id(%{id: id}), do: id
  defp user_id(%{"id" => id}), do: id
  defp user_id(id) when is_binary(id), do: id
  defp user_id(_user), do: nil
end
