defmodule Mix.Tasks.Typelizer.Gen do
  @shortdoc "Generates TypeScript from serializers, routes and Inertia pages"

  @moduledoc """
  Generates the TypeScript files: serializer interfaces, route helpers and Inertia page
  props.

      $ mix typelizer.gen

  The task compiles the project, writes every file whose content changed, and deletes
  stale generated files in the output directories. It never touches a file that does
  not start with the typelizer header.

  When `config :typelizer, repo: MyApp.Repo` is set, the database must be reachable:
  column nullability is read from it.

  See the [Configuration guide](configuration.md).
  """

  use Mix.Task

  alias Typelizer.{Output, Tasks}

  @impl Mix.Task
  def run(args) do
    Tasks.no_args!("typelizer.gen", args)

    Tasks.with_errors(fn ->
      stats = Tasks.config() |> Tasks.generate() |> Output.write()

      Mix.shell().info(
        "typelizer: wrote #{stats.written} #{Output.files(stats.written)}, " <>
          "#{stats.unchanged} unchanged, removed #{stats.removed} stale " <>
          "#{Output.files(stats.removed)}."
      )
    end)
  end
end
