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
end

defmodule MyAppWeb.ProjectSerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Projects.Project

  attributes [:id, :name, :budget, :settings, :links]
  has_many :tasks, serializer: MyAppWeb.TaskSerializer
end

defmodule MyAppWeb.Admin.TaskSerializer do
  @moduledoc false
  use Typelizer.Serializer, schema: MyApp.Tasks.Task, key_transform: :snake

  attributes [:id, :title, :assignee_id, :updated_at]
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
  attribute :owner, type: {:nullable, MyAppWeb.UserSerializer}
end

defmodule MyApp.Tasks do
  @moduledoc false
  def overdue?(%{due_on: nil}), do: false

  def overdue?(%{due_on: due_on, status: status}),
    do: status != :done and Date.compare(due_on, ~D[2026-09-30]) == :lt
end
