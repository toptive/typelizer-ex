defmodule Typelizer.InertiaPage.ValueCheckTest do
  use ExUnit.Case, async: true

  alias Typelizer.InertiaPage.ValueCheck
  alias Typelizer.TypeSpec

  @ctx %{key_transform: :camel, decimal_type: :string}

  defp check(value, spec), do: ValueCheck.check(value, TypeSpec.normalize!(spec, @ctx), "prop")

  test "primitives, as they are encoded to JSON" do
    assert check("a", :string) == []
    assert check(:atom, :string) == []
    assert check(1, :string) == ["prop: expected string, got 1"]
    assert check(true, :string) == ["prop: expected string, got true"]
    assert check(1.5, :float) == []
    assert check("1", :integer) == [~s(prop: expected number, got "1")]
    assert check(false, :boolean) == []
    assert check(%{}, :map) == []
    assert check([], :map) == ["prop: expected Record<string, unknown>, got []"]
    assert check(~D[2026-09-30], :date) == []
    assert check("2026-09-30", :utc_datetime) == []
    assert check(1, :date) == ["prop: expected string, got 1"]
    assert check(Decimal.new("1.5"), :decimal) == []
    assert check(1.5, :decimal) == ["prop: expected string, got 1.5"]
    assert check(1.5, {:ts, "whatever", []}) == []
    assert check(nil, :unknown) == []
  end

  test "nullability" do
    assert check(nil, {:nullable, :string}) == []
    assert check(nil, :string) == ["prop: expected string, got nil"]
  end

  test "enums, unions and intersections" do
    assert check(:todo, {:enum, [:todo, :done]}) == []
    assert check("done", {:enum, [:todo, :done]}) == []

    assert check("archived", {:enum, [:todo, :done]}) == [
             ~s(prop: expected "todo" | "done", got "archived")
           ]

    assert check(2, {:enum, [1, 2]}) == []
    assert check(1, {:union, [:string, :integer]}) == []

    assert check(true, {:union, [:string, :integer]}) == [
             "prop: expected string | number, got true"
           ]

    assert check(1, {:intersection, [:string, :integer]}) == []
  end

  test "lists, records and objects report a path" do
    assert check(["a", 1, "b", 2], {:list, :string}) == [
             "prop[1]: expected string, got 1",
             "prop[3]: expected string, got 2"
           ]

    assert check(%{"a" => 1, "b" => "x"}, {:map, :integer}) == [
             ~s(prop.b: expected number, got "x")
           ]

    object = {:object, due_on: :date, note: {:optional, :string}}
    assert check(%{dueOn: "2026-09-30"}, object) == []

    assert check(%{"dueOn" => 1, "note" => 2, "extra" => 3}, object) == [
             "prop.dueOn: expected string, got 1",
             "prop.note: expected string, got 2",
             "prop.extra: not declared"
           ]

    assert check(%{"due_on" => "2026-09-30"}, object) == ["prop: missing key dueOn (got due_on)"]
    assert check("x", object) == [~s(prop: expected an object, got "x")]
  end

  test "serializer output is checked field by field, nested serializers included" do
    user = %{"id" => "u1", "name" => "Ana", "role" => "admin", "nickname" => nil}
    assert check(user, MyAppWeb.UserSerializer) == []
    assert check([user], {:list, MyAppWeb.UserSerializer}) == []

    assert check(%{user | "role" => "owner"}, MyAppWeb.UserSerializer) ==
             [~s(prop.role: expected "member" | "admin", got "owner")]

    assert check(Map.delete(user, "name"), MyAppWeb.UserSerializer) == ["prop: missing key name"]

    assert ["prop: expected a User object, got %MyApp.Accounts.User{" <> _] =
             check(%MyApp.Accounts.User{}, MyAppWeb.UserSerializer)

    assert check(%{}, String) == ["prop: expected a String object, got %{}"]

    comment = %{
      "id" => 1,
      "body" => "Hi",
      "insertedAt" => "2026-09-30",
      "author" => %{user | "id" => 5},
      "task" => nil
    }

    assert check(comment, MyAppWeb.CommentSerializer) == [
             "prop.author.id: expected string, got 5"
           ]
  end

  test "optional serializer keys may be left out" do
    task =
      MyAppWeb.TaskSerializer.serialize(%MyApp.Tasks.Task{
        id: "t1",
        title: "T",
        status: :todo,
        inserted_at: ~U[2026-09-30 10:00:00Z],
        assignee: nil,
        comments: []
      })

    assert check(task, MyAppWeb.TaskSerializer) == []
    refute Map.has_key?(task, "archivedNote")
  end

  test "envelopes" do
    assert check(
             Typelizer.Envelope.paginated(["a"], page: 1, page_size: 10, total: 1),
             {:paginated, :string}
           ) == []

    assert check(Typelizer.Envelope.cursor_paginated(["a"]), {:cursor_paginated, :string}) == []
    assert check(Typelizer.Envelope.wrap([1], %{total: 1}), {:envelope, {:list, :integer}}) == []

    assert check(%{"data" => [1]}, {:paginated, :string}) == [
             "prop: missing key meta",
             "prop.data[0]: expected string, got 1"
           ]

    assert check(
             %{"data" => "x", "meta" => %{"n" => "y"}},
             {:envelope, :string, {:object, n: :integer}}
           ) ==
             [~s(prop.meta.n: expected number, got "y")]
  end

  test "errors/2 checks present props and stops after 20 errors" do
    assert ValueCheck.errors(%{"a" => 1}, [{"a", :string}, {"b", :string}]) == [
             "a: expected string, got 1"
           ]

    errors = ValueCheck.errors(%{"list" => Enum.to_list(1..25)}, [{"list", {:list, :string}}])
    assert length(errors) == 21
    assert List.last(errors) == "… and 5 more"
  end
end
