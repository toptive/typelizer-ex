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

# The TypeScript tests run when Node and the TypeScript compiler are installed
# (npm ci --prefix test/typescript).
typescript? = Typelizer.TypeScript.tsc() != nil

unless typescript? do
  IO.puts(
    "Node or TypeScript is missing (npm ci --prefix test/typescript): skipping the :typescript tests."
  )
end

exclude = [postgres: not postgres?, typescript: not typescript?]
ExUnit.start(exclude: for({tag, true} <- exclude, do: tag))
