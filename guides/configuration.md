# Configuration

All keys are optional. This block shows every key with its default value:

```elixir
config :typelizer,
  # Discovery. :auto finds every module of your app that uses the DSL.
  serializers: :auto,              # or a list: [MyAppWeb.TaskSerializer, …]
  pages: :auto,                    # or a list: [MyAppWeb.TaskController, …]
  router: :auto,                   # a router module, or false to skip route helpers

  # Output directories, relative to the project root. nil skips that output.
  output: [
    serializers: "assets/js/generated/serializers",
    routes: "assets/js/generated/routes",
    pages: "assets/js/generated/pages"
  ],

  # Types.
  key_transform: :camel,           # :camel or :snake
  decimal_type: :string,           # :string or :number
  type_names: %{},                 # %{MyAppWeb.TaskSerializer => "TaskDetail"}
  repo: nil,                       # MyApp.Repo: read column nullability from PostgreSQL

  # Route helpers.
  routes: [
    include: [],                   # path prefixes or regexes; [] keeps every route
    exclude: ["/dev"],             # path prefixes or regexes
    defaults: []                   # path params with a URL default, for example [:locale]
  ],

  # Inertia (runtime validation, dev and test only).
  validate_inertia_props: false,
  undeclared_inertia_pages: :raise, # :raise or :ignore

  # Formatting.
  prettier: false                  # true runs Prettier on the generated files
```

## Keys

### `serializers`, `pages`

`:auto` (the default) loads every module of the current Mix application and
keeps the ones that `use Typelizer.Serializer` or `use Typelizer.InertiaPage`.
Give a list of modules to choose them yourself.

### `router`

`:auto` (the default) uses the only module of your app that defines
`__routes__/0`. When there are several routers, set the one to use. `false`
skips route helpers.

### `output`

The directories that `mix typelizer.gen` writes to. `nil` for a key skips that
output. A key you leave out keeps its default. `mix typelizer.gen` deletes stale
generated files in these directories, but only files that start with the
typelizer header.

### `key_transform`

How Elixir names become TypeScript keys, for serializers, page props and route
params:

- `:camel`: `due_on` → `dueOn`.
- `:snake`: names stay as written.

A serializer can override it with `use Typelizer.Serializer, key_transform: :snake`.
Serializers read this key at compile time: run `mix compile --force` after you
change it.

### `decimal_type`

How `:decimal` values are typed and serialized:

- `:string` (default): `"12.50"` in JSON, `string` in TypeScript. No precision
  is lost.
- `:number`: a float in JSON, `number` in TypeScript.

Serializers read this key at compile time.

### `type_names`

A map from serializer module to TypeScript interface name. It wins over the
`name:` option and over the derived name.

### `repo`

An Ecto repo for PostgreSQL. When it is set, `mix typelizer.gen` and
`mix typelizer.check` start the repo and read `information_schema.columns` to
learn which columns are `NOT NULL`. See
[Nullability](serializers.md#nullability). The database must be reachable.

### `routes`

`include` and `exclude` filter the routes by path. An entry is a path prefix
(a string that matches whole segments) or a `Regex`. See
[Filters](routes.md#filters).

`defaults` lists the path params that get their value from `setUrlDefaults()` in
the frontend, as written in the router (`[:locale]`). They are optional in the
generated helpers. See [URL defaults](routes.md#url-defaults).

### `validate_inertia_props`, `undeclared_inertia_pages`

Turn on the `Typelizer.InertiaPage.ValidateProps` plug in dev and test, and
choose what it does with a page that has no declaration. See
[Validate rendered props](inertia.md#validate-rendered-props-dev-and-test).
These keys are read at runtime.

### `prettier`

`true` runs Prettier on the generated files, with the Prettier configuration of
your project. Typelizer looks for `node_modules/.bin/prettier` and then for
`assets/node_modules/.bin/prettier`. When `prettier: true` and Prettier is not
installed, generation fails. The output of Typelizer is already formatted with
two spaces, double quotes and semicolons, so most projects do not need it.

## Mix tasks

### `mix typelizer.gen`

Compiles the project, writes every generated file and deletes stale generated
files. It prints a summary:

```text
typelizer: wrote 3 files, 11 unchanged, removed 1 stale file.
```

A file is written only when its content changed.

### `mix typelizer.check`

Generates everything in memory and compares the result with
the output directories. It reports changed, missing and stale files with a
short diff, and exits with status 1 on drift. On success it prints:

```text
typelizer: the generated TypeScript is up to date.
```

## Generation errors

`mix typelizer.gen` and `mix typelizer.check` fail with a clear message when:

- a `serializer:` option or a type spec names a module that does not
  `use Typelizer.Serializer`;
- two serializers have the same interface name;
- two pages declare the same component, or two modules declare `shared`;
- two routes have the same group and action;
- a `query` declaration names an action that no route points to;
- `router: :auto` finds more than one router;
- `repo:` is set and the database is not reachable;
- a generated file would overwrite a file without the typelizer header.

## Output format

Every generated file starts with the line
`// Generated by typelizer — do not edit.` and ends with a newline. The same
input always gives byte-identical files: fields keep their declaration order,
and files, exports, route groups and actions are sorted by name.
