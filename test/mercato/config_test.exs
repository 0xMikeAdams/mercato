defmodule Mercato.ConfigTest do
  use ExUnit.Case, async: true
  alias Mercato.Config

  setup do
    # Ensure we're using the test database
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mercato.Repo)
  end

  describe "get_setting/1" do
    test "returns default values for known settings" do
      assert Config.get_setting(:currency) == "USD"
      assert Config.get_setting(:locale) == "en"
      assert Config.get_setting(:store_name) == "Mercato Store"
      assert Config.get_setting(:guest_checkout_enabled) == true
      assert Config.get_setting(:coupons_enabled) == true
    end

    test "returns nil for unknown settings" do
      assert Config.get_setting(:unknown_setting) == nil
    end

    test "returns runtime setting when available" do
      :ok = Config.put_setting(:store_name, "Custom Store Name")
      assert Config.get_setting(:store_name) == "Custom Store Name"
    end
  end

  describe "put_setting/2" do
    test "creates new runtime setting" do
      assert :ok = Config.put_setting(:custom_setting, "custom_value")
      assert Config.get_setting(:custom_setting) == "custom_value"
    end

    test "updates existing runtime setting" do
      :ok = Config.put_setting(:store_name, "First Name")
      assert Config.get_setting(:store_name) == "First Name"

      :ok = Config.put_setting(:store_name, "Updated Name")
      assert Config.get_setting(:store_name) == "Updated Name"
    end

    test "supports different value types" do
      :ok = Config.put_setting(:string_setting, "string_value")
      :ok = Config.put_setting(:integer_setting, 42)
      :ok = Config.put_setting(:boolean_setting, false)
      :ok = Config.put_setting(:map_setting, %{"key" => "value"})

      assert Config.get_setting(:string_setting) == "string_value"
      assert Config.get_setting(:integer_setting) == 42
      assert Config.get_setting(:boolean_setting) == false
      assert Config.get_setting(:map_setting) == %{"key" => "value"}
    end
  end

  describe "get_all_settings/0" do
    test "returns map with all default settings" do
      settings = Config.get_all_settings()

      assert is_map(settings)
      assert settings[:currency] == "USD"
      assert settings[:locale] == "en"
      assert settings[:store_name] == "Mercato Store"
      assert settings[:guest_checkout_enabled] == true
    end

    test "includes runtime settings with precedence" do
      :ok = Config.put_setting(:store_name, "Runtime Store Name")
      :ok = Config.put_setting(:custom_setting, "custom_value")

      settings = Config.get_all_settings()

      # Runtime setting should override default
      assert settings[:store_name] == "Runtime Store Name"
      # Custom setting should be included
      assert settings[:custom_setting] == "custom_value"
      # Default settings should still be present
      assert settings[:currency] == "USD"
    end
  end

  describe "delete_setting/1" do
    test "removes runtime setting" do
      :ok = Config.put_setting(:temp_setting, "temp_value")
      assert Config.get_setting(:temp_setting) == "temp_value"

      assert :ok = Config.delete_setting(:temp_setting)
      assert Config.get_setting(:temp_setting) == nil
    end

    test "returns error for non-existent setting" do
      assert {:error, :not_found} = Config.delete_setting(:non_existent)
    end

    test "falls back to default after deletion" do
      # Override default
      :ok = Config.put_setting(:store_name, "Custom Name")
      assert Config.get_setting(:store_name) == "Custom Name"

      # Delete runtime setting
      :ok = Config.delete_setting(:store_name)
      # Should fall back to default
      assert Config.get_setting(:store_name) == "Mercato Store"
    end
  end

  describe "list_runtime_settings/0" do
    test "returns list of runtime settings" do
      :ok = Config.put_setting(:setting1, "value1")
      :ok = Config.put_setting(:setting2, 42)

      settings = Config.list_runtime_settings()

      assert is_list(settings)
      assert length(settings) >= 2

      setting_keys = Enum.map(settings, & &1.key)
      assert "setting1" in setting_keys
      assert "setting2" in setting_keys
    end
  end

  describe "configuration precedence" do
    test "runtime settings override defaults" do
      # Default value
      assert Config.get_setting(:currency) == "USD"

      # Override with runtime setting
      :ok = Config.put_setting(:currency, "EUR")
      assert Config.get_setting(:currency) == "EUR"

      # Delete runtime setting, should fall back to default
      :ok = Config.delete_setting(:currency)
      assert Config.get_setting(:currency) == "USD"
    end
  end
end
