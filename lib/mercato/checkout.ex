defmodule Mercato.Checkout do
  @moduledoc """
  Programmatic, agent-ready cart-to-checkout orchestration.

  This API keeps cart state, deterministic pricing, checkout-session creation,
  and payment orchestration separate while reusing Mercato's existing cart,
  order, shipping, tax, and payment primitives.

  ## Authorization

  Every function that operates on an *existing* cart is **fail-closed**: the caller must
  prove it is allowed to act on the cart by passing a `:scope` in `opts`. The host is
  responsible for authenticating the request and deriving the scope — never take the
  identity from untrusted request data.

      # Guest cart — prove possession of the cart's high-entropy token:
      Checkout.update_cart_lines(cart_id, ops, scope: [cart_token: token])

      # Cart owned by an authenticated user — the actor id must match the cart's user_id:
      Checkout.price_checkout(cart_id, request, scope: [actor_id: current_user_id])

  A missing or mismatched scope, or an unknown `cart_id`, returns
  `{:error, %Mercato.Checkout.AuthorizationError{code: :forbidden}}` (map it to HTTP 403).
  The error never distinguishes "forbidden" from "not found", so the endpoints can't be
  used to enumerate cart ids. `create_cart/2` needs no scope — it mints a new cart.
  """

  import Ecto.Query, warn: false

  alias Decimal, as: D
  alias Mercato
  alias Mercato.Cart
  alias Mercato.Cart.Calculator
  alias Mercato.Cart.Cart, as: CartRecord
  alias Mercato.Cart.CartItem
  alias Mercato.Catalog
  alias Mercato.Config
  alias Mercato.Events

  alias Mercato.Checkout.{
    Address,
    AuthorizationError,
    BuyerIdentity,
    CheckoutLineItem,
    CheckoutPriceBreakdown,
    IdempotencyError,
    ProgrammaticCheckoutRequest,
    ProgrammaticCheckoutResponse,
    ProviderError,
    ValidationError
  }

  alias Mercato.Checkout.Providers.{
    DefaultCheckoutProvider,
    DefaultPaymentProvider,
    DefaultPricingProvider
  }

  # Preloads for the intermediate cart reloads between batch line operations. The product
  # and variant associations aren't needed to apply the next operation or to recalculate
  # totals, so we skip those joins here and only force the full `items: [:product, :variant]`
  # preload once on the final result. `:applied_coupon` is loaded so the calculator reuses it
  # instead of re-fetching the coupon on every recalculation.
  @line_op_preloads [:items, :applied_coupon]

  @type line_operation :: %{
          required(:action) => String.t() | atom(),
          optional(:item_id) => String.t(),
          optional(:product_id) => String.t(),
          optional(:variant_id) => String.t(),
          optional(:quantity) => pos_integer()
        }

  def create_cart(attrs \\ %{}, opts \\ []) do
    attrs = ensure_cart_token(attrs)

    with {:ok, create_attrs, checkout_attrs} <- normalize_cart_creation(attrs),
         {:ok, cart} <- Cart.create_cart(create_attrs),
         {:ok, cart} <- maybe_update_checkout_context(cart.id, checkout_attrs),
         {:ok, quoted_cart} <- ensure_priced(cart, %ProgrammaticCheckoutRequest{}, opts) do
      {:ok, build_response(quoted_cart, "cart_created", %ProgrammaticCheckoutRequest{}, nil)}
    end
  end

  def update_cart_lines(cart_id, operations, opts \\ []) when is_list(operations) do
    with :ok <- authorize_cart_access(cart_id, opts),
         :ok <- validate_line_operations(operations),
         {:ok, updated_cart} <-
           repo().transaction(fn ->
             case apply_line_operations(cart_id, operations) do
               {:ok, updated_cart} -> updated_cart
               {:error, error} -> repo().rollback(error)
             end
           end) do
      Events.broadcast_cart_updated(updated_cart)
      {:ok, build_response(updated_cart, "cart_updated", %ProgrammaticCheckoutRequest{}, nil)}
    else
      {:error, %ValidationError{} = error} ->
        {:error, error}

      {:error, %ProviderError{} = error} ->
        {:error, error}

      {:error, error} ->
        normalize_error(error)
    end
  end

  def set_buyer_identity(cart_id, attrs, opts \\ []) do
    with :ok <- authorize_cart_access(cart_id, opts),
         {:ok, buyer_identity} <- BuyerIdentity.new(attrs),
         {:ok, cart} <-
           Cart.update_checkout_context(cart_id, %{
             buyer_identity: BuyerIdentity.to_map(buyer_identity)
           }) do
      {:ok, build_response(cart, "buyer_identity_set", %ProgrammaticCheckoutRequest{}, nil)}
    else
      {:error, error} -> normalize_error(error)
    end
  end

  def set_shipping_address(cart_id, attrs, opts \\ []) do
    shipping_method = Keyword.get(opts, :shipping_method)

    with :ok <- authorize_cart_access(cart_id, opts),
         {:ok, address} <- Address.new(attrs),
         {:ok, cart} <-
           Cart.update_checkout_context(
             cart_id,
             %{
               shipping_address: Address.to_map(address),
               shipping_method: shipping_method
             }
             |> Enum.reject(fn {_key, value} -> is_nil(value) end)
             |> Map.new()
           ) do
      {:ok, build_response(cart, "shipping_address_set", %ProgrammaticCheckoutRequest{}, nil)}
    else
      {:error, error} -> normalize_error(error)
    end
  end

  def quote_checkout(cart_id, request \\ %{}, opts \\ []),
    do: price_checkout(cart_id, request, opts)

  def price_checkout(cart_id, request \\ %{}, opts \\ []) do
    with :ok <- authorize_cart_access(cart_id, opts),
         {:ok, request} <- ProgrammaticCheckoutRequest.new(request),
         {:ok, cart} <- apply_checkout_request(cart_id, request),
         :ok <- validate_ready_for_pricing(cart),
         {:ok, priced_cart} <- ensure_priced(cart, request, opts) do
      {:ok, build_response(priced_cart, "priced", request, nil)}
    else
      {:error, error} -> normalize_error(error)
    end
  end

  def create_checkout_session(cart_id, request \\ %{}, opts \\ []) do
    with :ok <- authorize_cart_access(cart_id, opts),
         {:ok, request} <- ProgrammaticCheckoutRequest.new(request),
         :ok <- validate_ready_for_checkout(request),
         {:ok, response} <- price_checkout(cart_id, request, opts),
         provider <- checkout_provider(opts),
         {:ok, session} <- provider.create_checkout_session(request, response, opts) do
      {:ok,
       %{
         response
         | status: "checkout_session_created",
           checkout_session: session,
           retry_safe: session.retry_safe
       }}
    else
      {:error, error} -> normalize_error(error)
    end
  end

  def create_payment_session(cart_id, request \\ %{}, opts \\ []) do
    with :ok <- authorize_cart_access(cart_id, opts),
         {:ok, request} <- ProgrammaticCheckoutRequest.new(request),
         :ok <- validate_ready_for_checkout(request),
         {:ok, response} <- price_checkout(cart_id, request, opts),
         provider <- payment_provider(opts),
         {:ok, session} <- provider.create_payment_session(request, response, opts) do
      {:ok,
       %{
         response
         | status: "payment_session_created",
           checkout_session: session,
           retry_safe: session.retry_safe
       }}
    else
      {:error, error} -> normalize_error(error)
    end
  end

  def create_payment_intent(cart_id, request \\ %{}, opts \\ []) do
    with :ok <- authorize_cart_access(cart_id, opts) do
      request =
        case request do
          nil -> %{payment_flow: "payment_intent"}
          %{} = map -> Map.put(Map.new(map), :payment_flow, "payment_intent")
        end

      create_payment_session(cart_id, request, opts)
    else
      {:error, error} -> normalize_error(error)
    end
  end

  defp normalize_cart_creation(attrs) when is_map(attrs) do
    with {:ok, buyer_identity} <-
           BuyerIdentity.new(Map.get(attrs, :buyer_identity) || Map.get(attrs, "buyer_identity")),
         {:ok, shipping_address} <-
           Address.new(Map.get(attrs, :shipping_address) || Map.get(attrs, "shipping_address")) do
      create_attrs =
        attrs
        |> Map.drop([
          :buyer_identity,
          "buyer_identity",
          :shipping_address,
          "shipping_address",
          :shipping_method,
          "shipping_method"
        ])

      checkout_attrs =
        %{}
        |> maybe_put(:buyer_identity, BuyerIdentity.to_map(buyer_identity))
        |> maybe_put(:shipping_address, Address.to_map(shipping_address))
        |> maybe_put(
          :shipping_method,
          Map.get(attrs, :shipping_method) || Map.get(attrs, "shipping_method")
        )

      {:ok, create_attrs, checkout_attrs}
    else
      {:error, error} -> normalize_error(error)
    end
  end

  defp maybe_update_checkout_context(cart_id, attrs) when map_size(attrs) == 0,
    do: Cart.get_cart(cart_id)

  defp maybe_update_checkout_context(cart_id, attrs),
    do: Cart.update_checkout_context(cart_id, attrs)

  defp apply_checkout_request(cart_id, %ProgrammaticCheckoutRequest{} = request) do
    context_attrs =
      %{}
      |> maybe_put(:buyer_identity, BuyerIdentity.to_map(request.buyer_identity))
      |> maybe_put(:shipping_address, Address.to_map(request.shipping_address))
      |> maybe_put(:shipping_method, request.shipping_method)

    maybe_update_checkout_context(cart_id, context_attrs)
  end

  defp ensure_priced(cart, request, opts) do
    provider = pricing_provider(opts)

    with {:ok, totals} <- provider.price_cart(cart, request, opts),
         {:ok, updated_cart} <- persist_totals(cart, totals) do
      {:ok, updated_cart}
    else
      {:error, reason} ->
        {:error,
         %ProviderError{
           provider: inspect(provider),
           code: :pricing_failed,
           message: "pricing provider failed",
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp persist_totals(cart, totals) do
    cart
    |> CartRecord.totals_changeset(totals)
    |> repo().update()
    |> case do
      {:ok, updated_cart} ->
        {:ok, repo().preload(updated_cart, [items: [:product, :variant]], force: true)}

      {:error, changeset} ->
        {:error,
         %ValidationError{
           code: :invalid_totals,
           message: "invalid calculated totals",
           details: traverse_errors(changeset)
         }}
    end
  end

  defp validate_line_operations([]) do
    {:error,
     %ValidationError{
       code: :line_operations_required,
       message: "at least one line operation is required"
     }}
  end

  defp validate_line_operations(operations) do
    Enum.reduce_while(operations, :ok, fn operation, :ok ->
      case validate_line_operation(operation) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp validate_line_operation(operation) when is_map(operation) do
    action =
      Map.get(operation, :action) || Map.get(operation, "action")

    normalized_action =
      action
      |> to_string()
      |> String.downcase()

    quantity = Map.get(operation, :quantity) || Map.get(operation, "quantity")
    product_id = Map.get(operation, :product_id) || Map.get(operation, "product_id")
    item_id = Map.get(operation, :item_id) || Map.get(operation, "item_id")

    cond do
      normalized_action not in ~w(add set update remove) ->
        {:error,
         %ValidationError{
           code: :invalid_line_action,
           message: "line action must be one of add, set, update, remove",
           details: %{action: action}
         }}

      normalized_action in ~w(add) and is_nil(product_id) ->
        {:error,
         %ValidationError{
           code: :product_id_required,
           message: "product_id is required for add operations"
         }}

      normalized_action in ~w(set update remove) and is_nil(item_id) and is_nil(product_id) ->
        {:error,
         %ValidationError{
           code: :line_reference_required,
           message: "item_id or product_id is required for update/remove operations"
         }}

      normalized_action in ~w(add set update) and (not is_integer(quantity) or quantity <= 0) ->
        {:error,
         %ValidationError{
           code: :invalid_quantity,
           message: "quantity must be a positive integer",
           details: %{quantity: quantity}
         }}

      true ->
        :ok
    end
  end

  defp validate_line_operation(_operation) do
    {:error,
     %ValidationError{code: :invalid_line_operation, message: "line operations must be maps"}}
  end

  defp apply_line_operations(cart_id, operations) do
    with {:ok, cart} <- fetch_cart_for_repo(repo(), cart_id),
         :ok <- validate_ready_for_line_mutation(cart) do
      final_cart =
        Enum.reduce_while(operations, {:ok, cart}, fn operation, {:ok, current_cart} ->
          case apply_line_operation(repo(), current_cart, operation) do
            {:ok, updated_cart} -> {:cont, {:ok, updated_cart}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      with {:ok, updated_cart} <- final_cart do
        totals = Calculator.recalculate_totals(updated_cart, pricing_opts_for_cart(updated_cart))

        updated_cart
        |> CartRecord.totals_changeset(totals)
        |> repo().update()
        |> case do
          {:ok, persisted_cart} ->
            {:ok, repo().preload(persisted_cart, [items: [:product, :variant]], force: true)}

          {:error, changeset} ->
            {:error,
             %ValidationError{
               code: :invalid_totals,
               message: "invalid calculated totals",
               details: traverse_errors(changeset)
             }}
        end
      end
    end
  end

  defp validate_ready_for_line_mutation(cart), do: validate_active_cart(cart)

  defp apply_line_operation(repo, cart, operation) do
    action =
      operation
      |> Map.get(:action, Map.get(operation, "action"))
      |> to_string()
      |> String.downcase()

    case action do
      "add" -> add_line(repo, cart, operation)
      "set" -> set_line_quantity(repo, cart, operation)
      "update" -> set_line_quantity(repo, cart, operation)
      "remove" -> remove_line(repo, cart, operation)
    end
  end

  defp add_line(repo, cart, operation) do
    product_id = Map.get(operation, :product_id) || Map.get(operation, "product_id")
    variant_id = Map.get(operation, :variant_id) || Map.get(operation, "variant_id")
    quantity = Map.get(operation, :quantity) || Map.get(operation, "quantity")

    with {:ok, product} <- fetch_product(product_id),
         {:ok, unit_price} <- get_item_price(product, variant_id) do
      case find_cart_item(cart, operation) do
        nil ->
          %CartItem{}
          |> CartItem.changeset(%{
            cart_id: cart.id,
            product_id: product_id,
            variant_id: variant_id,
            quantity: quantity,
            unit_price: unit_price
          })
          |> repo.insert()
          |> reload_cart(cart.id)

        item ->
          item
          |> CartItem.changeset(%{quantity: item.quantity + quantity})
          |> repo.update()
          |> reload_cart(cart.id)
      end
    end
  end

  defp set_line_quantity(repo, cart, operation) do
    quantity = Map.get(operation, :quantity) || Map.get(operation, "quantity")

    with {:ok, item} <- fetch_line_item(cart, operation) do
      item
      |> CartItem.changeset(%{quantity: quantity})
      |> repo.update()
      |> reload_cart(cart.id)
    end
  end

  defp remove_line(repo, cart, operation) do
    with {:ok, item} <- fetch_line_item(cart, operation),
         {:ok, _item} <- repo.delete(item) do
      fetch_cart_for_repo(repo, cart.id, @line_op_preloads)
    end
  end

  defp reload_cart({:ok, _result}, cart_id),
    do: fetch_cart_for_repo(repo(), cart_id, @line_op_preloads)

  defp reload_cart({:error, changeset}, _cart_id),
    do:
      {:error,
       %ValidationError{message: "invalid cart line", details: traverse_errors(changeset)}}

  defp fetch_line_item(cart, operation) do
    case find_cart_item(cart, operation) do
      nil ->
        {:error,
         %ValidationError{
           code: :line_item_not_found,
           message: "referenced line item was not found"
         }}

      item ->
        {:ok, item}
    end
  end

  defp find_cart_item(cart, operation) do
    item_id = Map.get(operation, :item_id) || Map.get(operation, "item_id")
    product_id = Map.get(operation, :product_id) || Map.get(operation, "product_id")
    variant_id = Map.get(operation, :variant_id) || Map.get(operation, "variant_id")

    Enum.find(cart.items, fn item ->
      cond do
        is_binary(item_id) ->
          item.id == item_id

        is_binary(product_id) ->
          item.product_id == product_id and item.variant_id == variant_id

        true ->
          false
      end
    end)
  end

  defp validate_ready_for_pricing(cart) do
    cond do
      cart.status != "active" ->
        inactive_cart_error()

      Enum.empty?(cart.items) ->
        {:error,
         %ValidationError{code: :empty_cart, message: "cart must contain at least one line item"}}

      shipping_required?(cart) and is_nil(cart.shipping_address) ->
        {:error,
         %ValidationError{
           code: :shipping_address_required,
           message: "shipping_address is required to price this cart"
         }}

      true ->
        :ok
    end
  end

  defp validate_active_cart(%CartRecord{status: "active"}), do: :ok
  defp validate_active_cart(%CartRecord{}), do: inactive_cart_error()

  defp inactive_cart_error do
    {:error,
     %ValidationError{
       code: :inactive_cart,
       message: "cart is no longer active"
     }}
  end

  defp validate_ready_for_checkout(request) do
    if is_nil(request.idempotency_key) do
      {:error,
       %IdempotencyError{
         message: "idempotency_key is required for checkout and payment session creation",
         details: %{field: :idempotency_key}
       }}
    else
      :ok
    end
  end

  defp build_response(cart, status, request, session) do
    currency = request.currency || default_currency()

    %ProgrammaticCheckoutResponse{
      status: status,
      cart_id: cart.id,
      cart_token: cart.cart_token,
      cart_status: cart.status,
      currency: currency,
      idempotency_key: request.idempotency_key,
      buyer_identity: to_buyer_identity(cart.buyer_identity),
      shipping_address: to_address(cart.shipping_address),
      shipping_method: cart.shipping_method,
      line_items: Enum.map(cart.items, &CheckoutLineItem.from_cart_item(&1, currency)),
      price_breakdown:
        CheckoutPriceBreakdown.from_totals(
          %{
            subtotal: cart.subtotal || D.new("0.00"),
            discount_total: cart.discount_total || D.new("0.00"),
            shipping_total: cart.shipping_total || D.new("0.00"),
            tax_total: cart.tax_total || D.new("0.00"),
            duties_total: cart.duties_total || D.new("0.00"),
            grand_total: cart.grand_total || D.new("0.00")
          },
          currency
        ),
      checkout_session: session,
      retry_safe: not is_nil(request.idempotency_key)
    }
  end

  defp to_buyer_identity(nil), do: nil

  defp to_buyer_identity(value) do
    case BuyerIdentity.new(value) do
      {:ok, identity} -> identity
      {:error, _reason} -> nil
    end
  end

  defp to_address(nil), do: nil

  defp to_address(value) do
    case Address.new(value) do
      {:ok, address} -> address
      {:error, _reason} -> nil
    end
  end

  defp fetch_product(product_id) do
    case Catalog.get_product(product_id) do
      {:ok, product} ->
        {:ok, product}

      {:error, :not_found} ->
        {:error,
         %ValidationError{
           code: :product_not_found,
           message: "product was not found",
           details: %{product_id: product_id}
         }}
    end
  end

  defp get_item_price(product, nil), do: {:ok, product.price}

  defp get_item_price(product, variant_id) do
    product_id = product.id

    case Catalog.get_variant(variant_id) do
      {:ok, %{product_id: ^product_id} = variant} ->
        {:ok, variant.price}

      {:ok, _variant} ->
        {:error,
         %ValidationError{
           code: :variant_product_mismatch,
           message: "variant does not belong to product"
         }}

      {:error, :not_found} ->
        {:error,
         %ValidationError{
           code: :variant_not_found,
           message: "variant was not found",
           details: %{variant_id: variant_id}
         }}
    end
  end

  # Fail-closed ownership gate for every entry point that operates on an existing cart.
  # The caller must prove it may act on the cart via a `:scope` in opts:
  #
  #   * `scope: [actor_id: user_id]` — for a cart owned by an authenticated user; the id
  #     must equal the cart's `user_id`.
  #   * `scope: [cart_token: token]` — for a guest cart (`user_id == nil`); the token must
  #     equal the cart's high-entropy `cart_token` (proof of possession).
  #
  # Anything else — no scope, wrong scope, or a cart_id that does not exist — returns
  # `%AuthorizationError{}`. We never distinguish "not found" from "forbidden", so the
  # endpoint can't be used as an oracle to enumerate cart ids. `scope` accepts a keyword
  # list or a map with atom keys.
  defp authorize_cart_access(cart_id, opts) do
    scope = Keyword.get(opts, :scope, [])

    case repo().get(CartRecord, cart_id) do
      %CartRecord{user_id: owner_id} when not is_nil(owner_id) ->
        if not is_nil(scope_value(scope, :actor_id)) and scope_value(scope, :actor_id) == owner_id,
          do: :ok,
          else: forbidden_cart_access()

      %CartRecord{user_id: nil, cart_token: token} when is_binary(token) ->
        if secure_token_match?(scope_value(scope, :cart_token), token),
          do: :ok,
          else: forbidden_cart_access()

      _ ->
        forbidden_cart_access()
    end
  end

  defp forbidden_cart_access do
    {:error, %AuthorizationError{message: "not authorized to access this cart", details: %{}}}
  end

  defp scope_value(scope, key) when is_list(scope), do: Keyword.get(scope, key)
  defp scope_value(scope, key) when is_map(scope), do: Map.get(scope, key)
  defp scope_value(_scope, _key), do: nil

  # Constant-time comparison so a mismatched guest token can't be recovered by timing.
  defp secure_token_match?(provided, expected)
       when is_binary(provided) and is_binary(expected) and
              byte_size(provided) == byte_size(expected) do
    :crypto.exor(provided, expected) == :binary.copy(<<0>>, byte_size(expected))
  end

  defp secure_token_match?(_provided, _expected), do: false

  defp fetch_cart_for_repo(repo, cart_id, preloads \\ [items: [:product, :variant]]) do
    case repo.get(CartRecord, cart_id) do
      nil ->
        {:error,
         %ValidationError{
           code: :cart_not_found,
           message: "cart was not found",
           details: %{cart_id: cart_id}
         }}

      cart ->
        {:ok, repo.preload(cart, preloads)}
    end
  end

  defp pricing_opts_for_cart(cart) do
    []
    |> maybe_put_keyword(
      :destination,
      Address.to_customer_address(to_address(cart.shipping_address))
    )
    |> maybe_put_keyword(:method, cart.shipping_method)
    |> maybe_put_keyword(:duties_total, D.new("0.00"))
  end

  defp shipping_required?(cart) do
    Enum.any?(cart.items, fn item ->
      product_type = item.product && item.product.product_type
      product_type not in ["downloadable", "virtual"]
    end)
  end

  defp ensure_cart_token(attrs) when is_map(attrs) do
    if Map.get(attrs, :cart_token) || Map.get(attrs, "cart_token") do
      attrs
    else
      Map.put(attrs, :cart_token, generate_cart_token())
    end
  end

  defp generate_cart_token do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_keyword(opts, _key, nil), do: opts
  defp maybe_put_keyword(opts, key, value), do: Keyword.put(opts, key, value)

  defp default_currency do
    Config.get_setting(:currency) || "USD"
  end

  defp traverse_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  defp pricing_provider(opts), do: Keyword.get(opts, :pricing_provider, DefaultPricingProvider)

  defp checkout_provider(opts),
    do:
      Keyword.get(
        opts,
        :checkout_provider,
        Application.get_env(:mercato, :checkout_provider, DefaultCheckoutProvider)
      )

  defp payment_provider(opts),
    do:
      Keyword.get(
        opts,
        :payment_provider,
        Application.get_env(:mercato, :payment_provider, DefaultPaymentProvider)
      )

  defp repo, do: Mercato.repo()

  defp normalize_error(%AuthorizationError{} = error), do: {:error, error}
  defp normalize_error(%ValidationError{} = error), do: {:error, error}
  defp normalize_error(%ProviderError{} = error), do: {:error, error}
  defp normalize_error(%IdempotencyError{} = error), do: {:error, error}

  defp normalize_error(%Ecto.Changeset{} = changeset),
    do:
      {:error,
       %ValidationError{message: "validation failed", details: traverse_errors(changeset)}}

  defp normalize_error({:error, reason}), do: normalize_error(reason)

  defp normalize_error(reason) when is_atom(reason) do
    {:error, %ValidationError{code: reason, message: Atom.to_string(reason)}}
  end

  defp normalize_error(reason) do
    {:error,
     %Mercato.Checkout.Error{
       code: :checkout_failed,
       message: "programmatic checkout failed",
       details: %{reason: inspect(reason)}
     }}
  end
end
