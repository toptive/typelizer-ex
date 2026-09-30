# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-09-30

Backward compatible with 0.1. After the upgrade, run `mix typelizer.gen`: the route
runtime (`routes/runtime.ts`) and `routes/index.ts` get the new exports, so
`mix typelizer.check` reports them until they are regenerated. Other generated files
do not change unless you use the new features.

### Added

- URL defaults for route helpers: `setUrlDefaults()` (an object, or a function read
  on every call) and `addUrlDefault()` in the generated runtime, and
  `config :typelizer, routes: [defaults: [:locale]]` to make those params optional
  in the helper types. A route whose only required param is not the first one
  accepts its value directly (`routes.article.show("intro")`).
  ([#1](https://github.com/toptive/typelizer-ex/issues/1))
- Typed query params: `use Typelizer.Query` and `query :index, page: {:optional,
  :integer}, ...` in a controller (or a LiveView) type the `query` option of the
  route helper through a generated `TaskIndexQuery` type. `:date` and `:time` params
  are strings; datetime params accept a string or a `Date`. `RouteOptions` becomes
  `RouteOptions<Q>`; its default keeps the 0.1 type.
  ([#2](https://github.com/toptive/typelizer-ex/issues/2))
- `Typelizer.Envelope`: `wrap/2`, `paginated/2` and `cursor_paginated/2` build
  `{ data, meta }` values; the type specs `{:envelope, spec}`,
  `{:envelope, spec, meta_spec}`, `{:paginated, item}` and `{:cursor_paginated, item}`
  generate `Envelope<T, M>`, `Paginated<T>` and `CursorPaginated<T>` from a shared
  `Envelope.ts`, which is written only when a spec uses it.
  ([#3](https://github.com/toptive/typelizer-ex/issues/3))
- `config :typelizer, validate_inertia_props: :values` also checks each rendered
  Inertia prop value against its declared type in dev and test (types, enums,
  nullability, serializer fields and nested serializers, envelopes) and reports
  each mismatch with a path such as `tasks[3].status`. `true` keeps the key-only
  check. ([#4](https://github.com/toptive/typelizer-ex/issues/4))

## [0.1.0] - 2026-09-30

### Added

- `Typelizer.Serializer`: a serializer DSL (`attributes`, `attribute` with `type:`,
  `nullable:` and `value:`, `has_one`, `has_many`) that builds `serialize/2` and
  `serialize_many/2` at compile time. Types are inferred from Ecto schemas, including
  `Ecto.Enum` literal unions and embeds; Ecto `:any` becomes `unknown`. Keys are camelCase by default
  (`key_transform:`), dates become ISO-8601 strings and decimals strings (or numbers
  with `decimal_type: :number`). Mistakes are compile errors with a hint.
- `required:` on an embed attribute lists the embed fields that are never null
  (`required: [:street, geo: [:lat, :lng]]` or `required: :all`).
- `optional: true` (leave the key out when the value is nil) and `if:` (send the
  key only when a condition holds) on `attribute`, `has_one` and `has_many`. Both
  make the TypeScript key optional (`key?:`).
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

[Unreleased]: https://github.com/toptive/typelizer-ex/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/toptive/typelizer-ex/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/toptive/typelizer-ex/releases/tag/v0.1.0
