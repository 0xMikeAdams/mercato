defmodule Mercato.Checkout.Providers.DefaultCheckoutProvider do
  @moduledoc """
  Default checkout provider.

  It creates a stable managed session object, or a redirect handoff when the
  caller provides a redirect URL.
  """

  @behaviour Mercato.Checkout.CheckoutProvider

  alias Mercato.Checkout.{
    CheckoutSession,
    ProgrammaticCheckoutRequest,
    ProgrammaticCheckoutResponse,
    ProviderError
  }

  @impl true
  def create_checkout_session(
        %ProgrammaticCheckoutRequest{} = request,
        %ProgrammaticCheckoutResponse{} = response,
        _opts
      ) do
    if request.session_kind == "redirect" and is_nil(request.redirect_url) do
      {:error,
       %ProviderError{
         provider: inspect(__MODULE__),
         code: :redirect_url_required,
         message: "redirect checkout requires redirect_url",
         details: %{session_kind: request.session_kind}
       }}
    else
      {:ok,
       %CheckoutSession{
         id: stable_id("chk", response.cart_id, request.idempotency_key),
         kind: request.session_kind,
         status: "ready",
         provider: inspect(__MODULE__),
         currency: response.currency,
         totals: response.price_breakdown,
         redirect_url: request.redirect_url,
         payment_client_secret: nil,
         provider_reference: nil,
         expires_at: nil,
         idempotency_key: request.idempotency_key,
         retry_safe: not is_nil(request.idempotency_key),
         metadata: request.metadata
       }}
    end
  end

  defp stable_id(prefix, cart_id, nil) do
    prefix <> "_" <> Ecto.UUID.generate() <> "_" <> cart_id
  end

  defp stable_id(prefix, cart_id, idempotency_key) do
    digest =
      :crypto.hash(:sha256, "#{prefix}:#{cart_id}:#{idempotency_key}")
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 24)

    "#{prefix}_#{digest}"
  end
end
