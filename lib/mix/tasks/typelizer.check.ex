defmodule Mix.Tasks.Typelizer.Check do
  @shortdoc "Fails when the generated TypeScript is out of date"

  @moduledoc """
  Checks that the generated TypeScript files match the Elixir code.

      $ mix typelizer.check

  The task generates every file in memory and compares the result with the output
  directories. On drift it prints the changed, missing and stale files with a short
  diff, and exits with status 1. Run it in git hooks, in CI and before a deploy.

  See the [Configuration guide](configuration.md).
  """

  use Mix.Task

  alias Typelizer.{Output, Tasks}

  @impl Mix.Task
  def run(args) do
    Tasks.no_args!("typelizer.check", args)

    Tasks.with_errors(fn ->
      config = Tasks.config()

      case config |> Tasks.generate() |> Output.diff() do
        [] ->
          Mix.shell().info("typelizer: the generated TypeScript is up to date.")

        changes ->
          Mix.shell().error(Output.report(changes, config.root))
          exit({:shutdown, 1})
      end
    end)
  end
end
