defmodule Mercato.Checkout.Providers.LegacyPaymentProvider do
  @moduledoc """
  Payment-provider adapter that wraps the existing `Mercato.Behaviours.PaymentGateway`.

  It supports fully server-side payment authorization/capture flows. Host apps can
  replace it with a Stripe-style provider that returns redirect URLs or client secrets.
  """

  @behaviour Mercato.Checkout.PaymentProvider

  alias Mercato.Checkout.{
    CheckoutSession,
    Money,
    ProgrammaticCheckoutRequest,
    ProgrammaticCheckoutResponse,
    ProviderError,
    ValidationError
  }

  alias Mercato.Runtime

  @impl true
  def create_payment_session(
        %ProgrammaticCheckoutRequest{} = request,
        %ProgrammaticCheckoutResponse{} = response,
        opts
      ) do
    with payment_details when is_map(payment_details) <- request.payment_details,
         {:ok, gateway} <- Runtime.fetch_payment_gateway(opts),
         amount <- Money.to_decimal(response.price_breakdown.grand_total),
         {:ok, transaction_id} <- authorize(gateway, amount, payment_details, opts),
         {:ok, capture_details} <- capture(gateway, transaction_id, amount, opts) do
      {:ok,
       %CheckoutSession{
         id: stable_id("pay", response.cart_id, request.idempotency_key),
         kind: request.payment_flow,
         status: capture_details[:status] || capture_details["status"] || "paid",
         provider: inspect(gateway),
         currency: response.currency,
         totals: response.price_breakdown,
         redirect_url: nil,
         payment_client_secret: nil,
         provider_reference: transaction_id,
         expires_at: nil,
         idempotency_key: request.idempotency_key,
         retry_safe: not is_nil(request.idempotency_key),
         metadata: request.metadata
       }}
    else
      nil ->
        {:error,
         %ValidationError{
           code: :payment_details_required,
           message: "payment_details are required to create a payment session"
         }}

      {:error, reason} ->
        {:error,
         %ProviderError{
           provider: inspect(__MODULE__),
           code: :payment_session_failed,
           message: "payment provider failed",
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp authorize(gateway, amount, payment_details, opts) do
    case gateway.authorize(amount, payment_details, opts) do
      {:ok, transaction_id} -> {:ok, transaction_id}
      {:error, reason} -> {:error, {:authorize_failed, reason}}
    end
  end

  defp capture(gateway, transaction_id, amount, opts) do
    case gateway.capture(transaction_id, amount, opts) do
      {:ok, details} -> {:ok, details}
      {:error, reason} -> {:error, {:capture_failed, reason}}
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
