defmodule Typelizer.EctoSchemaTest do
  use ExUnit.Case, async: true

  alias Typelizer.EctoSchema

  @ctx %{key_transform: :camel, decimal_type: :string}

  defmodule Upcase do
    use Ecto.ParameterizedType
    def type(_params), do: :string
    def init(opts), do: opts
    def cast(value, _params), do: {:ok, value}
    def load(value, _loader, _params), do: {:ok, value}
    def dump(value, _dumper, _params), do: {:ok, value}
  end

  defmodule Thing do
    use Ecto.Schema

    schema "things" do
      field :code, Upcase
      field :bits, :bitstring
      field :note, :string, virtual: true
      field :data, {:map, :decimal}
      many_to_many :categories, MyApp.Catalog.Category, join_through: "thing_categories"
      has_one :cover, MyApp.Projects.Project
    end
  end

  test "infers types, including parameterized custom types" do
    assert EctoSchema.describe(Thing, :code, :attribute, @ctx) ==
             {:field, :string, {:column, nil, "things", "code"}}

    assert EctoSchema.describe(Thing, :bits, :attribute, @ctx) ==
             {:field, :string, {:column, nil, "things", "bits"}}

    assert EctoSchema.describe(Thing, :note, :attribute, @ctx) == {:field, :string, true}

    assert {:field, {:record, {:decimal, :string}}, _} =
             EctoSchema.describe(Thing, :data, :attribute, @ctx)
  end

  test "describes associations" do
    assert EctoSchema.describe(Thing, :categories, :relation, @ctx) ==
             {:association, :many, false}

    assert EctoSchema.describe(Thing, :cover, :relation, @ctx) == {:association, :one, true}
  end

  test "reports unknown fields and types" do
    assert {:error, "Typelizer.EctoSchemaTest.Thing has no field :nope"} =
             EctoSchema.describe(Thing, :nope, :attribute, @ctx)

    assert {:error, message} = EctoSchema.infer({:tuple, :integer}, @ctx)
    assert message =~ "cannot map the Ecto type {:tuple, :integer}"
    assert {:error, _} = EctoSchema.infer({:parameterized, {String, %{}}}, @ctx)
    refute EctoSchema.schema?(String)
  end
end
