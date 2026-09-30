defmodule Typelizer.InertiaPage do
  @moduledoc """
  Declares the props of Inertia pages. `mix typelizer.gen` writes one TypeScript props
  interface per page component, and `Typelizer.InertiaPage.ValidateProps` checks the
  rendered props in dev and test.

      defmodule MyAppWeb.TaskController do
        use MyAppWeb, :controller
        use Typelizer.InertiaPage

        page "tasks/index",
          props: [
            tasks: {:list, MyAppWeb.TaskSerializer},
            filters: :map,
            stats: {:optional, {:object, open: :integer, done: :integer}}
          ]
      end

  Shared props (added to every page by a plug) are declared once, in one module:

      defmodule MyAppWeb.InertiaShared do
        use Typelizer.InertiaPage

        shared current_user: {:nullable, MyAppWeb.UserSerializer}, locale: :string
      end

  See the [Inertia guide](inertia.md).
  """

  alias Typelizer.{Naming, TypeSpec}

  @doc false
  defmacro __using__(_opts) do
    ctx = %{
      key_transform: Application.compile_env(__CALLER__, :typelizer, :key_transform, :camel),
      decimal_type: Application.compile_env(__CALLER__, :typelizer, :decimal_type, :string)
    }

    quote do
      import Typelizer.InertiaPage, only: [page: 2, shared: 1]
      Module.register_attribute(__MODULE__, :typelizer_pages, accumulate: true)
      @typelizer_ctx unquote(Macro.escape(ctx))
      @typelizer_shared nil
      @before_compile Typelizer.InertiaPage
    end
  end

  @doc """
  Declares the props of a page component.

  ## Options

    * `:props` - required. A keyword list of prop name → type spec. Wrap a spec in
      `{:optional, spec}` for a prop that is not always sent (for example a deferred prop).
    * `:name` - the TypeScript interface name. Default: the component in PascalCase plus
      `Props` (`"tasks/index"` → `TasksIndexProps`).
  """
  defmacro page(component, opts) do
    quote do
      Typelizer.InertiaPage.__page__(__MODULE__, unquote(component), unquote(opts), __ENV__)
    end
  end

  @doc """
  Declares the shared props: the props that a plug adds to every page. Only one module
  of the app may declare them. `errors` and `flash` are always included.
  """
  defmacro shared(props) do
    quote do
      Typelizer.InertiaPage.__shared__(__MODULE__, unquote(props), __ENV__)
    end
  end

  @doc false
  def __page__(module, component, opts, env) do
    ctx = Module.get_attribute(module, :typelizer_ctx)
    check_component!(env, component, Module.get_attribute(module, :typelizer_pages))
    check_page_opts!(env, component, opts)
    name = Keyword.get(opts, :name, Naming.pascalize(component) <> "Props")

    unless is_binary(name) and Naming.identifier?(name) do
      compile_error!(env, "page #{inspect(component)}: name: must be a TypeScript identifier")
    end

    props = normalize_props!(opts[:props], ctx, env, "page #{inspect(component)}")

    Module.put_attribute(module, :typelizer_pages, %{
      component: component,
      name: name,
      props: props,
      module: module
    })
  end

  defp check_component!(env, component, pages) do
    unless is_binary(component) and
             Regex.match?(~r{^[A-Za-z0-9_-]+(/[A-Za-z0-9_.-]+)*$}, component) do
      compile_error!(
        env,
        "page expects a component name such as \"tasks/index\", got: #{inspect(component)}"
      )
    end

    if component == "shared" do
      compile_error!(
        env,
        "the page component name \"shared\" is reserved for the shared props file"
      )
    end

    if Enum.any?(pages, &(&1.component == component)) do
      compile_error!(env, "the page #{inspect(component)} is declared twice")
    end
  end

  defp check_page_opts!(env, component, opts) do
    unless Keyword.keyword?(opts) and Keyword.has_key?(opts, :props) do
      compile_error!(env, "page #{inspect(component)} needs props: [name: type, ...]")
    end

    case Keyword.keys(opts) -- [:props, :name] do
      [] ->
        :ok

      unknown ->
        compile_error!(env, "page #{inspect(component)}: unknown option(s) #{inspect(unknown)}")
    end
  end

  @doc false
  def __shared__(module, props, env) do
    if Module.get_attribute(module, :typelizer_shared) do
      compile_error!(env, "shared props are declared twice in #{inspect(module)}")
    end

    ctx = Module.get_attribute(module, :typelizer_ctx)
    Module.put_attribute(module, :typelizer_shared, normalize_props!(props, ctx, env, "shared"))
  end

  defp normalize_props!(props, ctx, env, where) do
    TypeSpec.normalize_props!(props, ctx)
  rescue
    error in ArgumentError -> compile_error!(env, "#{where}: " <> error.message)
  end

  @doc false
  defmacro __before_compile__(env) do
    pages =
      env.module
      |> Module.get_attribute(:typelizer_pages)
      |> Enum.sort_by(& &1.component)

    shared = Module.get_attribute(env.module, :typelizer_shared)

    quote do
      @doc false
      def __typelizer_pages__, do: unquote(Macro.escape(pages))

      @doc false
      def __typelizer_shared__, do: unquote(Macro.escape(shared))
    end
  end

  defp compile_error!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end
