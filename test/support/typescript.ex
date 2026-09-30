defmodule Typelizer.TypeScript do
  @moduledoc false
  # Finds the TypeScript compiler for the :typescript tests.

  @local Path.expand("../typescript/node_modules/.bin/tsc", __DIR__)

  def tsc do
    cond do
      System.find_executable("node") == nil -> nil
      File.exists?(@local) -> @local
      true -> System.find_executable("tsc")
    end
  end

  def tsc!, do: tsc() || raise("TypeScript not found: run npm ci --prefix test/typescript")
end
