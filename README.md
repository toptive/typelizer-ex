# Typelizer

**Define once in Elixir. Generate everywhere in TypeScript.**

Typelizer is a library for Phoenix apps with a TypeScript frontend. It gives
you:

- **A serializer DSL** that is both the runtime serializer and the source of
  the TypeScript types.
- **TypeScript interfaces inferred from Ecto schemas**. `Ecto.Enum` fields
  become literal unions.
- **Typed route helpers** generated from your Phoenix router.
- **Typed page props for Inertia.js**, with a runtime check in dev and test.
- **`mix typelizer.gen`** to write the files and **`mix typelizer.check`** to
  fail on drift in CI and in git hooks.

## Installation

```elixir
def deps do
  [
    {:typelizer, "~> 0.1"}
  ]
end
```

`ecto`, `ecto_sql`, `phoenix`, `plug` and `inertia` are optional dependencies.
Typelizer uses them when your app has them. Typelizer supports Elixir 1.15+
and OTP 26+.

## Quick start: Phoenix + Inertia + React

**1. Write a serializer.** It serializes at runtime and it defines the type.

```elixir
defmodule MyAppWeb.TaskSerializer do
  use Typelizer.Serializer, schema: MyApp.Tasks.Task

  attributes [:id, :title, :status, :due_on]
  attribute :overdue, type: :boolean, value: &MyApp.Tasks.overdue?/1
  has_one :assignee, serializer: MyAppWeb.UserSerializer, nullable: true
end
```

**2. Declare the props of your Inertia pages** in the controller.

```elixir
defmodule MyAppWeb.TaskController do
  use MyAppWeb, :controller
  use Typelizer.InertiaPage

  page "tasks/index", props: [tasks: {:list, MyAppWeb.TaskSerializer}]

  def index(conn, _params) do
    conn
    |> assign_prop(:tasks, MyAppWeb.TaskSerializer.serialize_many(MyApp.Tasks.list()))
    |> render_inertia("tasks/index")
  end
end
```

**3. Configure and generate.**

```elixir
# config/config.exs
config :typelizer, repo: MyApp.Repo
config :inertia, camelize_props: true

# config/dev.exs and config/test.exs
config :typelizer, validate_inertia_props: true
```

```elixir
# lib/my_app_web/router.ex, in the :browser pipeline, after Inertia.Plug
plug Typelizer.InertiaPage.ValidateProps
```

```sh
mix typelizer.gen
```

**4. Use the types in React.**

```tsx
import type { TasksIndexProps } from "@/generated/pages";
import { routes } from "@/generated/routes";

export default function Index({ tasks }: TasksIndexProps) {
  return (
    <ul>
      {tasks.map((task) => (
        <li key={task.id}>
          <a href={routes.task.show(task.id).url}>{task.title}</a>
          {task.status === "done" && " ✓"}
        </li>
      ))}
    </ul>
  );
}
```

**5. Fail on drift.** Run `mix typelizer.check` in a pre-commit hook, in CI and
before a deploy. It exits with status 1 when the committed TypeScript does not
match the Elixir code.

## Guides

- [Getting started](guides/getting-started.md)
- [Serializers](guides/serializers.md)
- [Route helpers](guides/routes.md)
- [Inertia page props](guides/inertia.md)
- [Configuration](guides/configuration.md)

## Comparison with the Ruby gem

Typelizer for Elixir is a clean-room port of the idea behind the Ruby gem
[typelizer](https://github.com/skryukov/typelizer) by Svyatoslav Kryukov.
It shares no code with it.

| | Ruby typelizer | Typelizer for Elixir |
|---|---|---|
| Serializers | Adds types to existing serializer libraries (Alba, ActiveModel::Serializers and others) | Ships its own serializer DSL: one module serializes and defines the type |
| Type source | ActiveRecord models and the database schema | Ecto schemas, plus PostgreSQL column nullability when a repo is configured |
| Enums | Model enums | `Ecto.Enum` → literal unions |
| Route helpers | From `config/routes.rb` | From the Phoenix router |
| Inertia page props | No | Yes, with a runtime check in dev and test |
| Drift check | Your own task | Built in: `mix typelizer.check` |
| Regeneration | A file listener in development | `mix typelizer.gen` |

## Roadmap

Not in v0.1:

- Zod schemas as an output.
- OpenAPI documents as an output.
- Ash resources as a type source.

## Credits

The idea, the name and the developer experience come from
[skryukov/typelizer](https://github.com/skryukov/typelizer). Thank you.

## License

MIT. See [LICENSE](https://github.com/toptive/typelizer-ex/blob/main/LICENSE).
