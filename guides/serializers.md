# Serializers

A serializer module does two jobs:

1. At runtime, `serialize/2` turns a struct or a map into a JSON-ready map.
2. At generation time, `mix typelizer.gen` writes a TypeScript interface for it.

Both jobs read the same declaration, so the data and its type cannot drift.

```elixir
defmodule MyAppWeb.TaskSerializer do
  use Typelizer.Serializer, schema: MyApp.Tasks.Task

  attributes [:id, :status, :due_on, :inserted_at]

  # The column is nullable, but the API always sends a title.
  attribute :title, nullable: false

  # A computed attribute must declare `type:`.
  attribute :overdue, type: :boolean, value: &MyApp.Tasks.overdue?/1

  # An arity-2 function gets the options given to `serialize/2`.
  attribute :can_edit,
    type: :boolean,
    value: fn task, opts -> task.owner_id == opts[:user_id] end

  has_one :assignee, serializer: MyAppWeb.UserSerializer, nullable: true
  has_many :comments, serializer: MyAppWeb.CommentSerializer
end
```

## `use Typelizer.Serializer`

| Option | Default | Meaning |
|---|---|---|
| `schema:` | `nil` | An Ecto schema or embedded schema. Typelizer infers types from it and checks that each attribute exists. |
| `name:` | derived | The TypeScript interface name. See [Names](#names). |
| `key_transform:` | `config :typelizer, key_transform:` (`:camel`) | `:camel` (`due_on` → `dueOn`) or `:snake` (keys stay as written). |

## Fields

Fields appear in the output and in the interface in declaration order.
A field declared twice is a compile error.

### `attributes/1`

```elixir
attributes [:id, :title, :status]
```

Schema fields. It needs `schema:`. Each name must be a field of the schema.
An association in `attributes` is a compile error: use `has_one` or `has_many`.
An embed (`embeds_one`, `embeds_many`) is allowed and becomes a nested object.

### `attribute/2`

```elixir
attribute :title
attribute :title, nullable: false
attribute :priority, type: {:enum, [:low, :high]}
attribute :overdue, type: :boolean, value: &MyApp.Tasks.overdue?/1
```

| Option | Meaning |
|---|---|
| `type:` | A [type spec](#type-specs). Required when the field has `value:` or the serializer has no `schema:`. It replaces the inferred type. |
| `nullable:` | `true` or `false`. Always wins. See [Nullability](#nullability). |
| `value:` | A function that computes the value: arity 1 (`record`) or arity 2 (`record, opts`). Anonymous functions and captures work. |
| `optional:` | `true` leaves the key out when the value is nil. TypeScript: `key?: T`. See [Optional keys](#optional-keys). |
| `if:` | A function (arity 1 or 2, like `value:`) that decides whether the key is sent. TypeScript: `key?: T`. |

The three-argument form takes the function as the last argument. The options
must be in brackets, because Elixir allows a keyword list only as the last
argument:

```elixir
attribute :overdue, [type: :boolean], fn task -> MyApp.Tasks.overdue?(task) end
```

### `has_one/2` and `has_many/2`

```elixir
has_one :assignee, serializer: MyAppWeb.UserSerializer, nullable: true
has_many :comments, serializer: MyAppWeb.CommentSerializer
has_one :owner, serializer: MyAppWeb.UserSerializer, value: fn task -> task.project.owner end
```

| Option | Meaning |
|---|---|
| `serializer:` | Required. The serializer module for the nested value(s). |
| `nullable:` | `has_one` only. `true` or `false`. |
| `value:` | A function (arity 1 or 2) that returns the nested value(s) instead of `record.<name>`. |
| `optional:` | `true` leaves the key out when the value is nil. |
| `if:` | A function (arity 1 or 2) that decides whether the key is sent. |

A `has_one` can point to an association (`belongs_to`, `has_one`) or to an
`embeds_one`. A `has_many` can point to a `has_many`, a `many_to_many` or an
`embeds_many`. With `value:`, the name does not have to exist on the schema.

Serializers may refer to each other in cycles (`Task` → `User` → `Task`).
A serializer reference is not a compile-time dependency.

### Optional keys

Two options make a key optional (`key?:` in TypeScript):

```elixir
# Sent only when the value is not nil: `archivedNote?: string`.
attribute :archived_note, type: :string, optional: true, value: &archived_note/1

# Sent only when the condition holds: `internalRank?: number | null`.
attribute :internal_rank, type: {:nullable, :integer}, if: fn _task, opts -> opts[:admin] end

# Guard an association that is not always preloaded: `project?: Project`.
has_one :project, serializer: MyAppWeb.ProjectSerializer, if: &Ecto.assoc_loaded?(&1.project)
```

- With `optional: true`, the value is never null in the output, so the type has no
  `| null`. A `has_many` with `optional: true` leaves the key out for nil and sends
  `[]` as `[]`.
- With `if:`, the value is computed only when the condition holds. The type keeps
  its nullability: `key?: T | null` when the value can be nil.
- `value:` and `if:` must be written inline (an anonymous function or a capture),
  not passed in a variable.

## Runtime

```elixir
MyAppWeb.TaskSerializer.serialize(task)
MyAppWeb.TaskSerializer.serialize(task, user_id: current_user.id)
MyAppWeb.TaskSerializer.serialize_many(tasks)
MyAppWeb.TaskSerializer.serialize_many(tasks, user_id: current_user.id)
MyAppWeb.TaskSerializer.serialize(nil)
#=> nil
```

- The keys are strings, after the key transform.
- The values match the TypeScript type:
  - `Date`, `Time`, `NaiveDateTime` and `DateTime` → ISO-8601 strings.
  - `Decimal` → a string (`"12.50"`), or a float with `decimal_type: :number`.
  - `Ecto.Enum` atoms → strings.
  - Embeds → maps with transformed keys.
  - Values typed `:map`, `:any`, `:unknown`, `{:union, …}`, `{:intersection, …}` or
    `{:ts, …}` pass through unchanged.
- The options go down to nested serializers.
- An association that is not preloaded raises `Typelizer.SerializationError`
  with the serializer, the field and a hint to preload it.
- The field list, the keys and the encoders are built at compile time.
  `serialize/2` does no schema reflection per call.

## Type inference from Ecto

For a schema field without `type:`, Typelizer reads the Ecto type:

| Ecto type | TypeScript |
|---|---|
| `:id`, `:integer`, `:float` | `number` |
| `:binary_id`, `Ecto.UUID`, `:string`, `:binary` | `string` |
| `:boolean` | `boolean` |
| `:decimal` | `string` (`number` with `decimal_type: :number`) |
| `:date`, `:time`, `:naive_datetime`, `:utc_datetime` (and `_usec`) | `string` |
| `:map` | `Record<string, unknown>` |
| `:any` (virtual fields) | `unknown` |
| `{:map, t}` | `Record<string, T>` |
| `{:array, t}` | `T[]` |
| `Ecto.Enum` | a literal union: `"todo" \| "doing" \| "done"` |
| `{:array, Ecto.Enum}` | `("a" \| "b")[]` |
| `embeds_one` | a nested object with every field of the embedded schema |
| `embeds_many` | an array of that nested object |
| a custom `Ecto.Type` | inferred from its `type/0` (see below) |

A type that Typelizer cannot map is a compile error that asks you to add
`type:`.

### Custom types with struct values

For a custom `Ecto.Type`, Typelizer reads `type/0`: the type of the database
column. When the value in the struct is a struct of its own (for example a
`Money` type stored as a string or an integer), that type is wrong for JSON:
the TypeScript type says `string`, and the struct passes through unchanged, so
the JSON encoder fails or sends a different shape. Declare the type and convert
the value yourself:

```elixir
attribute :price, type: :string, value: fn product -> Money.to_string(product.price) end

attribute :price,
  type: {:object, amount: :integer, currency: :string},
  value: fn product -> %{amount: product.price.amount, currency: product.price.currency} end
```

## Type specs

Type specs are used by `type:` and by Inertia page props.

| Spec | TypeScript |
|---|---|
| `:string`, `:binary_id`, `:uuid`, `:binary` | `string` |
| `:integer`, `:float`, `:number`, `:id` | `number` |
| `:boolean` | `boolean` |
| `:decimal` | `string` (`number` with `decimal_type: :number`) |
| `:date`, `:time`, `:naive_datetime`, `:utc_datetime`, `:datetime` (and `_usec`) | `string` |
| `:map` | `Record<string, unknown>` |
| `:any` | `any` |
| `:unknown` | `unknown` |
| `{:list, spec}` or `{:array, spec}` | `T[]` |
| `{:map, spec}` | `Record<string, T>` |
| `{:enum, values}` (atoms, strings or integers) | `"a" \| "b"` or `1 \| 2` |
| `{:nullable, spec}` | `T \| null` |
| `{:object, [key: spec, …]}` | `{ key: T; … }` (keys transformed) |
| `{:optional, spec}` | inside `{:object, …}` and page props only: `key?: T` |
| `{:union, [spec, …]}` | `A \| B` |
| `{:intersection, [spec, …]}` | `A & B` |
| `{:ts, "raw TypeScript"}` | the text as written |
| `{:ts, "raw TypeScript", [Serializer, …]}` | the text as written, with imports for the named serializers |
| a serializer module | its interface (imported) |

An invalid type spec is a compile error. Inside a list, a union, an intersection
or raw TypeScript with operators gets parentheses: `(A | B)[]`.

```elixir
attribute :subject,
  type: {:union, [MyAppWeb.UserSerializer, MyAppWeb.ProjectSerializer]},
  value: &subject/1

attribute :card,
  type: {:ts, "Omit<User, \"role\"> & { online: boolean }", [MyAppWeb.UserSerializer]},
  value: &card/1
```

The serializer does not change values typed `{:union, …}`, `{:intersection, …}` or
`{:ts, …}`: it cannot know which member a value is. Return JSON-ready values from
`value:`, for example by calling the right serializer yourself:

```elixir
defp subject(%{subject: %MyApp.Accounts.User{} = user}), do: MyAppWeb.UserSerializer.serialize(user)
defp subject(%{subject: project}), do: MyAppWeb.ProjectSerializer.serialize(project)
```

## Nullability

The first rule that applies wins:

1. An explicit `nullable:` option, or a `{:nullable, spec}` type. With
   `optional: true` the field is never null (the key is left out instead).
2. A field with its own `type:` (a computed attribute, or any attribute with
   `type:`) is not nullable.
3. The primary key and the `timestamps()` fields are not nullable.
   A `has_many` is never nullable.
4. When `config :typelizer, repo: MyApp.Repo` is set, `mix typelizer.gen` reads
   `information_schema.columns` in PostgreSQL. `NOT NULL` columns are not
   nullable. For a `has_one` over a `belongs_to`, the foreign key column
   decides. For a `has_one` over an `embeds_one`, the embed column decides.
   The database must be reachable, or the task fails.
5. Otherwise the field is nullable.

Fields inside an inline embed (from `attributes`) follow rules 3 and 5. For full
control over an embed, write a serializer for the embedded schema and use
`has_one` or `has_many`.

## Names

The default interface name comes from the module name. Typelizer drops the
first segment (your app or web namespace), drops a `Serializers` segment and
drops the `Serializer` suffix. It joins the rest:

| Module | Interface |
|---|---|
| `MyAppWeb.TaskSerializer` | `Task` |
| `MyAppWeb.Admin.TaskSerializer` | `AdminTask` |
| `MyApp.Serializers.TaskSerializer` | `Task` |

Change it with `use Typelizer.Serializer, name: "TaskDetail"` or with
`config :typelizer, type_names: %{MyAppWeb.TaskSerializer => "TaskDetail"}`.
The config wins. Two serializers with the same name fail the generation.

## Generated TypeScript

One file per serializer, named after the interface, plus `index.ts`:

```ts
// assets/js/generated/serializers/Task.ts
// Generated by typelizer — do not edit.
// Source: MyAppWeb.TaskSerializer

import type { Comment } from "./Comment";
import type { User } from "./User";

export interface Task {
  id: string;
  status: "todo" | "doing" | "done";
  dueOn: string | null;
  insertedAt: string;
  title: string;
  overdue: boolean;
  canEdit: boolean;
  assignee: User | null;
  comments: Comment[];
}
```

```ts
// assets/js/generated/serializers/index.ts
// Generated by typelizer — do not edit.

export type { Comment } from "./Comment";
export type { Task } from "./Task";
export type { User } from "./User";
```

An embed renders as a nested object:

```ts
export interface Project {
  id: string;
  settings: {
    theme: "light" | "dark" | null;
    notifyOnDone: boolean | null;
  } | null;
}
```

## Compile-time errors

Typelizer raises a `CompileError` with a hint for:

- `attributes` or `attribute` without `schema:` and without `type:`;
- `value:` without `type:`;
- a field that is not in the schema;
- an association in `attributes`;
- `has_one` or `has_many` without `serializer:`;
- a field declared twice;
- an invalid type spec;
- an Ecto type that Typelizer cannot map.

`mix typelizer.gen` fails when a `serializer:` or a type spec names a module
that does not `use Typelizer.Serializer`.

## Introspection

`MyAppWeb.TaskSerializer.__typelizer__(:name)`, `(:schema)`, `(:fields)` and
`(:key_transform)` return the compiled metadata. The generator uses them; you
normally do not.
