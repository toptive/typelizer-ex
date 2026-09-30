defmodule Typelizer.RoutesTest do
  use ExUnit.Case, async: true

  alias Typelizer.GenerationError
  alias Typelizer.Generator.Routes

  @all %{include: [], exclude: []}

  test "the fixture router gives one file per group" do
    files = Routes.files(MyAppWeb.Router, %{include: [], exclude: ["/dev"]}, :camel)

    assert files |> Map.keys() |> Enum.sort() ==
             ~w(apiV1Member.ts apiV1Project.ts board.ts file.ts index.ts localizedFile.ts
                localizedPage.ts page.ts runtime.ts task.ts taskComment.ts)

    assert files["task.ts"] =~ ~s|url: buildUrl("/tasks/:id", params, options),|
    assert files["index.ts"] =~ "export const routes = {\n  apiV1Member,\n"
    assert Routes.files(MyAppWeb.Router, @all, :camel)["health.ts"]
  end

  describe "routes" do
    defmodule ConflictRouter do
      use Phoenix.Router

      get "/a", MyAppWeb.PageController, :show
      get "/b", MyAppWeb.PageController, :show
    end

    defmodule SnakeRouter do
      use Phoenix.Router

      get "/users/:user_id/posts/:post_id", MyAppWeb.PageController, :show, as: :user_post
      get "/", MyAppWeb.PageController, :home, as: nil
      put "/items/:id", MyAppWeb.PageController, :update, as: :item
      post "/items/:id", MyAppWeb.PageController, :update, as: :item_update
      get "/api/internal/x", MyAppWeb.PageController, :x, as: :internal
      get "/apiary", MyAppWeb.PageController, :apiary
    end

    defmodule ReservedRouter do
      use Phoenix.Router

      get "/x", MyAppWeb.PageController, :x, as: :new
    end

    test "two routes with the same group and action" do
      message =
        ~r{the routes GET /a \(MyAppWeb.PageController\) and GET /b \(MyAppWeb.PageController\) both become routes.page.show}

      assert_raise GenerationError, message, fn ->
        Routes.files(ConflictRouter, @all, :camel)
      end
    end

    test "a group name that is a reserved word" do
      assert_raise GenerationError, ~r/gets the group name "new"/, fn ->
        Routes.files(ReservedRouter, @all, :camel)
      end
    end

    test "snake_case params, routes without a helper and a lone PUT" do
      files = Routes.files(SnakeRouter, @all, :snake)

      assert files["userPost.ts"] =~
               "params: { user_id: string | number; post_id: string | number },"

      assert files["page.ts"] =~ "home: (options?: RouteOptions)"
      assert files["item.ts"] =~ ~s|): RouteDefinition<"put"> => ({|
      assert files["itemUpdate.ts"] =~ ~s|method: "post"|
    end

    test "include and exclude filters" do
      keys = fn filters ->
        SnakeRouter |> Routes.files(filters, :camel) |> Map.keys() |> Enum.sort()
      end

      assert keys.(%{include: ["/api"], exclude: []}) == ["index.ts", "internal.ts", "runtime.ts"]
      assert keys.(%{include: ["/api/"], exclude: [~r/internal/]}) == ["index.ts", "runtime.ts"]
      assert "internal.ts" not in keys.(%{include: [], exclude: ["/api"]})
      assert "page.ts" in keys.(%{include: ["/"], exclude: ["/api"]})

      assert_raise GenerationError, ~r/filters must be path prefixes/, fn ->
        keys.(%{include: [:api], exclude: []})
      end
    end

    test "no routes left" do
      files = Routes.files(SnakeRouter, %{include: ["/nothing"], exclude: []}, :camel)
      assert files["index.ts"] =~ "export const routes = {} as const;\n"
      refute files["index.ts"] =~ "import {"
    end
  end

  describe "URL defaults" do
    test "without defaults, every path param is required" do
      files = Routes.files(MyAppWeb.Router, %{include: ["/:locale"], exclude: []}, :camel)

      assert files["localizedPage.ts"] =~
               "    params: { locale: string | number; slug: string | number },\n"

      assert files["localizedPage.ts"] =~
               ~s|url: buildUrl("/:locale/articles/:slug", params, options),|
    end

    test "a defaulted param is optional, and a lone value is for the required param" do
      filters = %{include: ["/:locale"], exclude: [], defaults: ["locale"]}
      files = Routes.files(MyAppWeb.Router, filters, :snake)

      assert files["localizedPage.ts"] =~ "params?: { locale?: string | number },"
      assert files["localizedPage.ts"] =~ ~s|buildUrl("/:locale", params ?? {}, options)|

      assert files["localizedPage.ts"] =~
               ~s|buildUrl("/:locale/articles/:slug", params, options, "slug")|
    end

    test "defaults must be a list of param names" do
      assert_raise GenerationError,
                   ~r/routes: \[defaults: ...\] takes a list of path param names/,
                   fn ->
                     Routes.files(
                       MyAppWeb.Router,
                       %{include: [], exclude: [], defaults: :locale},
                       :camel
                     )
                   end
    end
  end
end
