# The PostgreSQL tests run when a local server accepts connections.
postgres? =
  case :gen_tcp.connect(~c"localhost", 5432, [], 500) do
    {:ok, socket} ->
      :gen_tcp.close(socket)
      true

    {:error, _} ->
      false
  end

unless postgres? do
  IO.puts("PostgreSQL is not reachable on localhost:5432: skipping the :postgres tests.")
end

ExUnit.start(exclude: if(postgres?, do: [], else: [:postgres]))
