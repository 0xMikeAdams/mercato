defmodule Mercato.PaymentGateways.Dummy do
  @moduledoc """
  Dummy payment gateway implementation for testing and development.

  This implementation provides a simple mock payment gateway that always
  succeeds for testing purposes. It should not be used in production
  environments.

  ## Configuration

      config :mercato, :payment_gateway, Mercato.PaymentGateways.Dummy

  ## Behavior

  - All authorize operations succeed and return a mock transaction ID
  - All capture operations succeed with mock response data
  - All refund operations succeed with mock response data
  - Transaction IDs follow the pattern "dummy_txn_<timestamp>_<random>"
  """

  @behaviour Mercato.Behaviours.PaymentGateway

  @impl true
  def authorize(_amount, _payment_details, _opts) do
    transaction_id = generate_transaction_id()
    {:ok, transaction_id}
  end

  @impl true
  def capture(transaction_id, amount, _opts) do
    if valid_transaction_id?(transaction_id) do
      {:ok,
       %{
         status: "succeeded",
         amount: amount,
         currency: "USD",
         transaction_id: transaction_id,
         created_at: DateTime.utc_now()
       }}
    else
      {:error, :transaction_not_found}
    end
  end

  @impl true
  def refund(transaction_id, amount, opts) do
    if valid_transaction_id?(transaction_id) do
      refund_id = generate_refund_id()

      {:ok,
       %{
         status: "succeeded",
         amount: amount,
         currency: "USD",
         refund_id: refund_id,
         transaction_id: transaction_id,
         reason: Keyword.get(opts, :reason, "requested_by_customer"),
         created_at: DateTime.utc_now()
       }}
    else
      {:error, :transaction_not_found}
    end
  end

  # Private helper functions

  defp generate_transaction_id do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(999_999)
    "dummy_txn_#{timestamp}_#{random}"
  end

  defp generate_refund_id do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(999_999)
    "dummy_ref_#{timestamp}_#{random}"
  end

  defp valid_transaction_id?(transaction_id) do
    String.starts_with?(transaction_id, "dummy_txn_")
  end
end
