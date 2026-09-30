defmodule MyAppWeb.InertiaShared do
  @moduledoc false
  use Typelizer.InertiaPage

  shared current_user: {:nullable, MyAppWeb.UserSerializer}, locale: :string
end

defmodule MyAppWeb.TaskController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]
  use Typelizer.InertiaPage
  use Typelizer.Query
  import Inertia.Controller

  query(:index,
    page: {:optional, :integer},
    status: {:optional, {:enum, [:todo, :doing, :done]}},
    tags: {:optional, {:list, :string}},
    due_before: {:optional, :date},
    min_estimate: {:optional, :decimal},
    filter: {:optional, {:object, owner_id: :integer, archived: {:optional, :boolean}}},
    sort: {:optional, {:list, {:object, field: :string, dir: {:enum, [:asc, :desc]}}}}
  )

  query(:show, include: {:list, {:enum, [:comments, :assignee]}})
  query(:edit, [])

  page "tasks/index",
    props: [
      tasks: {:list, MyAppWeb.TaskSerializer},
      filters: :map,
      next_cursor: {:nullable, :string},
      stats: {:optional, {:object, open: :integer, done: :integer}}
    ]

  page "tasks/show", props: [task: MyAppWeb.TaskSerializer, can_edit: :boolean]

  page "tasks/new",
    name: "NewTaskProps",
    props: [
      statuses: {:list, {:enum, [:todo, :doing, :done]}},
      project: {:nullable, MyAppWeb.ProjectSerializer}
    ]

  def index(conn, params) do
    conn
    |> assign_prop(:tasks, [])
    |> assign_prop(:filters, %{})
    |> then(
      &if(params["next_cursor"] == "skip", do: &1, else: assign_prop(&1, :next_cursor, nil))
    )
    |> then(&if(params["extra"] == "send", do: assign_prop(&1, :extra, 1), else: &1))
    |> assign_stats(params)
    |> render_inertia("tasks/index")
  end

  def show(conn, _params) do
    conn
    |> assign_prop(:task, %{"id" => "t1"})
    |> assign_prop(:can_edit, true)
    |> render_inertia("tasks/show")
  end

  def edit(conn, _params), do: render_inertia(conn, "tasks/edit")

  defp assign_stats(conn, %{"stats" => "defer"}),
    do: assign_prop(conn, :stats, inertia_defer(fn -> %{open: 1, done: 2} end))

  defp assign_stats(conn, _params), do: conn
end

defmodule MyAppWeb.DashboardController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]
  use Typelizer.InertiaPage
  import Inertia.Controller

  page "dashboard",
    props: [stats: MyAppWeb.StatsSerializer, recent: {:list, MyAppWeb.Admin.TaskSerializer}]

  page "settings/profile-edit", props: []

  def show(conn, _params) do
    conn
    |> assign_prop(:stats, %{})
    |> assign_prop(:recent, [])
    |> render_inertia("dashboard")
  end
end
