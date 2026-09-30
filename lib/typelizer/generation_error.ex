defmodule Typelizer.GenerationError do
  @moduledoc false
  # Raised by `mix typelizer.gen` and `mix typelizer.check` when the code cannot be
  # turned into TypeScript. The mix tasks print the message and exit with status 1.

  defexception [:message]
end
