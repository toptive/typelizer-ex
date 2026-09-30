defmodule Typelizer.Discovery do
  @moduledoc false
  # Finds the modules that use the typelizer DSLs, and the Phoenix router.

  alias Typelizer.{Config, GenerationError}

  @doc "The serializer modules, sorted."
  @spec serializers(Config.t()) :: [module()]
  def serializers(%Config{serializers: :auto} = config) do
    config |> app_modules() |> Enum.filter(&serializer?/1)
  end

  def serializers(%Config{serializers: modules}) when is_list(modules) do
    Enum.each(modules, fn module ->
      unless serializer?(module) do
        raise GenerationError,
              "config :typelizer, serializers: #{inspect(module)} does not use Typelizer.Serializer"
      end
    end)

    Enum.sort(modules)
  end

  @doc "The modules that declare Inertia pages or shared props, sorted."
  @spec page_modules(Config.t()) :: [module()]
  def page_modules(%Config{pages: :auto} = config) do
    config |> app_modules() |> Enum.filter(&page_module?/1)
  end

  def page_modules(%Config{pages: modules}) when is_list(modules) do
    Enum.each(modules, fn module ->
      unless page_module?(module) do
        raise GenerationError,
              "config :typelizer, pages: #{inspect(module)} does not use Typelizer.InertiaPage"
      end
    end)

    Enum.sort(modules)
  end

  @doc "The router module, or nil when route helpers are off or there is no router."
  @spec router(Config.t()) :: module() | nil
  def router(%Config{router: false}), do: nil

  def router(%Config{router: :auto} = config) do
    case config |> app_modules() |> Enum.filter(&router?/1) do
      [] ->
        nil

      [router] ->
        router

      routers ->
        raise GenerationError,
              "found several routers: #{Enum.map_join(routers, ", ", &inspect/1)}. " <>
                "Choose one with config :typelizer, router: MyAppWeb.Router"
    end
  end

  def router(%Config{router: router}) do
    unless router?(router) do
      raise GenerationError,
            "config :typelizer, router: #{inspect(router)} is not a Phoenix router"
    end

    router
  end

  @doc "True when the module uses `Typelizer.Serializer`."
  @spec serializer?(module()) :: boolean()
  def serializer?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__typelizer__, 1) and
      function_exported?(module, :serialize, 2)
  end

  @doc "True when the module uses `Typelizer.InertiaPage`."
  @spec page_module?(module()) :: boolean()
  def page_module?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__typelizer_pages__, 0)
  end

  @doc "The modules of an OTP application, sorted. Loads the application when needed."
  @spec modules(atom()) :: [module()]
  def modules(app) do
    _ = Application.load(app)
    app |> Application.spec(:modules) |> List.wrap() |> Enum.sort()
  end

  defp router?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__routes__, 0)
  end

  defp app_modules(%Config{app: nil}) do
    raise GenerationError,
          "cannot discover modules: no Mix application. Set the module lists in config :typelizer"
  end

  defp app_modules(%Config{app: app}), do: modules(app)
end
