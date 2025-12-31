defmodule Mercato.Behaviours.PaymentGateway do
  @moduledoc """
  Behaviour for implementing payment gateway integrations.

  This behaviour defines the standard interface for payment processing operations
  including authorization, capture, and refund functionality. Implementations
  should handle the specific API calls and response formats for their respective
  payment providers.

  ## Example Implementation

      defmodule MyApp.PaymentGateways.Stripe do
        @behaviour Mercato.Behaviours.PaymentGateway

        @impl true
        def authorize(amount, payment_details, opts) do
          # Stripe-specific authorization logic
          {:ok, "pi_1234567890"}
        end

        @impl true
        def capture(transaction_id, amount, opts) do
          # Stripe-specific capture logic
          {:ok, %{status: "succeeded", amount: amount}}
        end

        @impl true
        def refund(transaction_id, amount, opts) do
          # Stripe-specific refund logic
          {:ok, %{status: "succeeded", refund_id: "re_1234567890"}}
        end
      end

  ## Configuration

  Configure your payment gateway in your application config:

      config :mercato, :payment_gateway, MyApp.PaymentGateways.Stripe
  """

  @doc """
  Authorizes a payment for the given amount.

  This operation typically reserves the funds on the customer's payment method
  but does not immediately charge them. The funds are held until captured or
  the authorization expires.

  ## Parameters

    * `amount` - The amount to authorize as a Decimal
    * `payment_details` - Map containing payment information such as:
      * `:token` - Payment method token from frontend
      * `:customer_id` - Customer identifier for stored payment methods
      * `:billing_address` - Billing address information
      * `:metadata` - Additional payment metadata
    * `opts` - Additional options such as:
      * `:currency` - Currency code (defaults to store currency)
      * `:description` - Payment description
      * `:metadata` - Additional metadata for the transaction

  ## Returns

    * `{:ok, transaction_id}` - Authorization successful, returns transaction ID
    * `{:error, reason}` - Authorization failed with error reason

  ## Examples

      iex> authorize(Decimal.new("29.99"), %{token: "tok_123"}, currency: "USD")
      {:ok, "pi_1234567890"}

      iex> authorize(Decimal.new("29.99"), %{token: "invalid"}, [])
      {:error, :invalid_payment_method}
  """
  @callback authorize(
              amount :: Decimal.t(),
              payment_details :: map(),
              opts :: keyword()
            ) :: {:ok, transaction_id :: binary()} | {:error, reason :: term()}

  @doc """
  Captures a previously authorized payment.

  This operation completes the payment by charging the customer the specified
  amount. The amount can be less than or equal to the authorized amount but
  cannot exceed it.

  ## Parameters

    * `transaction_id` - The transaction ID returned from authorize/3
    * `amount` - The amount to capture as a Decimal
    * `opts` - Additional options such as:
      * `:description` - Capture description
      * `:metadata` - Additional metadata for the capture

  ## Returns

    * `{:ok, capture_details}` - Capture successful with details map
    * `{:error, reason}` - Capture failed with error reason

  The `capture_details` map typically contains:
    * `:status` - Capture status (e.g., "succeeded")
    * `:amount` - Captured amount
    * `:currency` - Currency code
    * `:created_at` - Capture timestamp

  ## Examples

      iex> capture("pi_1234567890", Decimal.new("29.99"), [])
      {:ok, %{status: "succeeded", amount: Decimal.new("29.99")}}

      iex> capture("invalid_id", Decimal.new("29.99"), [])
      {:error, :transaction_not_found}
  """
  @callback capture(
              transaction_id :: binary(),
              amount :: Decimal.t(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, reason :: term()}

  @doc """
  Refunds a captured payment.

  This operation returns funds to the customer's payment method. The refund
  amount can be partial or full but cannot exceed the captured amount.

  ## Parameters

    * `transaction_id` - The transaction ID of the captured payment
    * `amount` - The amount to refund as a Decimal
    * `opts` - Additional options such as:
      * `:reason` - Refund reason
      * `:metadata` - Additional metadata for the refund

  ## Returns

    * `{:ok, refund_details}` - Refund successful with details map
    * `{:error, reason}` - Refund failed with error reason

  The `refund_details` map typically contains:
    * `:status` - Refund status (e.g., "succeeded")
    * `:amount` - Refunded amount
    * `:currency` - Currency code
    * `:refund_id` - Unique refund identifier
    * `:created_at` - Refund timestamp

  ## Examples

      iex> refund("pi_1234567890", Decimal.new("29.99"), reason: "customer_request")
      {:ok, %{status: "succeeded", refund_id: "re_1234567890"}}

      iex> refund("invalid_id", Decimal.new("29.99"), [])
      {:error, :transaction_not_found}
  """
  @callback refund(
              transaction_id :: binary(),
              amount :: Decimal.t(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, reason :: term()}
end
