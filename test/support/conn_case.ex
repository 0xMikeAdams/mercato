defmodule Mercato.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      alias Mercato.Repo

      @endpoint Mercato.TestEndpoint
    end
  end

  setup tags do
    # Idiomatic Ecto-sandbox owner setup: for non-async tests this runs in shared mode so
    # the endpoint process tree (and any process a controller action spawns) can use the
    # test's connection — without this an action doing DB work off the request process
    # raises DBConnection.OwnershipError.
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Mercato.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if Process.whereis(Mercato.TestEndpoint) == nil do
      start_supervised!(Mercato.TestEndpoint)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
