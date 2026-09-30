# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-30

### Added

- `Typelizer.Serializer`: a serializer DSL (`attributes`, `attribute` with `type:`,
  `nullable:` and `value:`, `has_one`, `has_many`) that builds `serialize/2` and
  `serialize_many/2` at compile time. Types are inferred from Ecto schemas, including
  `Ecto.Enum` literal unions and embeds; Ecto `:any` becomes `unknown`. Keys are camelCase by default
  (`key_transform:`), dates become ISO-8601 strings and decimals strings (or numbers
  with `decimal_type: :number`). Mistakes are compile errors with a hint.
- Type specs `{:union, [...]}`, `{:intersection, [...]}` and
  `{:ts, text, [Serializer, ...]}` (raw TypeScript that imports the named serializers).
  Unions, intersections and raw TypeScript with operators get parentheses inside lists.
- Route helper generation from the Phoenix router: one typed helper per route
  (`routes.task.show(id)` → `{ url, method }`), typed path params, query strings in
  the Plug format (nested objects, arrays of objects, dates), encoded anchors, `setRoutesBaseUrl()` and path filters.
- The generated TypeScript passes `tsc --strict --noUncheckedIndexedAccess
  --exactOptionalPropertyTypes --verbatimModuleSyntax`; a test checks it on every run.
- `Typelizer.InertiaPage`: `page/2` declares the props of an Inertia page and
  `shared/1` the props shared by every page.
- `Typelizer.InertiaPage.ValidateProps`: a plug that raises
  `Typelizer.InertiaPage.PropsError` in dev and test when a rendered page sends
  missing or undeclared props (`config :typelizer, validate_inertia_props: true`).
- `mix typelizer.gen`: writes one TypeScript interface per serializer, the route
  helpers and the Inertia page props (`<component>.props.ts`, `SharedProps`, a
  `Pages` map). Deterministic output; stale generated files are removed; files
  without the typelizer header are never touched. Optional Prettier pass.
- `mix typelizer.check`: exits with status 1 and a short diff when the committed
  TypeScript is out of date.
- Column nullability from PostgreSQL `information_schema` when `repo:` is set.
- User guides for the public API: getting started, serializers, route helpers,
  Inertia page props and configuration. They explain how `camelize_props` changes
  nested and data keys (and `preserve_case/1`), and how to serialize custom Ecto
  types whose values are structs.

[0.1.0]: https://github.com/toptive/typelizer-ex/releases/tag/v0.1.0
