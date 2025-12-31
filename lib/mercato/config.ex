defmodule Mercato.Config do
  @moduledoc """
  The Config context provides functions for managing store configuration settings.

  This context handles all configuration-related operations including:
  - Runtime store settings management
  - Feature flag control
  - Configuration precedence (compile-time vs runtime)
  - Default values for common settings

  ## Configuration Precedence

  Settings are resolved in the following order (highest to lowest priority):
  1. Runtime database settings (via `put_setting/2`)
  2. Application configuration (compile-time config)
  3. Default values (hardcoded fallbacks)

  ## Examples

      # Get a setting with automatic fallback
      store_name = Config.get_setting(:store_name)

      # Set a runtime setting
      :ok = Config.put_setting(:store_name, "My Awesome Store")

      # Get all current settings
      settings = Config.get_all_settings()

      # Check if a feature is enabled
      if Config.get_setting(:guest_checkout_enabled) do
        # Allow guest checkout
      end
  """

  import Ecto.Query, warn: false
  alias Mercato.Repo
  alias Mercato.Config.StoreSetting

  @doc """
  Gets a setting value by key.

  Returns the setting value with the following precedence:
  1. Runtime database setting (highest priority)
  2. Application configuration
  3. Default value (lowest priority)

  Returns `nil` if no value is found at any level.

  ## Examples

      iex> get_setting(:store_name)
      "My Store"

      iex> get_setting(:nonexistent_key)
      nil

      iex> get_setting(:currency)
      "USD"  # from default values
  """
  def get_setting(key) when is_atom(key) do
    key_string = Atom.to_string(key)

    # 1. Check runtime database setting (highest priority)
    case get_runtime_setting(key_string) do
      {:ok, value} -> value
      {:error, :not_found} ->
        # 2. Check application configuration
        case get_app_config(key) do
          {:ok, value} -> value
          {:error, :not_found} ->
            # 3. Check default values (lowest priority)
            get_default_value(key)
        end
    end
  end

  @doc """
  Sets a runtime setting value.

  This creates or updates a setting in the database, which takes precedence
  over application configuration and default values.

  ## Examples

      iex> put_setting(:store_name, "My Awesome Store")
      :ok

      iex> put_setting(:guest_checkout_enabled, true)
      :ok

      iex> put_setting(:tax_rates, %{"US" => "8.5", "CA" => "12.0"})
      :ok
  """
  def put_setting(key, value) when is_atom(key) do
    key_string = Atom.to_string(key)
    value_type = determine_value_type(value)

    # Wrap non-map values in a map for storage
    stored_value = case value_type do
      "map" -> value
      _ -> %{"value" => value}
    end

    attrs = %{
      key: key_string,
      value: stored_value,
      value_type: value_type
    }

    case get_runtime_setting(key_string) do
      {:ok, _existing_value} ->
        # Update existing setting
        setting = Repo.get_by!(StoreSetting, key: key_string)
        setting
        |> StoreSetting.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _setting} -> :ok
          {:error, _changeset} -> {:error, :update_failed}
        end

      {:error, :not_found} ->
        # Create new setting
        %StoreSetting{}
        |> StoreSetting.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, _setting} -> :ok
          {:error, _changeset} -> {:error, :insert_failed}
        end
    end
  end

  @doc """
  Gets all current settings as a map.

  Returns a map containing all settings from all sources (runtime, app config, defaults)
  with runtime settings taking precedence over app config and defaults.

  ## Examples

      iex> get_all_settings()
      %{
        store_name: "My Store",
        currency: "USD",
        guest_checkout_enabled: true,
        tax_rates: %{"US" => "8.5"}
      }
  """
  def get_all_settings do
    # Start with default values
    defaults = get_all_default_values()

    # Merge with app config
    app_config = get_all_app_config()
    merged = Map.merge(defaults, app_config)

    # Merge with runtime settings (highest priority)
    runtime_settings = get_all_runtime_settings()
    Map.merge(merged, runtime_settings)
  end

  @doc """
  Deletes a runtime setting.

  This removes the setting from the database, causing it to fall back to
  application configuration or default values.

  ## Examples

      iex> delete_setting(:store_name)
      :ok

      iex> delete_setting(:nonexistent_key)
      {:error, :not_found}
  """
  def delete_setting(key) when is_atom(key) do
    key_string = Atom.to_string(key)

    case Repo.get_by(StoreSetting, key: key_string) do
      nil -> {:error, :not_found}
      setting ->
        case Repo.delete(setting) do
          {:ok, _setting} -> :ok
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @doc """
  Lists all runtime settings stored in the database.

  Returns a list of `StoreSetting` structs.

  ## Examples

      iex> list_runtime_settings()
      [%StoreSetting{key: "store_name", value: "My Store"}, ...]
  """
  def list_runtime_settings do
    Repo.all(StoreSetting)
  end

  # Private Functions

  defp get_runtime_setting(key_string) do
    case Repo.get_by(StoreSetting, key: key_string) do
      nil -> {:error, :not_found}
      %StoreSetting{value: stored_value, value_type: value_type} ->
        # Unwrap non-map values
        actual_value = case value_type do
          "map" -> stored_value
          _ -> Map.get(stored_value, "value")
        end
        {:ok, actual_value}
    end
  end

  defp get_app_config(key) do
    case Application.get_env(:mercato, key) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  defp get_all_app_config do
    case Application.get_all_env(:mercato) do
      [] -> %{}
      config ->
        config
        |> Enum.filter(fn {key, _value} -> is_atom(key) end)
        |> Enum.into(%{})
    end
  end

  defp get_all_runtime_settings do
    StoreSetting
    |> Repo.all()
    |> Enum.map(fn %StoreSetting{key: key, value: stored_value, value_type: value_type} ->
      # Unwrap non-map values
      actual_value = case value_type do
        "map" -> stored_value
        _ -> Map.get(stored_value, "value")
      end
      {String.to_atom(key), actual_value}
    end)
    |> Enum.into(%{})
  end

  defp determine_value_type(value) when is_binary(value), do: "string"
  defp determine_value_type(value) when is_integer(value), do: "integer"
  defp determine_value_type(value) when is_boolean(value), do: "boolean"
  defp determine_value_type(value) when is_map(value), do: "map"
  defp determine_value_type(_value), do: "string"  # fallback

  # Default values for common store settings
  defp get_default_value(:currency), do: "USD"
  defp get_default_value(:locale), do: "en"
  defp get_default_value(:store_name), do: "Mercato Store"
  defp get_default_value(:guest_checkout_enabled), do: true
  defp get_default_value(:coupons_enabled), do: true
  defp get_default_value(:inventory_tracking_enabled), do: true
  defp get_default_value(:tax_inclusive_prices), do: false
  defp get_default_value(:default_tax_rate), do: "0.0"
  defp get_default_value(:store_address), do: %{
    "line1" => "",
    "line2" => "",
    "city" => "",
    "state" => "",
    "postal_code" => "",
    "country" => "US"
  }
  defp get_default_value(:email_notifications_enabled), do: true
  defp get_default_value(:order_number_prefix), do: "ORD"
  defp get_default_value(:cart_expiry_days), do: 30
  defp get_default_value(:subscription_grace_period_days), do: 3
  defp get_default_value(:referral_commission_rate), do: "5.0"
  defp get_default_value(:referral_commission_type), do: "percentage"
  defp get_default_value(_key), do: nil

  defp get_all_default_values do
    %{
      currency: get_default_value(:currency),
      locale: get_default_value(:locale),
      store_name: get_default_value(:store_name),
      guest_checkout_enabled: get_default_value(:guest_checkout_enabled),
      coupons_enabled: get_default_value(:coupons_enabled),
      inventory_tracking_enabled: get_default_value(:inventory_tracking_enabled),
      tax_inclusive_prices: get_default_value(:tax_inclusive_prices),
      default_tax_rate: get_default_value(:default_tax_rate),
      store_address: get_default_value(:store_address),
      email_notifications_enabled: get_default_value(:email_notifications_enabled),
      order_number_prefix: get_default_value(:order_number_prefix),
      cart_expiry_days: get_default_value(:cart_expiry_days),
      subscription_grace_period_days: get_default_value(:subscription_grace_period_days),
      referral_commission_rate: get_default_value(:referral_commission_rate),
      referral_commission_type: get_default_value(:referral_commission_type)
    }
  end
end
