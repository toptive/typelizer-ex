defmodule Typelizer.InertiaPageTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Typelizer.InertiaPage.{PropsError, ValidateProps, Validation}

  setup do
    Application.put_env(:typelizer, :validate_inertia_props, true)

    on_exit(fn ->
      Application.delete_env(:typelizer, :validate_inertia_props)
      Application.delete_env(:typelizer, :undeclared_inertia_pages)
    end)
  end

  # Runs a request through the plugs of a typical :browser pipeline, then the action.
  defp request(controller, action, params \\ %{}, headers \\ []) do
    conn =
      conn(:get, "/", params)
      |> put_req_header("x-inertia", "true")
      |> put_req_header("x-inertia-version", "1")
      |> then(fn conn ->
        Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
      end)
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> Inertia.Plug.call(Inertia.Plug.init([]))
      |> Inertia.Controller.assign_prop(:current_user, nil)
      |> Inertia.Controller.assign_prop(:locale, "en")
      |> ValidateProps.call(ValidateProps.init([]))

    controller.call(conn, controller.init(action))
  rescue
    # Phoenix wraps controller errors; the router unwraps them in a real app.
    error in Plug.Conn.WrapperError -> reraise error.reason, error.stack
  end

  defp props(conn), do: conn.resp_body |> Jason.decode!() |> Map.fetch!("props")

  test "a page that sends exactly the declared props renders" do
    conn = request(MyAppWeb.TaskController, :index)

    assert conn.status == 200

    assert props(conn) |> Map.keys() |> Enum.sort() ==
             ~w(currentUser errors filters flash locale nextCursor tasks)
  end

  test "an optional prop may be sent" do
    conn = request(MyAppWeb.TaskController, :index)
    assert conn.status == 200
  end

  test "a missing prop raises" do
    error =
      assert_raise PropsError, fn ->
        request(MyAppWeb.TaskController, :index, %{"next_cursor" => "skip"})
      end

    assert error.message ==
             ~s(Inertia page "tasks/index" does not match its declaration in MyAppWeb.TaskController:\n) <>
               "  missing: nextCursor"
  end

  test "a prop that is not declared raises" do
    error =
      assert_raise PropsError, fn ->
        request(MyAppWeb.TaskController, :index, %{"extra" => "send"})
      end

    assert error.message =~ "  not declared: extra"
  end

  test "keys that are not camelCase get a hint" do
    Application.put_env(:inertia, :camelize_props, false)

    try do
      error = assert_raise PropsError, fn -> request(MyAppWeb.TaskController, :index) end
      assert error.message =~ "  missing: currentUser, nextCursor"
      assert error.message =~ "  not declared: current_user, next_cursor"
      assert error.message =~ "Hint: the keys are not camelCase."
    after
      Application.put_env(:inertia, :camelize_props, true)
    end
  end

  test "a deferred prop must be optional" do
    [{module, _}] =
      Code.compile_string("""
      defmodule Typelizer.InertiaPageTest.StrictController do
        use Phoenix.Controller, formats: [:json]
        use Typelizer.InertiaPage
        import Inertia.Controller

        page "strict", props: [stats: :map]

        def show(conn, _params) do
          conn
          |> assign_prop(:stats, inertia_defer(fn -> %{} end))
          |> render_inertia("strict")
        end
      end
      """)

    error = assert_raise PropsError, fn -> request(module, :show) end
    assert error.message =~ "  deferred but not optional: stats"
    assert error.message =~ "Declare it as {:optional, spec}"

    conn = request(MyAppWeb.TaskController, :index, %{"stats" => "defer"})
    assert conn.status == 200
    refute Map.has_key?(props(conn), "stats")
  end

  test "a partial reload checks only undeclared props" do
    headers = [
      {"x-inertia-partial-component", "tasks/index"},
      {"x-inertia-partial-data", "tasks"}
    ]

    conn = request(MyAppWeb.TaskController, :index, %{}, headers)
    assert conn.status == 200
    assert Map.keys(props(conn)) |> Enum.sort() == ~w(errors flash tasks)
  end

  test "a page without a declaration raises, unless ignored" do
    error = assert_raise PropsError, fn -> request(MyAppWeb.TaskController, :edit) end
    assert error.message =~ ~s(Inertia page "tasks/edit" has no declaration)

    Application.put_env(:typelizer, :undeclared_inertia_pages, :ignore)
    assert request(MyAppWeb.TaskController, :edit).status == 200
  end

  test "the declaration may live in another module of the app" do
    [{module, _}] =
      Code.compile_string("""
      defmodule Typelizer.InertiaPageTest.OtherController do
        use Phoenix.Controller, formats: [:json]
        import Inertia.Controller

        def show(conn, _params) do
          conn
          |> assign_prop(:task, %{})
          |> assign_prop(:can_edit, false)
          |> render_inertia("tasks/show")
        end
      end
      """)

    # Modules compiled in a test belong to no application: nothing to search.
    error = assert_raise PropsError, fn -> request(module, :show) end
    assert error.message =~ "has no declaration"

    assert request(MyAppWeb.DashboardController, :show).status == 200
  end

  test "a once prop that the client already has may be left out" do
    [{module, _}] =
      Code.compile_string("""
      defmodule Typelizer.InertiaPageTest.OnceController do
        use Phoenix.Controller, formats: [:json]
        use Typelizer.InertiaPage
        import Inertia.Controller

        page "plans", props: [plans: {:list, :string}]
        shared current_user: :any, locale: :string

        def show(conn, _params) do
          conn
          |> assign_prop(:plans, inertia_once(fn -> ["free"] end))
          |> render_inertia("plans")
        end
      end
      """)

    assert %{"plans" => ["free"]} = props(request(module, :show))

    conn = request(module, :show, %{}, [{"x-inertia-except-once-props", "plans"}])
    assert conn.status == 200
    refute Map.has_key?(props(conn), "plans")
  end

  test "responses that are not Inertia pages pass through" do
    conn =
      conn(:get, "/")
      |> ValidateProps.call(ValidateProps.init([]))
      |> send_resp(200, "ok")

    assert conn.resp_body == "ok"
  end

  test "a page rendered outside a controller is looked up nowhere" do
    conn =
      conn(:get, "/")
      |> ValidateProps.call([])
      |> put_private(:inertia_page, %{component: "tasks/index", props: %{}})

    assert_raise PropsError, ~r/has no declaration/, fn -> send_resp(conn, 200, "") end
  end

  describe "validate_inertia_props: :values" do
    setup do
      Application.put_env(:typelizer, :validate_inertia_props, :values)
    end

    test "serializer output renders" do
      assert request(MyAppWeb.TaskController, :show).status == 200
    end

    test "wrong values raise with a path" do
      message =
        assert_raise(PropsError, fn ->
          request(MyAppWeb.TaskController, :index, %{"bad" => "values"})
        end)
        |> Exception.message()

      assert message =~ ~s(  tasks[0]: missing key title)
      assert message =~ ~s(  tasks[0].status: expected "todo" | "doing" | "done", got "archived")
      assert message =~ ~s(  filters: expected Record<string, unknown>, got "x")
    end

    test "with validate_inertia_props: true, values are not checked" do
      Application.put_env(:typelizer, :validate_inertia_props, true)
      assert request(MyAppWeb.TaskController, :index, %{"bad" => "values"}).status == 200
    end
  end

  test "an unknown validate_inertia_props value raises" do
    Application.put_env(:typelizer, :validate_inertia_props, :value)

    assert_raise ArgumentError,
                 ~r/validate_inertia_props: must be false, true or :values, got: :value/,
                 fn ->
                   ValidateProps.call(conn(:get, "/"), [])
                 end
  end

  test "undeclared errors may hold nested error bags" do
    rendered = %{
      component: "dashboard",
      keys: ~w(currentUser locale errors flash stats recent),
      partial?: false,
      deferred: [],
      once: [],
      values: %{
        "currentUser" => nil,
        "locale" => "en",
        "errors" => %{"createTask" => %{"title" => "can't be blank"}},
        "flash" => %{},
        "stats" => nil,
        "recent" => []
      }
    }

    assert {:error, message} =
             Validation.check(
               rendered,
               MyAppWeb.DashboardController,
               [MyAppWeb.InertiaShared],
               :raise
             )

    refute message =~ "errors"
    assert message =~ "stats: expected a DashboardStats object, got nil"
  end

  test "the plug does nothing when validation is off" do
    Application.put_env(:typelizer, :validate_inertia_props, false)
    assert request(MyAppWeb.TaskController, :edit).status == 200
  end

  describe "declarations" do
    test "are compiled into __typelizer_pages__/0 and __typelizer_shared__/0" do
      assert [
               %{component: "tasks/archive", name: "TasksArchiveProps"},
               %{
                 component: "tasks/index",
                 name: "TasksIndexProps",
                 module: MyAppWeb.TaskController
               },
               %{component: "tasks/new", name: "NewTaskProps"},
               %{component: "tasks/show", name: "TasksShowProps", props: props}
             ] = MyAppWeb.TaskController.__typelizer_pages__()

      assert props == [
               {:task, "task", {:serializer, MyAppWeb.TaskSerializer}, false},
               {:can_edit, "canEdit", :boolean, false}
             ]

      assert MyAppWeb.TaskController.__typelizer_shared__() == nil

      assert [
               {:current_user, "currentUser", {:nullable, {:serializer, MyAppWeb.UserSerializer}},
                false}
               | _
             ] =
               MyAppWeb.InertiaShared.__typelizer_shared__()
    end

    defp compile_error(body) do
      source = """
      defmodule Typelizer.InertiaPageTest.M#{System.unique_integer([:positive])} do
        use Typelizer.InertiaPage
        #{body}
      end
      """

      error = assert_raise CompileError, fn -> Code.compile_string(source, "page.ex") end
      Exception.message(error)
    end

    test "invalid declarations are compile errors" do
      assert compile_error(~s(page "a", props: [x: :nope])) =~ ~s(page "a": x: unknown type :nope)
      assert compile_error(~s(page "a", [])) =~ ~s(page "a" needs props:)
      assert compile_error(~s(page "../a", props: [])) =~ "expects a component name"
      assert compile_error(~s(page "shared", props: [])) =~ "reserved"

      assert compile_error(~s(page "a", props: []\npage "a", props: [])) =~
               ~s(the page "a" is declared twice)

      assert compile_error(~s(page "a", props: [], nam: "X")) =~ "unknown option(s) [:nam]"

      assert compile_error(~s(page "a", props: [], name: "not valid")) =~
               "must be a TypeScript identifier"

      assert compile_error(~s(page "a", props: [x: :string, x: :integer])) =~
               "prop :x is declared twice"

      assert compile_error(~s(page "a", props: :map)) =~ "expected a keyword list"

      assert compile_error("shared a: :string\nshared b: :string") =~
               "shared props are declared twice"

      assert compile_error("shared a: {:enum, [1.5]}") =~ "shared: a: {:enum, values}"
    end
  end
end
