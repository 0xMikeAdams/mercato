defmodule Mercato.Controllers.CustomerController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json], namespace: false
  import Mercato.Controllers.Helpers

  alias Mercato.Customers

  def show_profile(conn, _params) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, customer} <- Customers.get_customer(user_id, preload: [:addresses]) do
      render_data(conn, customer)
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end

  def update_profile(conn, %{"customer" => attrs}), do: update_profile(conn, attrs)

  def update_profile(conn, attrs) when is_map(attrs) do
    with {:ok, user_id} <- current_user_id(conn) do
      case Customers.get_customer(user_id, preload: [:addresses]) do
        {:ok, customer} ->
          case Customers.update_customer(customer, put_attr(attrs, :user_id, user_id)) do
            {:ok, updated_customer} ->
              render_data(conn, updated_customer)

            {:error, %Ecto.Changeset{} = changeset} ->
              render_error(conn, :unprocessable_entity, "validation_error", %{
                details: changeset_errors(changeset)
              })
          end

        {:error, :not_found} ->
          case Customers.create_customer(put_attr(attrs, :user_id, user_id)) do
            {:ok, customer} ->
              render_data(conn, customer, :created)

            {:error, %Ecto.Changeset{} = changeset} ->
              render_error(conn, :unprocessable_entity, "validation_error", %{
                details: changeset_errors(changeset)
              })
          end
      end
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
    end
  end

  def list_addresses(conn, _params) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, customer} <- Customers.get_customer(user_id) do
      render_data(conn, Customers.list_addresses(customer.id))
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
      {:error, :not_found} -> render_error(conn, :not_found, "not_found")
    end
  end

  def create_address(conn, %{"address" => attrs}), do: create_address(conn, attrs)

  def create_address(conn, attrs) when is_map(attrs) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, customer} <- Customers.get_customer(user_id),
         {:ok, address} <- Customers.add_address(customer.id, attrs) do
      render_data(conn, address, :created)
    else
      {:error, :unauthorized} ->
        render_error(conn, :unauthorized, "unauthorized")

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{
          details: changeset_errors(changeset)
        })
    end
  end

  def update_address(conn, %{"id" => id, "address" => attrs}),
    do: update_address(conn, %{"id" => id} |> Map.merge(attrs))

  def update_address(conn, %{"id" => id} = attrs) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, customer} <- Customers.get_customer(user_id),
         {:ok, address} <- fetch_customer_address(id, customer.id),
         {:ok, updated_address} <- Customers.update_address(address, Map.delete(attrs, "id")) do
      render_data(conn, updated_address)
    else
      {:error, :unauthorized} ->
        render_error(conn, :unauthorized, "unauthorized")

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{
          details: changeset_errors(changeset)
        })
    end
  end

  def delete_address(conn, %{"id" => id}) do
    with {:ok, user_id} <- current_user_id(conn),
         {:ok, customer} <- Customers.get_customer(user_id),
         {:ok, address} <- fetch_customer_address(id, customer.id),
         {:ok, _address} <- Customers.delete_address(address) do
      Plug.Conn.send_resp(conn, :no_content, "")
    else
      {:error, :unauthorized} ->
        render_error(conn, :unauthorized, "unauthorized")

      {:error, :not_found} ->
        render_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = changeset} ->
        render_error(conn, :unprocessable_entity, "validation_error", %{
          details: changeset_errors(changeset)
        })
    end
  end

  def order_history(conn, _params) do
    with {:ok, user_id} <- current_user_id(conn) do
      render_data(conn, Customers.get_order_history_by_user_id(user_id))
    else
      {:error, :unauthorized} -> render_error(conn, :unauthorized, "unauthorized")
    end
  end

  defp fetch_customer_address(address_id, customer_id) do
    case Customers.get_address(address_id) do
      {:ok, %{customer_id: ^customer_id} = address} -> {:ok, address}
      {:ok, _address} -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp put_attr(attrs, key, value) when is_map(attrs) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, Atom.to_string(key), value)
    else
      Map.put(attrs, key, value)
    end
  end
end
