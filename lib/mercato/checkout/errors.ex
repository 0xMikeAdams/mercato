defmodule Mercato.Checkout.Error do
  @moduledoc """
  Base exception for programmatic checkout failures.
  """

  defexception [:code, :message, details: %{}, retryable: false]

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          details: map(),
          retryable: boolean()
        }
end

defmodule Mercato.Checkout.ValidationError do
  @moduledoc """
  Raised when checkout input fails validation.
  """

  defexception [:message, code: :validation_failed, details: %{}, retryable: false]
end

defmodule Mercato.Checkout.ProviderError do
  @moduledoc """
  Raised when a checkout, pricing, or payment provider cannot complete a request.
  """

  defexception [:message, :provider, code: :provider_error, details: %{}, retryable: true]
end

defmodule Mercato.Checkout.IdempotencyError do
  @moduledoc """
  Raised when an idempotent checkout operation is requested incorrectly.
  """

  defexception [:message, code: :idempotency_error, details: %{}, retryable: true]
end
