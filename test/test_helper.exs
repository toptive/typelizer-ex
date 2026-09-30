# The PostgreSQL tests run when a server accepts connections on PGHOST (default:
# localhost) and PGPORT (default: 5432).
pg_host = System.get_env("PGHOST", "localhost")
pg_port = String.to_integer(System.get_env("PGPORT", "5432"))

postgres? =
  case :gen_tcp.connect(String.to_charlist(pg_host), pg_port, [], 500) do
    {:ok, socket} ->
      :gen_tcp.close(socket)
      true

    {:error, _} ->
      false
  end

unless postgres? do
  IO.puts("PostgreSQL is not reachable on #{pg_host}:#{pg_port}: skipping the :postgres tests.")
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
