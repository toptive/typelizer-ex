defmodule Typelizer.Query do
  @moduledoc """
  Declares the query params of controller actions, so that the generated route
  helpers type their `query` option.

      defmodule MyAppWeb.TaskController do
        use MyAppWeb, :controller
        use Typelizer.Query

        query :index,
          page: {:optional, :integer},
          status: {:optional, {:enum, [:todo, :doing, :done]}},
          tags: {:optional, {:list, :string}}

        def index(conn, params), do: ...
      end

  ```ts
  routes.task.index({ query: { page: 2, status: "todo" } }); // ok
  routes.task.index({ query: { stauts: "todo" } });          // compile error
  ```

  Query keys stay as written (snake_case), because Phoenix reads them as written.
  Only types are generated: the controller still casts and validates `params`.
  Actions without a declaration keep `Record<string, unknown>`.

  A LiveView module can declare the query params of its live actions the same way.

  See the [Route helpers guide](routes.md#typed-query-params).
  """

  alias Typelizer.TypeSpec

  @doc false
  defmacro __using__(_opts) do
    decimal_type = Application.compile_env(__CALLER__, :typelizer, :decimal_type, :string)

    quote do
      import Typelizer.Query, only: [query: 2]
      Module.register_attribute(__MODULE__, :typelizer_queries, accumulate: true)
      @typelizer_query_ctx %{key_transform: :snake, decimal_type: unquote(decimal_type)}
      @before_compile Typelizer.Query
    end
  end

  @doc """
  Declares the query params of an action: a keyword list of param name → type spec.
  Wrap a spec in `{:optional, spec}` for a param that may be left out.
  """
  defmacro query(action, params) do
    quote do
      Typelizer.Query.__query__(__MODULE__, unquote(action), unquote(params), __ENV__)
    end
  end

  @doc false
  def __query__(module, action, params, env) do
    unless is_atom(action) and action not in [nil, true, false] do
      compile_error!(env, "query expects an action name (an atom), got: #{inspect(action)}")
    end

    queries = Module.get_attribute(module, :typelizer_queries)

    if Enum.any?(queries, fn {declared, _props, _line} -> declared == action end) do
      compile_error!(env, "query #{inspect(action)} is declared twice")
    end

    props =
      try do
        params
        |> dates_as_strings()
        |> TypeSpec.normalize_props!(Module.get_attribute(module, :typelizer_query_ctx))
      rescue
        error in ArgumentError ->
          compile_error!(env, "query #{inspect(action)}: " <> error.message)
      end

    if Enum.any?(props, fn {_, _, spec, _} -> TypeSpec.serializers(spec) != [] end) do
      compile_error!(
        env,
        "query #{inspect(action)}: query params cannot be serializers. Use primitives, " <>
          "enums, lists or objects"
      )
    end

    Module.put_attribute(module, :typelizer_queries, {action, props, env.line})
  end

  # A calendar date or a time of day is a plain string in a query: a JavaScript Date
  # holds an instant, and its ISO-8601 form is in UTC, which moves the date east of
  # UTC. Datetimes keep `string | Date`.
  defp dates_as_strings(spec) when spec in [:date, :time, :time_usec], do: :string

  defp dates_as_strings({tag, inner}) when tag in [:list, :array, :map, :nullable, :optional],
    do: {tag, dates_as_strings(inner)}

  defp dates_as_strings({tag, specs}) when tag in [:union, :intersection] and is_list(specs),
    do: {tag, Enum.map(specs, &dates_as_strings/1)}

  defp dates_as_strings({:object, props}), do: {:object, dates_as_strings(props)}

  defp dates_as_strings(props) when is_list(props) do
    if Keyword.keyword?(props),
      do: Enum.map(props, fn {key, spec} -> {key, dates_as_strings(spec)} end),
      else: props
  end

  defp dates_as_strings(spec), do: spec

  @doc false
  defmacro __before_compile__(env) do
    queries = Module.get_attribute(env.module, :typelizer_queries)
    # Live actions are not functions: a LiveView is not checked.
    live_view? = Phoenix.LiveView in List.wrap(Module.get_attribute(env.module, :behaviour))

    # Any arity counts: a controller may override action/2 to pass extra arguments.
    actions = for {name, _arity} <- Module.definitions_in(env.module, :def), do: name

    for {action, _props, line} <- queries, not live_view? and action not in actions do
      compile_error!(
        %{env | line: line},
        "query #{inspect(action)}: #{inspect(env.module)} has no public function #{action}"
      )
    end

    map = Map.new(queries, fn {action, props, _line} -> {action, props} end)

    quote do
      @doc false
      def __typelizer_queries__, do: unquote(Macro.escape(map))
    end
  end

  defp compile_error!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end
