defmodule Typelizer.QueryTest do
  use ExUnit.Case, async: true

  alias Typelizer.GenerationError
  alias Typelizer.Generator.Routes

  @all %{include: [], exclude: [], defaults: []}

  test "declarations are compiled into __typelizer_queries__/0" do
    queries = MyAppWeb.TaskController.__typelizer_queries__()

    assert queries[:edit] == []

    assert [{:include, "include", {:list, {:enum, ["comments", "assignee"]}}, false}] =
             queries[:show]

    assert {:due_before, "due_before", :string, true} =
             List.keyfind(queries[:index], :due_before, 0)

    assert {:updated_after, _, :temporal, true} = List.keyfind(queries[:index], :updated_after, 0)
  end

  defp compile_error(body, prelude \\ "use Phoenix.Controller, formats: [:json]") do
    source = """
    defmodule Typelizer.QueryTest.M#{System.unique_integer([:positive])} do
      #{prelude}
      use Typelizer.Query
      #{body}
      def index(conn, _params), do: conn
    end
    """

    error = assert_raise CompileError, fn -> Code.compile_string(source, "query.ex") end
    Exception.message(error)
  end

  test "dates and times inside lists, objects and unions are strings; datetimes are not" do
    [{module, _}] =
      Code.compile_string("""
      defmodule Typelizer.QueryTest.Dates do
        use Phoenix.Controller, formats: [:json]
        use Typelizer.Query

        query :index,
          days: {:list, :date},
          window: {:optional, {:object, from: :date, at: {:nullable, :time}, until: :naive_datetime}},
          either: {:union, [:date, :integer]}

        def index(conn, _params), do: conn
      end
      """)

    assert [
             {:days, _, {:list, :string}, false},
             {:window, _,
              {:object,
               [
                 {:from, _, :string, _},
                 {:at, _, {:nullable, :string}, _},
                 {:until, _, :temporal, _}
               ]}, true},
             {:either, _, {:union, [:string, :number]}, false}
           ] = module.__typelizer_queries__()[:index]
  end

  test "invalid declarations are compile errors" do
    assert compile_error("query :index, page: :nope") =~ "query :index: page: unknown type :nope"
    assert compile_error("query :index, []\nquery :index, []") =~ "query :index is declared twice"
    assert compile_error(~s(query "index", [])) =~ "query expects an action name"
    assert compile_error("query :index, user: MyAppWeb.UserSerializer") =~ "cannot be serializers"

    message = compile_error("query :indx, []")
    assert message =~ "has no action indx/2"
    assert message =~ "query.ex:4"
  end

  test "a LiveView may declare its live actions" do
    [{module, _}] =
      Code.compile_string("""
      defmodule Typelizer.QueryTest.BoardLive do
        use Phoenix.LiveView
        use Typelizer.Query
        query :edit, tab: {:optional, :string}
        def render(assigns), do: ~H"<div></div>"
      end
      """)

    defmodule LiveRouter do
      use Phoenix.Router
      import Phoenix.LiveView.Router
      live "/board/:id/edit", Typelizer.QueryTest.BoardLive, :edit
    end

    files = Routes.files(LiveRouter, @all, :camel)
    assert module.__typelizer_queries__()[:edit]
    assert files["board.ts"] =~ "export type BoardEditQuery = {\n  tab?: string;\n};"
    assert files["board.ts"] =~ "options?: RouteOptions<BoardEditQuery>,"
  end

  test "a declaration for an action without a route fails the generation" do
    defmodule PartialRouter do
      use Phoenix.Router
      get "/tasks", MyAppWeb.TaskController, :index
    end

    assert_raise GenerationError,
                 ~r/MyAppWeb.TaskController declares query :edit, but no route points to MyAppWeb.TaskController.edit/,
                 fn -> Routes.files(PartialRouter, @all, :camel) end
  end

  test "controllers that the router does not use are not checked" do
    defmodule OtherRouter do
      use Phoenix.Router
      get "/", MyAppWeb.PageController, :home
    end

    assert Routes.files(OtherRouter, @all, :camel)["page.ts"]
  end
end
