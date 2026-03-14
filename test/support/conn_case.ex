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

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mercato.Repo)

    if Process.whereis(Mercato.TestEndpoint) == nil do
      start_supervised!(Mercato.TestEndpoint)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
