defmodule Typelizer.SerializerTest do
  use ExUnit.Case, async: true

  alias MyApp.Accounts.User
  alias MyApp.Projects.{Link, Project, Settings}
  alias MyApp.Tasks.{Comment, Task}
  alias MyAppWeb.{ProjectSerializer, StatsSerializer, TaskSerializer, UserSerializer}

  @user %User{id: "u1", name: "Ana", role: :admin, email: "ana@example.com"}

  defp task(attrs \\ []) do
    struct!(
      %Task{
        id: "t1",
        title: "Ship",
        status: :doing,
        priority: :high,
        labels: [:bug, :feature],
        due_on: ~D[2026-09-01],
        estimate: Decimal.new("12.50"),
        position: 3,
        done_at: ~N[2026-09-02 10:00:00],
        metadata: %{"source" => "api"},
        scores: %{"a" => 1},
        tags: ["x"],
        inserted_at: ~U[2026-09-30 10:00:00Z],
        assignee_id: "u1",
        assignee: @user,
        comments: []
      },
      attrs
    )
  end

  describe "serialize/2" do
    test "returns JSON-ready values under camelCase string keys, in declaration order" do
      assert TaskSerializer.serialize(task(), user_id: "u1") == %{
               "id" => "t1",
               "status" => "doing",
               "priority" => "high",
               "labels" => ["bug", "feature"],
               "dueOn" => "2026-09-01",
               "estimate" => "12.50",
               "position" => 3,
               "title" => "Ship",
               "doneAt" => "2026-09-02T10:00:00",
               "metadata" => %{"source" => "api"},
               "scores" => %{"a" => 1},
               "tags" => ["x"],
               "insertedAt" => "2026-09-30T10:00:00Z",
               "overdue" => true,
               "canEdit" => true,
               "summary" => "Ship (doing)",
               "dueLabel" => "2026-09-01",
               "assignee" => %{
                 "id" => "u1",
                 "name" => "Ana",
                 "role" => "admin",
                 "nickname" => nil
               },
               "comments" => []
             }
    end

    test "optional: leaves the key out when the value is nil" do
      refute Map.has_key?(TaskSerializer.serialize(task()), "archivedNote")
      refute Map.has_key?(TaskSerializer.serialize(task()), "watchers")

      serialized =
        TaskSerializer.serialize(
          task(metadata: %{"archived_note" => "old", "watchers" => [@user]})
        )

      assert %{"archivedNote" => "old", "watchers" => [%{"id" => "u1"}]} = serialized
      assert %{"watchers" => []} = TaskSerializer.serialize(task(metadata: %{"watchers" => []}))
    end

    test "if: adds the key only when the condition holds" do
      refute Map.has_key?(TaskSerializer.serialize(task()), "internalRank")
      assert %{"internalRank" => 3} = TaskSerializer.serialize(task(), admin: true)
      assert %{"internalRank" => nil} = TaskSerializer.serialize(task(position: nil), admin: true)
    end

    test "if: can guard an association that is not loaded" do
      refute Map.has_key?(TaskSerializer.serialize(task()), "project")

      project = %Project{id: "p1", name: "Launch", links: [], tasks: []}
      assert %{"project" => %{"id" => "p1"}} = TaskSerializer.serialize(task(project: project))
    end

    test "passes the options to arity-2 functions and nested serializers" do
      refute TaskSerializer.serialize(task(), user_id: "someone else")["canEdit"]
      refute TaskSerializer.serialize(task())["canEdit"]
    end

    test "keeps nil values" do
      serialized = TaskSerializer.serialize(task(due_on: nil, estimate: nil, assignee: nil))

      assert %{"dueOn" => nil, "estimate" => nil, "assignee" => nil, "overdue" => false} =
               serialized
    end

    test "returns nil for nil" do
      assert TaskSerializer.serialize(nil) == nil
    end

    test "serializes nested lists" do
      comment = %Comment{
        id: 1,
        body: "Hi",
        inserted_at: ~U[2026-09-30 10:00:00Z],
        author: @user,
        task: nil
      }

      assert %{"comments" => [%{"id" => 1, "author" => %{"name" => "Ana"}, "task" => nil}]} =
               TaskSerializer.serialize(task(comments: [comment]))
    end

    test "serializes embeds with transformed keys" do
      project = %Project{
        id: "p1",
        name: "Launch",
        budget: Decimal.new("1000"),
        settings: %Settings{theme: :dark, notify_on_done: true},
        links: [%Link{id: "l1", url: "https://example.com", label: nil}],
        address: %MyApp.Projects.Address{
          street: "Main St 1",
          city: "Springfield",
          geo: %MyApp.Projects.Geo{lat: 1.5, lng: 2.5}
        },
        price: %MyApp.Projects.Money{amount: 1200, currency: "EUR"},
        tasks: []
      }

      assert ProjectSerializer.serialize(project) == %{
               "id" => "p1",
               "name" => "Launch",
               "budget" => "1000",
               "settings" => %{"theme" => "dark", "notifyOnDone" => true},
               "links" => [%{"id" => "l1", "url" => "https://example.com", "label" => nil}],
               "address" => %{
                 "street" => "Main St 1",
                 "line2" => nil,
                 "city" => "Springfield",
                 "geo" => %{"lat" => 1.5, "lng" => 2.5}
               },
               "price" => %{"amount" => 1200, "currency" => "EUR"},
               "tasks" => []
             }

      assert %{"settings" => nil, "links" => []} =
               ProjectSerializer.serialize(%{project | settings: nil, links: []})
    end

    test "serializes plain maps with declared types" do
      stats = %{
        open_count: 2,
        by_status: %{"todo" => 2},
        last_activity_at: ~U[2026-09-30 10:00:00Z],
        window: %{from: ~D[2026-09-01], to: ~D[2026-09-30], label: nil},
        trend: [:up, :flat],
        raw: [["a", 1]],
        owner: @user,
        mixed: ["a", 1],
        subject: %{"id" => "p1"},
        owner_card: %{"id" => "u1", "online" => true},
        reviewer: nil,
        history: ["a", 2],
        latest_users: Typelizer.Envelope.wrap([], generated_at: "2026-09-30T10:00:00Z")
      }

      assert StatsSerializer.serialize(stats) == %{
               "openCount" => 2,
               "byStatus" => %{"todo" => 2},
               "lastActivityAt" => "2026-09-30T10:00:00Z",
               "window" => %{"from" => "2026-09-01", "to" => "2026-09-30"},
               "trend" => ["up", "flat"],
               "raw" => [["a", 1]],
               "owner" => %{"id" => "u1", "name" => "Ana", "role" => "admin", "nickname" => nil},
               "mixed" => ["a", 1],
               "subject" => %{"id" => "p1"},
               "ownerCard" => %{"id" => "u1", "online" => true},
               "reviewer" => nil,
               "history" => ["a", 2],
               "latestUsers" => %{
                 "data" => [],
                 "meta" => %{"generatedAt" => "2026-09-30T10:00:00Z"}
               }
             }

      assert %{"window" => %{"label" => "Q3"}} =
               StatsSerializer.serialize(%{
                 stats
                 | window: %{"from" => nil, "to" => nil, "label" => "Q3"}
               })
    end

    test "serialize_many/2 serializes a list" do
      assert [%{"id" => "u1"}, %{"id" => "u2"}] =
               UserSerializer.serialize_many([@user, %{@user | id: "u2"}])
    end

    test "serializes self references, many_to_many, times and decimal maps" do
      child = %MyApp.Catalog.Category{
        id: 2,
        name: "Child",
        rates: %{},
        parent: nil,
        children: [],
        projects: []
      }

      category = %MyApp.Catalog.Category{
        id: 1,
        name: "Root",
        opens_at: ~T[09:30:00],
        rates: %{"eur" => Decimal.new("1.10")},
        parent: nil,
        children: [child],
        projects: []
      }

      assert MyAppWeb.CategorySerializer.serialize(category) == %{
               "id" => 1,
               "name" => "Root",
               "opensAt" => "09:30:00",
               "rates" => %{"eur" => "1.10"},
               "parent" => nil,
               "children" => [
                 %{
                   "id" => 2,
                   "name" => "Child",
                   "opensAt" => nil,
                   "rates" => %{},
                   "parent" => nil,
                   "children" => [],
                   "projects" => []
                 }
               ],
               "projects" => []
             }
    end

    test "raises when a has_many association is not loaded" do
      assert_raise Typelizer.SerializationError,
                   ~r/the association :children is not loaded/,
                   fn ->
                     MyAppWeb.CategorySerializer.serialize(%MyApp.Catalog.Category{
                       id: 1,
                       parent: nil
                     })
                   end
    end

    test "a value: function whose arity is known only at runtime" do
      [{module, _}] =
        Code.compile_string("""
        defmodule Typelizer.SerializerTest.RuntimeArity do
          use Typelizer.Serializer
          attribute :one, type: :any, value: Enum.at([fn record -> record.a end], 0)
          attribute :two, type: :any, value: Enum.at([fn _record, opts -> opts[:b] end], 0)
          attribute :bad, type: :any, value: Enum.at([:not_a_function], 0), if: & &1[:bad?]
        end
        """)

      assert module.serialize(%{a: 1}, b: 2) == %{"one" => 1, "two" => 2}

      assert_raise Typelizer.SerializationError, ~r/value: must be a function of arity 1/, fn ->
        module.serialize(%{a: 1, bad?: true})
      end
    end

    test "raises when an association is not loaded" do
      message = ~r/MyAppWeb.TaskSerializer: the association :assignee is not loaded.*preload/i

      assert_raise Typelizer.SerializationError, message, fn ->
        TaskSerializer.serialize(%Task{id: "t1", status: :todo})
      end
    end

    test "raises when a field is missing" do
      assert_raise Typelizer.SerializationError, ~r/the record has no field :open_count/, fn ->
        StatsSerializer.serialize(%{})
      end

      assert_raise Typelizer.SerializationError, ~r/expects a struct or a map/, fn ->
        StatsSerializer.serialize("nope")
      end
    end

    test "decimal_type: :number serializes decimals as floats" do
      [{module, _}] =
        Code.compile_string("""
        defmodule Typelizer.SerializerTest.DecimalNumber do
          use Typelizer.Serializer
          attribute :amount, type: :decimal
        end
        """)

      assert module.serialize(%{amount: Decimal.new("1.5")}) == %{"amount" => "1.5"}

      Application.put_env(:typelizer, :decimal_type, :number)

      try do
        [{module, _}] =
          Code.compile_string("""
          defmodule Typelizer.SerializerTest.DecimalFloat do
            use Typelizer.Serializer
            attribute :amount, type: :decimal
          end
          """)

        assert module.serialize(%{amount: Decimal.new("1.5")}) == %{"amount" => 1.5}
        assert [%{spec: {:decimal, :number}}] = module.__typelizer__(:fields)
      after
        Application.delete_env(:typelizer, :decimal_type)
      end
    end
  end

  describe "__typelizer__/1" do
    test "returns the compiled metadata" do
      assert TaskSerializer.__typelizer__(:name) == "Task"
      assert TaskSerializer.__typelizer__(:schema) == Task
      assert TaskSerializer.__typelizer__(:key_transform) == :camel
      assert StatsSerializer.__typelizer__(:name) == "DashboardStats"
      assert MyAppWeb.Admin.TaskSerializer.__typelizer__(:name) == "AdminTask"
      assert MyAppWeb.Admin.TaskSerializer.__typelizer__(:key_transform) == :snake

      fields = TaskSerializer.__typelizer__(:fields)

      assert %{name: :title, key: "title", nullable: false, spec: :string} =
               Enum.find(fields, &(&1.name == :title))

      assert %{nullable: {:column, nil, "tasks", "assignee_id"}} =
               Enum.find(fields, &(&1.name == :assignee))

      assert %{
               nullable: false,
               optional: false,
               spec: {:list, {:serializer, MyAppWeb.CommentSerializer}}
             } =
               Enum.find(fields, &(&1.name == :comments))

      assert %{optional: true, nullable: false, spec: :string} =
               Enum.find(fields, &(&1.name == :archived_note))

      assert %{optional: true, spec: {:nullable, :number}} =
               Enum.find(fields, &(&1.name == :internal_rank))
    end
  end

  describe "snake_case keys" do
    test "key_transform: :snake keeps the names" do
      task = %Task{
        id: "t1",
        title: "Ship",
        assignee_id: "u1",
        updated_at: ~U[2026-09-30 10:00:00Z]
      }

      assert MyAppWeb.Admin.TaskSerializer.serialize(task) == %{
               "id" => "t1",
               "title" => "Ship",
               "assignee_id" => "u1",
               "updated_at" => "2026-09-30T10:00:00Z"
             }
    end
  end

  defmodule Point do
    use Ecto.Type
    def type, do: :point
    def cast(value), do: {:ok, value}
    def load(value), do: {:ok, value}
    def dump(value), do: {:ok, value}
  end

  describe "compile-time errors" do
    defp compile_error(body, opts \\ "schema: MyApp.Tasks.Task") do
      module = "Typelizer.SerializerTest.M#{System.unique_integer([:positive])}"

      source = """
      defmodule #{module} do
        use Typelizer.Serializer#{if opts != "", do: ", " <> opts}
        #{body}
      end
      """

      error = assert_raise CompileError, fn -> Code.compile_string(source, "serializer.ex") end
      Exception.message(error)
    end

    test "a computed attribute without type:" do
      assert compile_error("attribute :x, value: fn t -> t end") =~
               "a computed attribute must declare its TypeScript type"
    end

    test "value: or if: that is not written inline" do
      assert compile_error("opts = [if: & &1]\nattribute :title, opts") =~
               "if: must be written inline in the attribute call"
    end

    test "an attribute without schema and without type:" do
      assert compile_error("attribute :x", "") =~ "add type:"
      assert compile_error("attributes [:x]", "") =~ "add type:"
    end

    test "an unknown field" do
      message = compile_error("attributes [:id, :nope]")
      assert message =~ "MyApp.Tasks.Task has no field :nope"
      assert message =~ "serializer.ex:3"
    end

    test "an unknown field with an explicit type" do
      assert compile_error("attribute :nope, type: :string") =~ "has no field :nope"
    end

    test "an association in attributes" do
      assert compile_error("attributes [:assignee]") =~ "Use has_one :assignee, serializer: ..."
      assert compile_error("attribute :comments") =~ "Use has_many :comments"
    end

    test "has_one or has_many without serializer:" do
      assert compile_error("has_one :assignee, nullable: true") =~ "needs serializer:"
    end

    test "has_one on a list and has_many on a single value" do
      assert compile_error("has_one :comments, serializer: Foo") =~
               "Use has_many instead of has_one"

      assert compile_error("has_many :assignee, serializer: Foo") =~
               "Use has_one instead of has_many"
    end

    test "a relation that is not an association or an embed" do
      assert compile_error("has_one :title, serializer: Foo") =~
               "has no association or embed :title"
    end

    test "a field declared twice" do
      assert compile_error("attributes [:id]\nattribute :id") =~ "the field :id is declared twice"
    end

    test "an invalid type spec" do
      assert compile_error("attribute :x, type: :strng, value: & &1", "") =~ "unknown type :strng"

      assert compile_error("attribute :x, type: {:enum, []}, value: & &1", "") =~
               "{:enum, values}"

      assert compile_error("attribute :x, type: {:optional, :string}, value: & &1", "") =~
               "{:nullable, spec}"

      assert compile_error("attribute :x, type: {:union, [:string]}, value: & &1", "") =~
               "at least two"

      assert compile_error(
               "attribute :x, type: {:intersection, [:string, :nope]}, value: & &1",
               ""
             ) =~
               "unknown type :nope"

      assert compile_error(~s(attribute :x, type: {:ts, "A", [:a]}, value: & &1), "") =~
               "serializer modules"
    end

    test "an unknown option" do
      assert compile_error("attribute :title, typ: :string") =~ "unknown option(s) [:typ]"

      assert compile_error("has_many :comments, serializer: Foo, nullable: true") =~
               "unknown option(s) [:nullable]"
    end

    test "invalid required:" do
      project = "schema: MyApp.Projects.Project"

      assert compile_error("attribute :name, required: [:x]", project) =~
               "required: works only on an embed, and :name is not an embed"

      assert compile_error("attribute :address, required: [:zip]", project) =~
               "required: MyApp.Projects.Address has no field :zip. Its fields: [:street, :line2, :city, :geo]"

      assert compile_error("attribute :address, required: [street: [:x]]", project) =~
               "required: :street of MyApp.Projects.Address is not an embed"

      assert compile_error("attribute :address, required: [geo: [:alt]]", project) =~
               "MyApp.Projects.Geo has no field :alt"

      assert compile_error("attribute :address, required: true", project) =~
               "required: takes :all or a list of field names"

      assert compile_error("attribute :address, type: :map, required: [:street]", project) =~
               "Remove type: or required:"
    end

    test "a non-boolean nullable: or optional:" do
      assert compile_error("attribute :title, nullable: :yes") =~
               "nullable: must be true or false"

      assert compile_error("attribute :title, optional: 1") =~ "optional: must be true or false"
    end

    test "a schema that is not an Ecto schema" do
      assert compile_error("", "schema: String") =~ "schema: String is not an Ecto schema"
    end

    test "an invalid key_transform or name" do
      assert compile_error("", "key_transform: :kebab") =~
               "key_transform: must be one of [:camel, :snake]"

      assert compile_error("", ~s(name: "not valid")) =~
               "name: must be a valid TypeScript identifier"
    end

    test "an unknown Ecto type inside an embed" do
      defmodule Coordinates do
        use Ecto.Schema

        embedded_schema do
          field :point, Typelizer.SerializerTest.Point
        end
      end

      defmodule Place do
        use Ecto.Schema

        embedded_schema do
          embeds_one :coordinates, Coordinates
        end
      end

      message =
        compile_error("attributes [:coordinates]", "schema: Typelizer.SerializerTest.Place")

      assert message =~ "cannot map the Ecto type :point"

      assert message =~
               "(field :point of the embedded schema Typelizer.SerializerTest.Coordinates)"

      assert message =~ "Write a serializer for Typelizer.SerializerTest.Coordinates"
    end

    test "an unknown Ecto type" do
      defmodule Weird do
        use Ecto.Schema

        embedded_schema do
          field :point, {:array, Point}
        end
      end

      assert compile_error("attributes [:point]", "schema: Typelizer.SerializerTest.Weird") =~
               "cannot map the Ecto type"
    end
  end

  test "Ecto :any becomes unknown" do
    defmodule Anything do
      use Ecto.Schema

      embedded_schema do
        field :payload, :any, virtual: true
        field :data, {:map, :any}
      end
    end

    [{module, _}] =
      Code.compile_string("""
      defmodule Typelizer.SerializerTest.AnythingSerializer do
        use Typelizer.Serializer, schema: Typelizer.SerializerTest.Anything
        attributes [:payload, :data]
      end
      """)

    assert [%{spec: :unknown}, %{spec: {:record, :unknown}}] = module.__typelizer__(:fields)
  end

  test "a custom Ecto type is inferred from type/0" do
    defmodule Cents do
      use Ecto.Type
      def type, do: :integer
      def cast(value), do: {:ok, value}
      def load(value), do: {:ok, value}
      def dump(value), do: {:ok, value}
    end

    defmodule Order do
      use Ecto.Schema

      embedded_schema do
        field :total, Cents
        field :uuid, Ecto.UUID
      end
    end

    [{module, _}] =
      Code.compile_string("""
      defmodule Typelizer.SerializerTest.OrderSerializer do
        use Typelizer.Serializer, schema: Typelizer.SerializerTest.Order
        attributes [:id, :total, :uuid]
      end
      """)

    assert [
             %{name: :id, spec: :string, nullable: false},
             %{name: :total, spec: :number, nullable: true},
             %{name: :uuid, spec: :string, nullable: true}
           ] = module.__typelizer__(:fields)
  end
end
