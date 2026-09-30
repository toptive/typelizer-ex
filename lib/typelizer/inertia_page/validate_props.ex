if Code.ensure_loaded?(Plug.Conn) do
  defmodule Typelizer.InertiaPage.ValidateProps do
    @moduledoc """
    A plug that checks, in dev and test, that each rendered Inertia page sends exactly
    the props declared with `Typelizer.InertiaPage.page/2`.

        # config/dev.exs and config/test.exs
        config :typelizer, validate_inertia_props: true

        # lib/my_app_web/router.ex
        pipeline :browser do
          # ...
          plug Inertia.Plug
          plug Typelizer.InertiaPage.ValidateProps
        end

    When a page renders, the plug compares the top-level keys of its props with the
    page props, the shared props, `errors` and `flash`:

      * a declared prop is missing and it is not `{:optional, _}` → error;
      * a deferred prop is declared without `{:optional, _}` → error;
      * a prop is present but not declared → error;
      * the component has no declaration → error, unless
        `config :typelizer, undeclared_inertia_pages: :ignore`.

    On a partial reload only undeclared props are reported. The error is a
    `Typelizer.InertiaPage.PropsError`, raised before the response is sent.

    With `validate_inertia_props: :values`, the plug also checks each present value
    against its declared type spec (types, enums, nullability, serializer fields,
    nested serializers) and reports each mismatch with a path such as
    `tasks[3].status`.

    With `validate_inertia_props: false` (the default) the plug does nothing. Both
    config keys are read at runtime.
    """

    @behaviour Plug

    alias Typelizer.{Discovery, InertiaPage.PropsError, InertiaPage.Validation}

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(conn, _opts) do
      if Application.get_env(:typelizer, :validate_inertia_props, false) in [true, :values] do
        Plug.Conn.register_before_send(conn, &validate/1)
      else
        conn
      end
    end

    defp validate(%Plug.Conn{private: %{inertia_page: page}} = conn) do
      controller = conn.private[:phoenix_controller]

      rendered = %{
        component: page.component,
        keys: Enum.map(Map.keys(page.props), &to_string/1),
        partial?: Map.get(page, :is_partial, false),
        deferred: page |> Map.get(:deferred_props, %{}) |> Map.values() |> List.flatten(),
        once: page |> Map.get(:once_props, %{}) |> Map.values() |> Enum.map(& &1["prop"])
      }

      rendered =
        if Application.get_env(:typelizer, :validate_inertia_props) == :values,
          do: Map.put(rendered, :values, Map.new(page.props, fn {k, v} -> {to_string(k), v} end)),
          else: rendered

      undeclared = Application.get_env(:typelizer, :undeclared_inertia_pages, :raise)

      case Validation.check(rendered, controller, app_modules(controller), undeclared) do
        :ok -> conn
        {:error, message} -> raise PropsError, message
      end
    end

    defp validate(conn), do: conn

    defp app_modules(nil), do: []

    defp app_modules(controller) do
      case Application.get_application(controller) do
        nil -> []
        app -> Discovery.modules(app)
      end
    end
  end
end
