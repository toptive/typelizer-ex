defmodule Typelizer.Tasks do
  @moduledoc false
  # Shared setup for the mix tasks.

  alias Typelizer.{Config, GenerationError, Generator, Prettier}

  @doc "Compiles the project and loads the configuration."
  @spec config() :: Config.t()
  def config do
    Mix.Task.run("app.config")
    Config.load(app: Mix.Project.config()[:app], root: File.cwd!())
  end

  @doc "Generates every output, with the optional Prettier pass."
  @spec generate(Config.t()) :: [Generator.output()]
  def generate(config), do: config |> Generator.generate() |> Prettier.format(config)

  @doc "Turns a generation error into a Mix error (exit status 1)."
  @spec with_errors((-> term())) :: term()
  def with_errors(fun) do
    fun.()
  rescue
    error in GenerationError -> Mix.raise("typelizer: " <> error.message)
  end

  @doc "Rejects arguments: the tasks take none."
  @spec no_args!(String.t(), [String.t()]) :: :ok
  def no_args!(_task, []), do: :ok

  def no_args!(task, args),
    do: Mix.raise("mix #{task} takes no arguments, got: #{Enum.join(args, " ")}")
end
