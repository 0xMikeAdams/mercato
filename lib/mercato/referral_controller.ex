if Code.ensure_loaded?(Phoenix.Controller) do
  defmodule Mercato.ReferralController do
  @moduledoc """
  Phoenix controller for handling referral shortlinks and tracking.

  This controller provides functionality for:
  - Handling `/r/:code` shortlink redirects
  - Tracking referral clicks with metadata
  - Redirecting users to the store with referral attribution

  ## Usage

  Add the referral route to your Phoenix router:

      defmodule MyAppWeb.Router do
        use Phoenix.Router

        # Referral shortlink route (should be at root level)
        get "/r/:code", Mercato.ReferralController, :redirect

        # Or use the helper macro
        import Mercato.Router
        mercato_referral_routes()
      end

  ## Configuration

  Configure the redirect URL in your application config:

      config :mercato,
        store_url: "https://mystore.com",
        referral_cookie_name: "mercato_referral",
        referral_cookie_max_age: 30 * 24 * 60 * 60  # 30 days in seconds

  ## Referral Attribution

  When a user clicks a referral link:
  1. The click is tracked with IP, user agent, and referrer
  2. A cookie is set with the referral code for attribution
  3. The user is redirected to the configured store URL
  4. Future orders can be attributed using the cookie value

  ## Error Handling

  - Invalid or expired referral codes redirect to the store without attribution
  - Missing configuration falls back to "/" redirect
  - All errors are logged for debugging
  """

  if Code.ensure_loaded?(Phoenix.Controller) do
    use Phoenix.Controller, namespace: false
  end

  alias Mercato.Referrals
  alias Mercato.Events

  require Logger

  @doc """
  Handles referral shortlink redirects.

  Tracks the click, sets attribution cookie, and redirects to the store.

  ## Parameters

  - `code` - The referral code from the URL path

  ## Response

  Redirects to the configured store URL with referral attribution.
  """
  def redirect(conn, %{"code" => code}) do
    case Referrals.get_referral_code(code) do
      {:ok, referral_code} ->
        # Track the click
        click_metadata = extract_click_metadata(conn)
        {:ok, _click} = Referrals.track_click(code, click_metadata)

        # Set attribution cookie
        conn = set_referral_cookie(conn, code)

        # Broadcast click event
        Events.broadcast_referral_click(referral_code.id, click_metadata)

        # Redirect to store
        redirect_url = get_store_url()

        Logger.info("Referral click tracked",
          referral_code: code,
          ip: click_metadata.ip_address,
          redirect_url: redirect_url
        )

        redirect(conn, external: redirect_url)

      {:error, :not_found} ->
        Logger.warn("Invalid referral code accessed", code: code)

        # Still redirect to store, but without attribution
        redirect_url = get_store_url()
        redirect(conn, external: redirect_url)

      {:error, reason} ->
        Logger.error("Error processing referral code",
          code: code,
          reason: inspect(reason)
        )

        # Fallback redirect
        redirect_url = get_store_url()
        redirect(conn, external: redirect_url)
    end
  end

  @doc """
  Handles referral code validation for API requests.

  Returns referral code information without redirecting.
  Useful for AJAX requests or API integrations.
  """
  def validate(conn, %{"code" => code}) do
    case Referrals.get_referral_code(code) do
      {:ok, referral_code} ->
        json(conn, %{
          valid: true,
          code: referral_code.code,
          referrer_id: referral_code.user_id,
          commission_type: referral_code.commission_type,
          commission_value: referral_code.commission_value
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{valid: false, error: "Referral code not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{valid: false, error: "Invalid referral code", reason: inspect(reason)})
    end
  end

  @doc """
  Returns referral statistics for analytics.

  Requires the referral code to be valid and active.
  """
  def stats(conn, %{"code" => code}) do
    case Referrals.get_referral_code(code) do
      {:ok, referral_code} ->
        stats = Referrals.get_referral_stats(referral_code.user_id)

        json(conn, %{
          code: referral_code.code,
          clicks: referral_code.clicks_count,
          conversions: referral_code.conversions_count,
          total_commission: referral_code.total_commission,
          stats: stats
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Referral code not found"})
    end
  end

  # Private helper functions

  defp extract_click_metadata(conn) do
    %{
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn),
      referrer_url: get_referrer_url(conn)
    }
  end

  defp get_client_ip(conn) do
    # Check for forwarded IP headers first (for load balancers/proxies)
    forwarded_for = get_req_header(conn, "x-forwarded-for") |> List.first()
    real_ip = get_req_header(conn, "x-real-ip") |> List.first()

    cond do
      forwarded_for && forwarded_for != "" ->
        # X-Forwarded-For can contain multiple IPs, take the first one
        forwarded_for |> String.split(",") |> List.first() |> String.trim()

      real_ip && real_ip != "" ->
        real_ip

      true ->
        # Fallback to remote IP from connection
        case conn.remote_ip do
          {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
          {a, b, c, d, e, f, g, h} ->
            # IPv6 format
            [a, b, c, d, e, f, g, h]
            |> Enum.map(&Integer.to_string(&1, 16))
            |> Enum.join(":")
          _ -> "unknown"
        end
    end
  end

  defp get_user_agent(conn) do
    get_req_header(conn, "user-agent") |> List.first() || "unknown"
  end

  defp get_referrer_url(conn) do
    get_req_header(conn, "referer") |> List.first()
  end

  defp set_referral_cookie(conn, code) do
    cookie_name = get_cookie_name()
    max_age = get_cookie_max_age()

    put_resp_cookie(conn, cookie_name, code,
      max_age: max_age,
      http_only: false,  # Allow JavaScript access for frontend integration
      secure: conn.scheme == :https,
      same_site: "Lax"
    )
  end

  defp get_store_url do
    Application.get_env(:mercato, :store_url, "/")
  end

  defp get_cookie_name do
    Application.get_env(:mercato, :referral_cookie_name, "mercato_referral")
  end

  defp get_cookie_max_age do
    # Default to 30 days
    Application.get_env(:mercato, :referral_cookie_max_age, 30 * 24 * 60 * 60)
  end
  end
end
