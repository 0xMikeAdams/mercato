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

defmodule Mercato.Checkout.AuthorizationError do
  @moduledoc """
  Returned when the caller is not authorized to act on the referenced cart.

  Every `Mercato.Checkout` entry point that operates on an existing cart requires the
  caller to prove ownership by passing a `:scope` (see `Mercato.Checkout`): the
  authenticated `:actor_id` must match a user-owned cart's `user_id`, or the supplied
  `:cart_token` must match a guest cart's high-entropy token. A missing or mismatched
  scope — or a cart that does not exist — yields this error. Hosts should map it to
  HTTP 403. The message is intentionally generic so it cannot be used to probe which
  cart ids exist.
  """

  defexception [:message, code: :forbidden, details: %{}, retryable: false]
end
