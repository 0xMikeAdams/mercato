defmodule Mercato.Checkout.Money do
  @moduledoc """
  Stable machine-readable money value used by programmatic checkout responses.
  """

  alias Decimal, as: D

  @enforce_keys [:amount, :currency_code]
  defstruct [:amount, :currency_code]

  @type t :: %__MODULE__{
          amount: String.t(),
          currency_code: String.t()
        }

  def new(%D{} = amount, currency_code) when is_binary(currency_code) do
    normalized_amount = D.round(amount, 2)

    %__MODULE__{
      amount: D.to_string(normalized_amount, :normal),
      currency_code: String.upcase(currency_code)
    }
  end

  def to_decimal(%__MODULE__{amount: amount}), do: D.new(amount)
end
