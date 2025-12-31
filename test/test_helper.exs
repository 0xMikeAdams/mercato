ExUnit.start()

# Set up Ecto Sandbox for concurrent tests
Ecto.Adapters.SQL.Sandbox.mode(Mercato.Repo, :manual)
