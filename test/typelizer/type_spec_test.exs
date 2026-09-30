defmodule Typelizer.TypeSpecTest do
  use ExUnit.Case, async: true

  alias Typelizer.TypeSpec

  @ctx %{key_transform: :camel, decimal_type: :string}

  test "normalizes primitives and aliases" do
    for spec <- [:string, :binary_id, :uuid, :binary],
        do: assert(TypeSpec.normalize!(spec, @ctx) == :string)

    for spec <- [:integer, :float, :number, :id],
        do: assert(TypeSpec.normalize!(spec, @ctx) == :number)

    for spec <- [:date, :time, :time_usec, :naive_datetime, :utc_datetime_usec, :datetime],
        do: assert(TypeSpec.normalize!(spec, @ctx) == :temporal)

    assert TypeSpec.normalize!(:decimal, @ctx) == {:decimal, :string}
    assert TypeSpec.normalize!(:decimal, %{@ctx | decimal_type: :number}) == {:decimal, :number}
    assert TypeSpec.normalize!({:array, :id}, @ctx) == {:list, :number}
    assert TypeSpec.normalize!({:map, :boolean}, @ctx) == {:record, :boolean}
    assert TypeSpec.normalize!({:nullable, {:nullable, :map}}, @ctx) == {:nullable, :map}
    assert TypeSpec.normalize!({:enum, [:a, "b", 3]}, @ctx) == {:enum, ["a", "b", 3]}

    assert TypeSpec.normalize!(MyAppWeb.UserSerializer, @ctx) ==
             {:serializer, MyAppWeb.UserSerializer}
  end

  test "objects transform their keys and allow optional props" do
    assert TypeSpec.normalize!({:object, due_on: :date, note: {:optional, :string}}, @ctx) ==
             {:object, [{:due_on, "dueOn", :temporal, false}, {:note, "note", :string, true}]}

    assert TypeSpec.normalize!({:object, due_on: :date}, %{@ctx | key_transform: :snake}) ==
             {:object, [{:due_on, "due_on", :temporal, false}]}
  end

  test "rejects invalid specs with a hint" do
    for spec <- [
          nil,
          true,
          :nope,
          "string",
          {:list},
          {:enum, [1.5]},
          {:object, [1]},
          {:object, :map}
        ] do
      assert_raise ArgumentError, fn -> TypeSpec.normalize!(spec, @ctx) end
    end

    assert_raise ArgumentError, ~r/prop :a is declared twice/, fn ->
      TypeSpec.normalize_props!([a: :string, a: :string], @ctx)
    end

    assert_raise ArgumentError, ~r/b: unknown type :nope/, fn ->
      TypeSpec.normalize_props!([a: :string, b: :nope], @ctx)
    end

    assert_raise ArgumentError, ~r/expected a keyword list/, fn ->
      TypeSpec.normalize_props!(%{a: :string}, @ctx)
    end
  end

  test "serializers/1 finds every serializer a spec refers to" do
    spec =
      TypeSpec.normalize!(
        {:object,
         a: {:list, MyAppWeb.UserSerializer},
         b: {:union, [MyAppWeb.TaskSerializer, {:map, MyAppWeb.ProjectSerializer}]},
         c: {:ts, "X", [MyAppWeb.CommentSerializer]}},
        @ctx
      )

    assert TypeSpec.serializers(spec) == [
             MyAppWeb.UserSerializer,
             MyAppWeb.TaskSerializer,
             MyAppWeb.ProjectSerializer,
             MyAppWeb.CommentSerializer
           ]
  end

  test "passthrough?/1" do
    assert TypeSpec.passthrough?({:list, {:nullable, :string}})
    assert TypeSpec.passthrough?({:union, [:string, {:serializer, Foo}]})
    refute TypeSpec.passthrough?({:list, :temporal})
    refute TypeSpec.passthrough?({:serializer, Foo})
    refute TypeSpec.passthrough?({:object, []})
  end
end
