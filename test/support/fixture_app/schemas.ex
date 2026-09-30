defmodule MyApp.Repo do
  @moduledoc false
  use Ecto.Repo, otp_app: :typelizer, adapter: Ecto.Adapters.Postgres
end

defmodule MyApp.Accounts.User do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :name, :string
    field :email, :string
    field :role, Ecto.Enum, values: [:member, :admin]
    field :nickname, :string, virtual: true
    timestamps type: :utc_datetime
  end
end

defmodule MyApp.Tasks.Task do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tasks" do
    field :title, :string
    field :status, Ecto.Enum, values: [:todo, :doing, :done], default: :todo
    field :priority, Ecto.Enum, values: [low: 1, high: 2]
    field :labels, {:array, Ecto.Enum}, values: [:bug, :feature]
    field :due_on, :date
    field :estimate, :decimal
    field :position, :integer
    field :done_at, :naive_datetime
    field :metadata, :map
    field :scores, {:map, :integer}
    field :tags, {:array, :string}
    belongs_to :assignee, MyApp.Accounts.User
    belongs_to :project, MyApp.Projects.Project
    has_many :comments, MyApp.Tasks.Comment
    timestamps type: :utc_datetime
  end
end

defmodule MyApp.Tasks.Comment do
  @moduledoc false
  use Ecto.Schema

  schema "comments" do
    field :body, :string
    belongs_to :task, MyApp.Tasks.Task, type: :binary_id
    belongs_to :author, MyApp.Accounts.User, type: :binary_id
    timestamps type: :utc_datetime
  end
end

defmodule MyApp.Projects.Settings do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :theme, Ecto.Enum, values: [:light, :dark]
    field :notify_on_done, :boolean
  end
end

defmodule MyApp.Projects.Link do
  @moduledoc false
  use Ecto.Schema

  embedded_schema do
    field :url, :string
    field :label, :string
  end
end

defmodule MyApp.Projects.Geo do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :lat, :float
    field :lng, :float
  end
end

defmodule MyApp.Projects.Address do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :street, :string
    field :line2, :string
    field :city, :string
    embeds_one :geo, MyApp.Projects.Geo
  end
end

defmodule MyApp.Projects.Money do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field :amount, :integer
    field :currency, :string
  end
end

defmodule MyApp.Projects.Project do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "projects" do
    field :name, :string
    field :budget, :decimal
    embeds_one :settings, MyApp.Projects.Settings
    embeds_many :links, MyApp.Projects.Link
    embeds_one :address, MyApp.Projects.Address
    embeds_one :price, MyApp.Projects.Money
    has_many :tasks, MyApp.Tasks.Task
    timestamps type: :utc_datetime
  end
end
