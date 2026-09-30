# Controllers and plugs that the fixture router points to. They do nothing.
for module <- [
      MyAppWeb.PageController,
      MyAppWeb.CommentController,
      MyAppWeb.FileController,
      MyAppWeb.Api.V1.ProjectController,
      MyAppWeb.Api.V1.MemberController,
      MyAppWeb.HealthController,
      MyAppWeb.MailboxPlug
    ] do
  defmodule module do
    @moduledoc false
    def init(opts), do: opts
    def call(conn, _opts), do: conn
  end
end

defmodule MyAppWeb.BoardLive do
  @moduledoc false
  use Phoenix.LiveView

  def render(assigns), do: ~H"<div></div>"
end
