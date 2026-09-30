defmodule Typelizer do
  @moduledoc """
  Define once in Elixir. Generate everywhere in TypeScript.

  Typelizer gives a Phoenix app:

    * `Typelizer.Serializer` - a serializer DSL that serializes records at runtime and
      is the source of a TypeScript interface. Types are inferred from Ecto schemas;
      `Ecto.Enum` fields become literal unions.
    * Typed route helpers generated from the Phoenix router.
    * `Typelizer.InertiaPage` - typed page props for Inertia.js pages, checked at
      runtime in dev and test by `Typelizer.InertiaPage.ValidateProps`.
    * `mix typelizer.gen` to write the TypeScript files and `mix typelizer.check` to
      fail when they are out of date.

  Start with the [Getting started guide](getting-started.md).
  """
end
