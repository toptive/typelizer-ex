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
        TypeSpec.normalize_props!(params, Module.get_attribute(module, :typelizer_query_ctx))
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

  @doc false
  defmacro __before_compile__(env) do
    queries = Module.get_attribute(env.module, :typelizer_queries)
    # Live actions are not functions: a LiveView is not checked.
    live_view? = Phoenix.LiveView in List.wrap(Module.get_attribute(env.module, :behaviour))

    for {action, _props, line} <- queries,
        not live_view? and not Module.defines?(env.module, {action, 2}) do
      compile_error!(
        %{env | line: line},
        "query #{inspect(action)}: #{inspect(env.module)} has no action #{action}/2"
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
