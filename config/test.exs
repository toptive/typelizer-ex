import Config

config :typelizer, MyApp.Repo,
  username: System.get_env("PGUSER", System.get_env("USER")),
  password: System.get_env("PGPASSWORD", ""),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: System.get_env("PGDATABASE", "typelizer_test"),
  pool_size: 2

config :typelizer, ecto_repos: [MyApp.Repo]

config :phoenix, :json_library, Jason
config :inertia, endpoint: MyAppWeb.Endpoint, camelize_props: true
config :logger, level: :warning
