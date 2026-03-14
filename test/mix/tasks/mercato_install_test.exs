defmodule Mix.Tasks.Mercato.InstallTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Mercato.Install

  test "inject_router_contents/1 inserts trust-boundary route macros" do
    router = """
    defmodule ExampleWeb.Router do
      use ExampleWeb, :router

      pipeline :api do
        plug :accepts, ["json"]
      end

      pipeline :browser do
        plug :accepts, ["html"]
      end

      scope "/api", ExampleWeb do
        pipe_through :api
      end

      scope "/", ExampleWeb do
        pipe_through :browser
      end
    end
    """

    updated = Install.inject_router_contents(router)

    assert updated =~ "import Mercato.Router"
    assert updated =~ "mercato_public_routes()"
    assert updated =~ "mercato_customer_routes()"
    assert updated =~ "mercato_admin_routes()"
    assert updated =~ "mercato_referral_routes(api_prefix: \"/api/mercato\")"
    refute updated =~ "mercato_basic_routes"
  end
end
