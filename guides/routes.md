# Route helpers

Typelizer reads your Phoenix router and writes a TypeScript module with one
typed helper per route. The frontend never hardcodes a path, and a renamed
route breaks the TypeScript build instead of a user's click.

```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  pipe_through :browser

  get "/", PageController, :home

  resources "/tasks", TaskController do
    resources "/comments", CommentController, only: [:index, :create]
  end
end
```

```ts
import { routes, setRoutesBaseUrl } from "@/generated/routes";

routes.page.home();                        // { url: "/", method: "get" }
routes.task.index();                       // { url: "/tasks", method: "get" }
routes.task.show(42);                      // { url: "/tasks/42", method: "get" }
routes.task.show({ id: 42 });              // the same
routes.task.update(42);                    // { url: "/tasks/42", method: "patch" }
routes.task.delete(42);                    // { url: "/tasks/42", method: "delete" }
routes.taskComment.create({ taskId: 42 }); // { url: "/tasks/42/comments", method: "post" }

routes.task.index({ query: { page: 2, tags: ["a", "b"] } });
// { url: "/tasks?page=2&tags[]=a&tags[]=b", method: "get" }

routes.task.show(42, { anchor: "notes" });
// { url: "/tasks/42#notes", method: "get" }

setRoutesBaseUrl("https://app.example.com");
routes.task.show(42).url;                  // "https://app.example.com/tasks/42"
```

Each helper returns a `RouteDefinition`: `{ url: string; method: M }`, where
`M` is the literal HTTP method. Pass it to your HTTP client or to Inertia:

```tsx
import { Link, router } from "@inertiajs/react";

<Link href={routes.task.show(task.id).url}>{task.title}</Link>;
router.visit(routes.task.update(task.id).url, { method: "patch", data });
```

## Setup

The router is found automatically when your app has exactly one module with
`__routes__/0`. Set it when you have several:

```elixir
config :typelizer, router: MyAppWeb.Router
```

Set `router: false` to skip route helpers.

## Rules

- **Group name**: the Phoenix helper name of the route, camelCased: `task`,
  `taskComment`, `apiV1Task`. Change it with the router's `as:` option.
  A route without a helper name uses its controller:
  `MyAppWeb.Admin.UserController` → `adminUser`.
- **Action name**: the controller action, camelCased: `index`, `show`, `new`,
  `edit`, `create`, `update`, `delete`, or any custom action. A LiveView route
  uses its live action, or `index` when it has none.
- `PUT` and `PATCH` for the same action become one helper with
  `method: "patch"`.
- Two routes with the same group and action make `mix typelizer.gen` fail with
  a message that names both routes. Set `as:` on one of them or exclude one.
- Only `GET`, `POST`, `PUT`, `PATCH` and `DELETE` routes are generated.
  `forward` routes are skipped.
- **Path params** are typed `string | number`. A glob param (`*path`) takes
  `string | string[]`. The param keys follow the key transform (`:task_id`
  becomes `taskId` with `:camel`); at runtime both spellings work.
- A route with one path param accepts the value directly: `show(42)`.
  A route with several takes an object: `show({ taskId: 1, id: 2 })`.
- The last argument is optional: `{ query?: Record<string, unknown>; anchor?: string }`.
  A route without path params takes only this argument.
- **Query strings** follow the Plug conventions: arrays become `key[]=v`,
  nested objects become `key[sub]=v`, and arrays of objects become
  `sort[0][field]=price&sort[1][field]=name` (the indexed map that Phoenix forms
  send, which `cast_assoc` accepts). `Date` values become ISO-8601 strings, and
  `null` or `undefined` values are skipped. The anchor is URL-encoded.

## Filters

```elixir
config :typelizer,
  routes: [
    include: ["/api", "/app"],
    exclude: ["/dev", ~r{^/admin/internal}]
  ]
```

An entry is a path prefix (a string) or a `Regex`. A prefix matches whole path
segments: `"/api"` matches `/api` and `/api/tasks`, not `/apiary`.
`include: []` (the default) keeps every route. `exclude` wins over `include`.

The default is `exclude: ["/dev"]`: Phoenix puts its development-only routes
(LiveDashboard, the mailbox preview) under `/dev`, and they exist only in the dev
environment. Keep them out, or `mix typelizer.check` gives different results in
dev and in CI. When you set `exclude`, it replaces the default.

## Typed query params

By default the `query` option takes any object. Declare the query params of an
action with `Typelizer.Query` to type it:

```elixir
defmodule MyAppWeb.TaskController do
  use MyAppWeb, :controller
  use Typelizer.Query

  query :index,
    page: {:optional, :integer},
    status: {:optional, {:enum, [:todo, :doing, :done]}},
    due_before: {:optional, :date},
    sort: {:optional, {:list, {:object, field: :string, dir: {:enum, [:asc, :desc]}}}}

  query :show, include: {:list, {:enum, [:comments, :assignee]}}

  def index(conn, params), do: ...
  def show(conn, params), do: ...
end
```

```ts
routes.task.index({ query: { page: 2, status: "todo" } });   // ok
routes.task.index({ query: { stauts: "todo" } });            // compile error
routes.task.index({ query: { due_before: new Date() } });    // ok: sent as ISO-8601
routes.task.show(42, { query: { include: ["comments"] } });  // `include` is required
```

The generator writes a named type per action, `TaskIndexQuery`, next to the
helpers, and `index.ts` exports it:

```ts
export type TaskIndexQuery = {
  page?: number;
  status?: "todo" | "doing" | "done";
  due_before?: string | Date;
  sort?: {
    field: string;
    dir: "asc" | "desc";
  }[];
};

export const task = {
  index: (options?: RouteOptions<TaskIndexQuery>): RouteDefinition<"get"> => ({
  // …
```

- The specs are the [type specs](serializers.md#type-specs) of serializers, without
  serializer modules. `{:optional, spec}` marks a param that may be left out.
- Query keys stay as written (snake_case): Phoenix reads them as written. The key
  transform does not apply.
- Dates accept a string or a `Date`; decimals accept a string or a number.
- `query :edit, []` allows no query params at all.
- Only types are generated. Cast and validate `params` in the controller as usual.
- An action without a declaration keeps `RouteOptions` (any query).
- A LiveView can declare the query params of its live actions the same way.
- Errors: an invalid spec, a declaration twice or an action that the controller
  does not define is a `CompileError`. A declaration for an action that no route
  of the router points to fails `mix typelizer.gen`.

## URL defaults

Some path params are the same in almost every URL: a locale, the current
organization. List them in the config:

```elixir
scope "/:locale", MyAppWeb do
  get "/articles/:slug", ArticleController, :show
end

config :typelizer, routes: [defaults: [:locale]]
```

Then set their values once in the frontend:

```ts
import { addUrlDefault, routes, setUrlDefaults } from "@/generated/routes";

setUrlDefaults({ locale: "en" });
routes.article.show("intro");                      // "/en/articles/intro"
routes.article.show({ slug: "intro", locale: "es" }); // a given value wins: "/es/articles/intro"

// A function is called on every URL, so it always reads the current value.
setUrlDefaults(() => ({ locale: i18n.language }));

// Add one default and keep the others.
addUrlDefault("organizationId", 7);
```

- A param in `defaults` is optional in the helper types
  (`{ locale?: string | number; slug: string | number }`).
- When one param is still required, the helper takes its value directly
  (`show("intro")`).
- When every param has a default, the params argument is optional, and the
  options come second: `routes.home.index({}, { query: { q: "x" } })`.
- A default key may be written in snake_case or camelCase.
- A missing value (no param and no default) throws
  `typelizer: missing route param "locale" for /:locale/articles/:slug`.
- `setUrlDefaults()` and `addUrlDefault()` work for any path param, also one that
  is not in `defaults`; only the TypeScript types differ.

## Generated files

The default directory is `assets/js/generated/routes`:

- `runtime.ts`: the `Method`, `RouteDefinition<M>`, `RouteOptions<Q>` and
  `UrlDefaults` types, `setRoutesBaseUrl()`, `setUrlDefaults()`, `addUrlDefault()`
  and `buildUrl()`.
- `<group>.ts`: one file per group, for example `task.ts` exports `task` and the
  query types of its actions.
- `index.ts`: re-exports each group and the runtime API, and exports `routes`,
  one object with every group.

```ts
// assets/js/generated/routes/task.ts
// Generated by typelizer — do not edit.

import { buildUrl, type RouteDefinition, type RouteOptions } from "./runtime";

export const task = {
  /** POST /tasks */
  create: (options?: RouteOptions): RouteDefinition<"post"> => ({
    url: buildUrl("/tasks", {}, options),
    method: "post",
  }),
  /** DELETE /tasks/:id */
  delete: (
    params: { id: string | number } | string | number,
    options?: RouteOptions,
  ): RouteDefinition<"delete"> => ({
    url: buildUrl("/tasks/:id", params, options),
    method: "delete",
  }),
  // edit, index, new, show, update
} as const;
```

```ts
// assets/js/generated/routes/index.ts
// Generated by typelizer — do not edit.

import { page } from "./page";
import { task } from "./task";
import { taskComment } from "./taskComment";

export { page, task, taskComment };
export {
  addUrlDefault,
  buildUrl,
  setRoutesBaseUrl,
  setUrlDefaults,
} from "./runtime";
export type {
  Method,
  RouteDefinition,
  RouteOptions,
  UrlDefaults,
} from "./runtime";

export const routes = {
  page,
  task,
  taskComment,
} as const;
```

Groups and actions are sorted by name, so the output does not change when you
reorder the router.
