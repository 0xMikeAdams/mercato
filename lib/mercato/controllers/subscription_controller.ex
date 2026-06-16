defmodule Mercato.Controllers.SubscriptionController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers

  alias Mercato.Subscriptions

  def index(conn, _params) do
    with {:ok, user_id} <- current_user_id(conn) do
      render_data(conn, Subscriptions.list_subscriptions(user_id: user_id))
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, subscription} <- fetch_customer_subscription(id, user_id) do
      render_data(conn, subscription)
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end

  def pause(conn, %{"id" => id}) do
    update_subscription(conn, id, &Subscriptions.pause_subscription/1)
  end

  def resume(conn, %{"id" => id}) do
    update_subscription(conn, id, &Subscriptions.resume_subscription/1)
  end

  def cancel(conn, %{"id" => id}) do
    update_subscription(conn, id, &Subscriptions.cancel_subscription/1)
  end

  defp update_subscription(conn, id, action) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, _subscription} <- fetch_customer_subscription(id, user_id),
         {:ok, subscription} <- action.(id) do
      render_data(conn, subscription)
    else
      {:error, :unauthorized} ->
        render_error(conn, :unauthorized, "unauthorized")

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, reason} ->
        render_error(conn, :unprocessable_entity, "unprocessable_entity", error_detail(reason))
    end
  end

  defp fetch_customer_subscription(subscription_id, user_id) do
    case Subscriptions.get_subscription(subscription_id) do
      {:ok, %{user_id: ^user_id} = subscription} -> {:ok, subscription}
      {:ok, _subscription} -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end
end
