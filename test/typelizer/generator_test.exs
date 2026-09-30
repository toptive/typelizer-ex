defmodule Typelizer.GeneratorTest do
  use ExUnit.Case, async: true

  alias Typelizer.{Config, GenerationError, Generator, TS}

  defp config(overrides) do
    Config.load(
      [app: :typelizer, root: System.tmp_dir!(), columns: %{}]
      |> Keyword.merge(overrides)
    )
  end

  defp files(overrides, kind) do
    overrides
    |> config()
    |> Generator.generate()
    |> Enum.find(&(&1.kind == kind))
    |> Map.get(:files)
  end

  describe "serializers" do
    test "explicit lists and type_names" do
      files =
        files(
          [
            serializers: [MyAppWeb.UserSerializer],
            type_names: %{MyAppWeb.UserSerializer => "Person"},
            output: [routes: nil, pages: nil]
          ],
          :serializers
        )

      assert Map.keys(files) == ["Person.ts", "index.ts"]
      assert files["Person.ts"] =~ "export interface Person {\n"
      assert files["index.ts"] =~ ~s(export type { Person } from "./Person";)
    end

    test "a serializer that is not in the explicit list" do
      message =
        ~r/MyAppWeb.CommentSerializer refers to MyAppWeb.TaskSerializer, which is not in config/

      assert_raise GenerationError, message, fn ->
        files(
          [
            serializers: [MyAppWeb.CommentSerializer, MyAppWeb.UserSerializer],
            output: [pages: nil]
          ],
          :serializers
        )
      end
    end

    test "a module that is not a serializer" do
      defmodule NotASerializer do
        use Typelizer.Serializer
        has_one :x, serializer: String
      end

      assert_raise GenerationError,
                   ~r/refers to String, which does not use Typelizer.Serializer/,
                   fn ->
                     files([serializers: [NotASerializer], output: [pages: nil]], :serializers)
                   end

      assert_raise GenerationError,
                   ~r/serializers: String does not use Typelizer.Serializer/,
                   fn ->
                     files([serializers: [String]], :serializers)
                   end
    end

    test "two serializers with the same name" do
      assert_raise GenerationError,
                   ~r/MyAppWeb.TaskSerializer and MyAppWeb.UserSerializer have the same TypeScript name "Task"/,
                   fn ->
                     files([type_names: %{MyAppWeb.UserSerializer => "Task"}], :serializers)
                   end
    end

    test "an empty serializer" do
      defmodule Empty do
        use Typelizer.Serializer, name: "Empty"
      end

      assert files([serializers: [Empty], output: [pages: nil]], :serializers)["Empty.ts"] =~
               "export interface Empty {}\n"
    end

    test "invalid config values" do
      assert_raise GenerationError, ~r/key_transform: must be one of/, fn ->
        config(key_transform: :kebab)
      end
    end
  end

  describe "router" do
    defmodule OtherRouter do
      use Phoenix.Router
      get "/users/:user_id/posts/:post_id", MyAppWeb.PageController, :show, as: :user_post
    end

    test "router discovery" do
      assert_raise GenerationError, ~r/router: String is not a Phoenix router/, fn ->
        files([router: String], :routes)
      end

      refute [router: false]
             |> config()
             |> Generator.generate()
             |> Enum.any?(&(&1.kind == :routes))

      assert files([router: OtherRouter], :routes)["userPost.ts"]
    end
  end

  describe "pages" do
    defmodule DuplicatePage do
      use Typelizer.InertiaPage
      page "tasks/index", props: []
    end

    defmodule SameName do
      use Typelizer.InertiaPage
      page "other", name: "TasksIndexProps", props: []
    end

    defmodule OtherShared do
      use Typelizer.InertiaPage
      shared locale: :string
    end

    defmodule OnlyPages do
      use Typelizer.InertiaPage
      page "home", props: [user: MyAppWeb.UserSerializer, errors: {:map, {:list, :string}}]
    end

    test "a page declared twice" do
      assert_raise GenerationError,
                   ~r/"tasks\/index" is declared in MyAppWeb.TaskController and .*DuplicatePage/,
                   fn ->
                     files([pages: [MyAppWeb.TaskController, DuplicatePage]], :pages)
                   end
    end

    test "two pages with the same TypeScript name" do
      assert_raise GenerationError, ~r/have the same TypeScript name "TasksIndexProps"/, fn ->
        files([pages: [MyAppWeb.TaskController, SameName]], :pages)
      end
    end

    test "shared props declared twice" do
      assert_raise GenerationError,
                   ~r/shared props are declared in MyAppWeb.InertiaShared and .*OtherShared/,
                   fn ->
                     files([pages: [OtherShared, MyAppWeb.InertiaShared]], :pages)
                   end
    end

    test "without shared props, SharedProps has errors and flash" do
      files = files([pages: [OnlyPages]], :pages)

      assert files["shared.props.ts"] ==
               TS.file(nil, [
                 "export interface SharedProps {\n  errors: Record<string, string>;\n  flash: Record<string, string>;\n}"
               ])

      assert files["home.props.ts"] =~ ~s(import type { User } from "../serializers/User";)
      assert files["home.props.ts"] =~ "  errors: Record<string, string[]>;\n"
    end

    test "pages that refer to serializers need the serializer output" do
      assert_raise GenerationError, ~r/output: \[serializers: nil\]/, fn ->
        files([pages: [OnlyPages], output: [serializers: nil]], :pages)
      end
    end

    test "explicit page lists and discovery without an application" do
      files = files([pages: [MyAppWeb.InertiaShared, MyAppWeb.TaskController]], :pages)
      assert files["shared.props.ts"] =~ "Source: MyAppWeb.InertiaShared"

      assert_raise GenerationError, ~r/no Mix application/, fn ->
        [app: nil] |> config() |> Generator.generate()
      end
    end

    test "no page modules, no pages output" do
      refute [pages: []] |> config() |> Generator.generate() |> Enum.any?(&(&1.kind == :pages))
    end

    test "a module that does not declare pages" do
      assert_raise GenerationError, ~r/pages: String does not use Typelizer.InertiaPage/, fn ->
        files([pages: [String]], :pages)
      end
    end
  end
end
