defmodule MyAppWeb.Router do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", MyAppWeb do
    pipe_through(:browser)

    get("/", PageController, :home)
    get("/about", PageController, :about)

    resources "/tasks", TaskController do
      resources("/comments", CommentController, only: [:index, :create])
    end

    get("/files/*path", FileController, :show)
    live("/board", BoardLive)
    live("/board/:id/edit", BoardLive, :edit)
  end

  scope "/api/v1", MyAppWeb.Api.V1, as: :api_v1 do
    resources("/projects", ProjectController, only: [:index, :show, :update])
    get("/projects/:project_id/members/:member_id", MemberController, :show)
    options("/projects", ProjectController, :options)
  end

  scope "/dev" do
    forward("/mailbox", MyAppWeb.MailboxPlug)
    get("/health", MyAppWeb.HealthController, :show)
  end
end
