defmodule Typelizer.Generator do
  @moduledoc false
  # Builds every generated file in memory. `Typelizer.Output` writes or compares them.

  alias Typelizer.{Config, Discovery, Nullability}
  alias Typelizer.Generator.{Pages, Routes, Serializers}

  @type output :: %{kind: atom(), dir: String.t(), files: %{String.t() => String.t()}}

  @doc "Returns one entry per enabled output: its absolute directory and its files."
  @spec generate(Config.t()) :: [output()]
  def generate(%Config{} = config) do
    serializers_dir = Config.output_dir(config, :serializers)
    routes_dir = Config.output_dir(config, :routes)
    pages_dir = Config.output_dir(config, :pages)

    page_modules = if pages_dir, do: Discovery.page_modules(config), else: []

    serializers =
      if serializers_dir || page_modules != [], do: Discovery.serializers(config), else: []

    names = Serializers.names(config, serializers)
    router = if routes_dir, do: Discovery.router(config)

    [
      serializers_dir &&
        %{
          kind: :serializers,
          dir: serializers_dir,
          files: Serializers.files(serializers, names, nullable_fun(config, serializers))
        },
      router &&
        %{
          kind: :routes,
          dir: routes_dir,
          files: Routes.files(router, config.routes, config.key_transform)
        },
      page_modules != [] &&
        %{
          kind: :pages,
          dir: pages_dir,
          files: Pages.files(page_modules, names, pages_dir, serializers_dir)
        }
    ]
    |> Enum.filter(& &1)
  end

  defp nullable_fun(config, serializers) do
    columns = columns(config, serializers)
    &Nullability.resolve(&1, columns)
  end

  defp columns(%Config{columns: columns}, _serializers) when is_map(columns), do: columns
  defp columns(%Config{repo: nil}, _serializers), do: nil

  defp columns(%Config{repo: repo}, serializers) do
    tables =
      for module <- serializers,
          %{nullable: {:column, prefix, table, _column}} <- module.__typelizer__(:fields),
          uniq: true,
          do: {prefix, table}

    Nullability.fetch(repo, Enum.sort(tables))
  end
end
