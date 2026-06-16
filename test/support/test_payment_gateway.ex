defmodule Mercato.TestPaymentGateway do
  @behaviour Mercato.Behaviours.PaymentGateway

  @impl true
  def authorize(amount, payment_details, _opts) do
    notify({:authorize, amount, payment_details})

    case fetch_token(payment_details) do
      "declined" -> {:error, :card_declined}
      _ -> {:ok, "test_txn_123"}
    end
  end

  @impl true
  def capture(transaction_id, amount, _opts) do
    notify({:capture, transaction_id, amount})

    if transaction_id == "capture_fail" do
      {:error, :capture_failed}
    else
      {:ok, %{status: "succeeded", transaction_id: transaction_id, amount: amount}}
    end
  end

  @impl true
  def refund(transaction_id, amount, _opts) do
    notify({:refund, transaction_id, amount})

    if transaction_id == "bad_txn" do
      {:error, :transaction_not_found}
    else
      {:ok,
       %{
         status: "succeeded",
         refund_id: "refund_123",
         transaction_id: transaction_id,
         amount: amount
       }}
    end
  end

  defp fetch_token(%{"token" => token}), do: token
  defp fetch_token(%{token: token}), do: token
  defp fetch_token(_payment_details), do: nil

  defp notify(message) do
    send(self(), {:test_payment_gateway, message})
    :ok
  end
end
