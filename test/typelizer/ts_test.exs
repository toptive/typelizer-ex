defmodule Typelizer.TSTest do
  use ExUnit.Case, async: true

  alias Typelizer.TS

  describe "TS" do
    test "renders type specs" do
      name_of = fn MyAppWeb.UserSerializer -> "User" end

      assert TS.type({:list, {:nullable, :string}}, name_of) == "(string | null)[]"
      assert TS.type({:list, {:enum, ["a"]}}, name_of) == ~s("a"[])
      assert TS.type({:list, {:ts, "A | B", []}}, name_of) == "(A | B)[]"
      assert TS.type({:list, {:ts, "A|B", []}}, name_of) == "(A|B)[]"
      assert TS.type({:list, {:ts, "A&B", []}}, name_of) == "(A&B)[]"

      assert TS.type({:list, {:ts, "Array<[string, number]>", []}}, name_of) ==
               "Array<[string, number]>[]"

      assert TS.type({:union, [:string, {:serializer, MyAppWeb.UserSerializer}]}, name_of) ==
               "string | User"

      assert TS.type({:list, {:union, [:string, :number]}}, name_of) == "(string | number)[]"

      assert TS.type({:intersection, [{:union, [:string, :number]}, {:ts, "A | B", []}]}, name_of) ==
               "(string | number) & (A | B)"

      assert TS.type(
               {:union, [{:intersection, [:string, :number]}, {:enum, ["a", "b"]}]},
               name_of
             ) ==
               "(string & number) | \"a\" | \"b\""

      assert TS.type({:intersection, [{:nullable, :string}, {:enum, ["a", "b"]}]}, name_of) ==
               "(string | null) & (\"a\" | \"b\")"

      assert TS.type({:record, {:serializer, MyAppWeb.UserSerializer}}, name_of) ==
               "Record<string, User>"

      assert TS.type({:enum, [1, 2]}, name_of) == "1 | 2"
      assert TS.type({:object, []}, name_of) == "Record<string, never>"
      assert TS.type({:enum, [~s(a"b\\c)]}, name_of) == ~S("a\"b\\c")
      assert TS.type(:any, name_of) == "any"
      assert TS.type(:unknown, name_of) == "unknown"
    end

    test "quotes keys that are not identifiers" do
      assert TS.property_key("dueOn") == "dueOn"
      assert TS.property_key("due-on") == ~s("due-on")
      assert TS.property_key("1st") == ~s("1st")
    end

    test "relative paths" do
      assert TS.relative("/a/pages/tasks", "/a/serializers/Task") == "../../serializers/Task"
      assert TS.relative("/a/pages", "/a/pages/shared.props") == "./shared.props"
    end
  end

  test "export_list/3 wraps long lists, but never a single name" do
    long = "../../../very/long/directory/settings/profile-edit.props"

    assert TS.export_list("import type", ["SettingsProfileEditProps"], long) ==
             ~s(import type { SettingsProfileEditProps } from "#{long}";)

    assert TS.export_list("import type", ["A", "B"], long <> "/and/more") ==
             ~s(import type {\n  A,\n  B,\n} from "#{long}/and/more";)

    assert TS.export_list("export", ["a", "b"]) == "export { a, b };"
  end

  describe "naming" do
    doctest Typelizer.Naming

    test "camelize keeps leading underscores and single words" do
      assert Typelizer.Naming.camelize("_private_key") == "_privateKey"
      assert Typelizer.Naming.camelize("task") == "task"
      assert Typelizer.Naming.camelize("___") == "___"
    end
  end
end
