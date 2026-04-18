defmodule Mercato.Checkout.ProgrammaticCheckoutRequest do
  @moduledoc """
  Request envelope for pricing, checkout-session, and payment-session calls.
  """

  alias Mercato.Checkout.{Address, BuyerIdentity, ValidationError}

  @session_kinds ~w(managed redirect)
  @payment_flows ~w(payment_session payment_intent authorization)

  @enforce_keys []
  defstruct [
    :buyer_identity,
    :shipping_address,
    :billing_address,
    :shipping_method,
    :currency,
    :idempotency_key,
    :session_kind,
    :payment_flow,
    :payment_method,
    :redirect_url,
    :payment_details,
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  def new(nil), do: {:ok, %__MODULE__{}}
  def new(%__MODULE__{} = request), do: {:ok, request}

  def new(attrs) when is_map(attrs) do
    with {:ok, buyer_identity} <-
           BuyerIdentity.new(Map.get(attrs, :buyer_identity) || Map.get(attrs, "buyer_identity")),
         {:ok, shipping_address} <-
           Address.new(Map.get(attrs, :shipping_address) || Map.get(attrs, "shipping_address")),
         {:ok, billing_address} <-
           Address.new(Map.get(attrs, :billing_address) || Map.get(attrs, "billing_address")),
         {:ok, session_kind} <-
           normalize_enum(
             Map.get(attrs, :session_kind) || Map.get(attrs, "session_kind"),
             @session_kinds,
             "managed",
             :session_kind
           ),
         {:ok, payment_flow} <-
           normalize_enum(
             Map.get(attrs, :payment_flow) || Map.get(attrs, "payment_flow"),
             @payment_flows,
             "payment_session",
             :payment_flow
           ) do
      {:ok,
       %__MODULE__{
         buyer_identity: buyer_identity,
         shipping_address: shipping_address,
         billing_address: billing_address,
         shipping_method:
           normalize_optional_string(
             Map.get(attrs, :shipping_method) || Map.get(attrs, "shipping_method")
           ),
         currency:
           normalize_optional_string(Map.get(attrs, :currency) || Map.get(attrs, "currency")),
         idempotency_key:
           normalize_optional_string(
             Map.get(attrs, :idempotency_key) || Map.get(attrs, "idempotency_key")
           ),
         session_kind: session_kind,
         payment_flow: payment_flow,
         payment_method:
           normalize_optional_string(
             Map.get(attrs, :payment_method) || Map.get(attrs, "payment_method")
           ),
         redirect_url:
           normalize_optional_string(
             Map.get(attrs, :redirect_url) || Map.get(attrs, "redirect_url")
           ),
         payment_details: Map.get(attrs, :payment_details) || Map.get(attrs, "payment_details"),
         metadata: Map.get(attrs, :metadata) || Map.get(attrs, "metadata") || %{}
       }}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error,
         %ValidationError{
           message: "invalid checkout request",
           details: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
         }}

      {:error, %ValidationError{} = error} ->
        {:error, error}
    end
  end

  defp normalize_enum(nil, _allowed, default, _field), do: {:ok, default}

  defp normalize_enum(value, allowed, _default, field) when is_binary(value) do
    normalized = String.trim(value)

    if normalized in allowed do
      {:ok, normalized}
    else
      {:error,
       %ValidationError{
         message: "invalid #{field}",
         details: %{field => %{allowed: allowed, received: value}}
       }}
    end
  end

  defp normalize_enum(value, _allowed, _default, field) do
    {:error,
     %ValidationError{
       message: "invalid #{field}",
       details: %{field => %{received: value}}
     }}
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value), do: to_string(value)
end
