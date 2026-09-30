defmodule MyAppWeb.UserSerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Accounts.User

  attributes [:id, :name, :role]
  attribute :nickname, type: {:nullable, :string}
end

defmodule MyAppWeb.CommentSerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Tasks.Comment

  attributes [:id, :body, :inserted_at]
  has_one :author, serializer: MyAppWeb.UserSerializer
  has_one :task, serializer: MyAppWeb.TaskSerializer, nullable: true
end

defmodule MyAppWeb.TaskSerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Tasks.Task

  attributes [:id, :status, :priority, :labels, :due_on, :estimate, :position]
  attribute :title, nullable: false
  attributes [:done_at, :metadata, :scores, :tags, :inserted_at]
  attribute :overdue, type: :boolean, value: &MyApp.Tasks.overdue?/1

  attribute :can_edit,
    type: :boolean,
    value: fn task, opts -> task.assignee_id == opts[:user_id] end

  attribute :summary, [type: :string], fn task -> "#{task.title} (#{task.status})" end
  attribute :due_label, type: {:nullable, :date}, value: & &1.due_on

  has_one :assignee, serializer: MyAppWeb.UserSerializer
  has_many :comments, serializer: MyAppWeb.CommentSerializer
  attribute :archived_note, type: :string, optional: true, value: & &1.metadata["archived_note"]

  attribute :internal_rank,
    type: {:nullable, :integer},
    if: fn _task, opts -> opts[:admin] end,
    value: & &1.position

  has_one :project, serializer: MyAppWeb.ProjectSerializer, if: &Ecto.assoc_loaded?(&1.project)

  has_many :watchers,
    serializer: MyAppWeb.UserSerializer,
    optional: true,
    value: & &1.metadata["watchers"]
end

defmodule MyAppWeb.ProjectSerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Projects.Project

  attributes [:id, :name, :budget, :settings, :links]
  attribute :address, required: [:street, :city, geo: [:lat, :lng]]
  attribute :price, required: :all
  has_many :tasks, serializer: MyAppWeb.TaskSerializer
end

defmodule MyAppWeb.Admin.TaskSerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Tasks.Task, key_transform: :snake

  attributes [:id, :title, :assignee_id, :updated_at]

  attribute :history_page,
    type: {:envelope, {:list, :string}, {:object, page_count: :integer}},
    value: fn task ->
      Typelizer.Envelope.wrap([task.title], [page_count: 1], key_transform: :snake)
    end
end

defmodule MyAppWeb.StatsSerializer do
  @moduledoc false
  use Typelizer.Serializer, name: "DashboardStats"

  attribute :open_count, type: :integer
  attribute :by_status, type: {:map, :integer}
  attribute :last_activity_at, type: {:nullable, :utc_datetime}

  attribute :window,
    type: {:object, from: :date, to: :date, label: {:optional, :string}}

  attribute :trend, type: {:list, {:enum, [:up, :down, :flat]}}
  attribute :raw, type: {:ts, "Array<[string, number]>"}
  attribute :mixed, type: {:list, {:ts, "string | number"}}
  attribute :subject, type: {:union, [MyAppWeb.UserSerializer, MyAppWeb.ProjectSerializer]}

  attribute :owner_card,
    type: {:ts, "Omit<User, \"role\"> & { online: boolean }", [MyAppWeb.UserSerializer]}

  attribute :reviewer,
    type: {:nullable, {:intersection, [MyAppWeb.UserSerializer, {:object, admin: :boolean}]}}

  attribute :history, type: {:list, {:union, [:string, {:enum, [1, 2]}]}}

  attribute :latest_users,
    type: {:envelope, {:list, MyAppWeb.UserSerializer}, {:object, generated_at: :utc_datetime}}

  attribute :owner, type: {:nullable, MyAppWeb.UserSerializer}
end

defmodule MyAppWeb.CategorySerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Catalog.Category

  attributes [:id, :name, :opens_at, :rates]
  has_one :parent, serializer: MyAppWeb.CategorySerializer
  has_many :children, serializer: MyAppWeb.CategorySerializer
  has_many :projects, serializer: MyAppWeb.ProjectSerializer
end

defmodule MyApp.Tasks do
  @moduledoc false
  def overdue?(%{due_on: nil}), do: false

  def overdue?(%{due_on: due_on, status: status}),
    do: status != :done and Date.compare(due_on, ~D[2026-09-30]) == :lt
end
