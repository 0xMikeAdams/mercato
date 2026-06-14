defmodule Mercato.ReferralController do
  @moduledoc """
  Phoenix controller for handling referral shortlinks and tracking.

  This controller provides:
  - `/r/:code` redirect handling
  - click tracking (IP, user agent, referrer)
  - attribution via a cookie

  ## Configuration

      config :mercato,
        store_url: "https://mystore.com",
        referral_cookie_name: "mercato_referral",
        referral_cookie_max_age: 30 * 24 * 60 * 60,
        referral_cookie_http_only: true,
        referral_cookie_same_site: "Lax",
        trust_forwarded_headers: false
  """

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers
  import Phoenix.Controller, except: [redirect: 2]

  alias Mercato.Controllers.Serializer
  alias Mercato.Events
  alias Mercato.Referrals

  require Logger

  def redirect(conn, %{"code" => code}) do
    redirect_url = get_store_url()

    case Referrals.get_referral_code(code) do
      {:ok, referral_code} ->
        click_metadata = extract_click_metadata(conn)

        case Referrals.track_click(code, click_metadata) do
          {:ok, _click} ->
            Events.broadcast_referral_click(referral_code.id, click_metadata)

          {:error, reason} ->
            Logger.warning("Failed to track referral click",
              referral_code: code,
              reason: inspect(reason)
            )
        end

        conn
        |> set_referral_cookie(code)
        |> Phoenix.Controller.redirect(external: redirect_url)

      {:error, :not_found} ->
        Logger.warning("Invalid referral code accessed", referral_code: code)
        Phoenix.Controller.redirect(conn, external: redirect_url)

      {:error, reason} ->
        Logger.error("Error processing referral code",
          referral_code: code,
          reason: inspect(reason)
        )

        Phoenix.Controller.redirect(conn, external: redirect_url)
    end
  end

  def validate(conn, %{"code" => code}) do
    # Public, unauthenticated endpoint: only confirm whether the code is usable.
    # The referrer's id and commission terms are private and must NOT be disclosed
    # to an arbitrary caller (codes are short and enumerable).
    case Referrals.get_referral_code(code) do
      {:ok, referral_code} ->
        json(conn, %{valid: true, code: referral_code.code})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{valid: false, error: "Referral code not found"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{valid: false, error: "Invalid referral code"})
    end
  end

  # Referral statistics are private to the code's owner. There is intentionally no
  # code-based public stats endpoint — requesting `/stats/:code` falls through to
  # this clause, which returns only the *authenticated caller's own* stats and never
  # another user's clicks/conversions/earnings.
  def stats(conn, _params) do
    with {:ok, user_id} <- current_user_id(conn) do
      json(conn, %{data: Serializer.serialize(Referrals.get_referral_stats(user_id))})
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
    end
  end

  def generate_code(conn, %{"referral_code" => attrs}), do: generate_code(conn, attrs)

  def generate_code(conn, attrs) when is_map(attrs) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, referral_code} <- Referrals.generate_referral_code(user_id, attrs) do
      render_data(conn, referral_code, :created)
    else
      {:error, :unauthorized} ->
        render_error(conn, :unauthorized, "unauthorized")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{details: changeset_errors(changeset)})
    end
  end

  def get_code(conn, _params) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, referral_code} <- Referrals.get_referral_code_by_user(user_id) do
      render_data(conn, referral_code)
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end

  defp extract_click_metadata(conn) do
    %{
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn),
      referrer_url: get_referrer_url(conn)
    }
  end

  defp get_client_ip(conn) do
    if trust_forwarded_headers?() do
      conn
      |> forwarded_ip()
      |> case do
        nil -> remote_ip(conn)
        ip -> ip
      end
    else
      remote_ip(conn)
    end
  end

  defp forwarded_ip(conn) do
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()

    real_ip =
      conn
      |> get_req_header("x-real-ip")
      |> List.first()

    candidate =
      cond do
        is_binary(forwarded_for) and forwarded_for != "" ->
          forwarded_for |> String.split(",") |> List.first() |> String.trim()

        is_binary(real_ip) and real_ip != "" ->
          String.trim(real_ip)

        true ->
          nil
      end

    if is_binary(candidate) and valid_ip?(candidate), do: candidate, else: nil
  end

  defp remote_ip(conn) do
    case conn.remote_ip do
      ip when is_tuple(ip) ->
        ip |> :inet.ntoa() |> to_string()

      _ ->
        "0.0.0.0"
    end
  end

  defp valid_ip?(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp get_user_agent(conn) do
    get_req_header(conn, "user-agent") |> List.first()
  end

  defp get_referrer_url(conn) do
    get_req_header(conn, "referer") |> List.first()
  end

  defp set_referral_cookie(conn, code) do
    cookie_name = Application.get_env(:mercato, :referral_cookie_name, "mercato_referral")
    max_age = Application.get_env(:mercato, :referral_cookie_max_age, 30 * 24 * 60 * 60)
    http_only = Application.get_env(:mercato, :referral_cookie_http_only, true)
    same_site = Application.get_env(:mercato, :referral_cookie_same_site, "Lax")

    put_resp_cookie(conn, cookie_name, code,
      max_age: max_age,
      http_only: http_only,
      secure: conn.scheme == :https,
      same_site: same_site
    )
  end

  defp get_store_url do
    Application.get_env(:mercato, :store_url, "/")
  end

  defp trust_forwarded_headers? do
    Application.get_env(:mercato, :trust_forwarded_headers, false)
  end
end
