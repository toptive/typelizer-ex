defmodule Typelizer.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/toptive/typelizer-ex"

  def project do
    [
      app: :typelizer,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Optional dependencies, used only when the host app has them.
      xref: [exclude: [Decimal, Ecto.Adapters.SQL, Ecto.Adapters.Postgres]],
      name: "Typelizer",
      description:
        "Define once in Elixir. Generate everywhere in TypeScript: serializers, " <>
          "Phoenix route helpers and Inertia page props.",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts"
      ]
    ]
  end

  def cli do
    [preferred_envs: [check: :test]]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.10", optional: true},
      {:ecto_sql, "~> 3.10", optional: true},
      {:plug, "~> 1.14", optional: true},
      {:phoenix, "~> 1.7", optional: true},
      {:inertia, "~> 2.6", optional: true},
      {:jason, "~> 1.4", optional: true},
      {:postgrex, "~> 0.19", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib guides mix.exs .formatter.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/serializers.md",
        "guides/routes.md",
        "guides/inertia.md",
        "guides/configuration.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r{guides/}
      ],
      groups_for_modules: [
        DSL: [Typelizer.Serializer, Typelizer.InertiaPage],
        Runtime: [Typelizer.InertiaPage.ValidateProps],
        Errors: [Typelizer.SerializationError, Typelizer.InertiaPage.PropsError]
      ]
    ]
  end
end
