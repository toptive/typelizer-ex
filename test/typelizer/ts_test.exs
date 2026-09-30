defmodule Typelizer.TSTest do
  use ExUnit.Case, async: true

  alias Typelizer.TS

  describe "TS" do
    test "renders type specs" do
      name_of = fn MyAppWeb.UserSerializer -> "User" end

      assert TS.type({:list, {:nullable, :string}}, name_of) == "(string | null)[]"
      assert TS.type({:list, {:enum, ["a"]}}, name_of) == ~s("a"[])
      assert TS.type({:list, {:ts, "A | B"}}, name_of) == "(A | B)[]"

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

  describe "naming" do
    doctest Typelizer.Naming

    test "camelize keeps leading underscores and single words" do
      assert Typelizer.Naming.camelize("_private_key") == "_privateKey"
      assert Typelizer.Naming.camelize("task") == "task"
      assert Typelizer.Naming.camelize("___") == "___"
    end
  end
end
