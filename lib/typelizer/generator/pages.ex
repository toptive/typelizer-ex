defmodule Typelizer.Generator.Pages do
  @moduledoc false
  # One `<component>.props.ts` file per Inertia page, plus `shared.props.ts` and
  # `index.ts`.

  alias Typelizer.{GenerationError, Generator.Serializers, TS, TypeSpec}

  @default_shared [
    {:errors, "errors", {:record, :string}, false},
    {:flash, "flash", {:record, :string}, false}
  ]

  @doc """
  The generated files: `%{relative_path => content}`. `pages_dir` and
  `serializers_dir` are absolute; `serializers_dir` is nil when that output is off.
  """
  @spec files([module()], %{module() => String.t()}, String.t(), String.t() | nil) :: %{
          String.t() => String.t()
        }
  def files(modules, names, pages_dir, serializers_dir) do
    dirs = %{pages: pages_dir, serializers: serializers_dir}
    pages = pages(modules)
    {shared_module, shared} = shared(modules)
    check_names!(pages)

    page_files =
      Map.new(pages, fn page ->
        {page.component <> ".props.ts", page_file(page, names, dirs)}
      end)

    page_files
    |> Map.put("shared.props.ts", shared_file(shared_module, shared, names, dirs))
    |> Map.put("index.ts", index_file(pages))
  end

  defp pages(modules) do
    pages = modules |> Enum.flat_map(& &1.__typelizer_pages__()) |> Enum.sort_by(& &1.component)

    pages
    |> Enum.group_by(& &1.component)
    |> Enum.sort()
    |> Enum.each(fn
      {_component, [_]} ->
        :ok

      {component, duplicates} ->
        raise GenerationError,
              "the Inertia page #{inspect(component)} is declared in " <>
                "#{duplicates |> Enum.map(& &1.module) |> Enum.sort() |> Enum.map_join(" and ", &inspect/1)}. " <>
                "Declare each page once"
    end)

    pages
  end

  defp check_names!(pages) do
    pages
    |> Enum.group_by(& &1.name)
    |> Enum.sort()
    |> Enum.each(fn
      {_name, [_]} ->
        :ok

      {name, duplicates} ->
        raise GenerationError,
              "the Inertia pages #{duplicates |> Enum.map_join(" and ", &inspect(&1.component))} " <>
                "have the same TypeScript name #{inspect(name)}. Set name: in one page declaration"
    end)
  end

  defp shared(modules) do
    case Enum.filter(modules, & &1.__typelizer_shared__()) do
      [] ->
        {nil, @default_shared}

      [module] ->
        props = module.__typelizer_shared__()
        declared = Enum.map(props, &elem(&1, 1))
        defaults = Enum.reject(@default_shared, &(elem(&1, 1) in declared))
        {module, props ++ defaults}

      several ->
        raise GenerationError,
              "shared props are declared in #{Enum.map_join(several, " and ", &inspect/1)}. " <>
                "Declare them in one module"
    end
  end

  defp page_file(page, names, dirs) do
    dir = Path.expand(Path.dirname(page.component), dirs.pages)
    shared = TS.relative(dir, Path.join(dirs.pages, "shared.props"))
    name_of = Serializers.name_of(names, "page #{inspect(page.component)}")

    imports =
      serializer_imports(page.props, name_of, dir, dirs.serializers) ++
        [~s(import type { SharedProps } from "#{shared}";)]

    body =
      case page.props do
        [] ->
          "export interface #{page.name} extends SharedProps {}"

        props ->
          "export interface #{page.name} extends SharedProps {\n" <>
            TS.props(props, name_of, 1) <> "}"
      end

    TS.file(inspect(page.module), [Enum.join(imports, "\n"), body])
  end

  defp shared_file(module, props, names, dirs) do
    name_of = Serializers.name_of(names, "shared props")
    imports = serializer_imports(props, name_of, dirs.pages, dirs.serializers)
    body = "export interface SharedProps {\n" <> TS.props(props, name_of, 1) <> "}"
    TS.file(module && inspect(module), [Enum.join(imports, "\n"), body])
  end

  defp serializer_imports(props, name_of, dir, serializers_dir) do
    names =
      props
      |> Enum.flat_map(fn {_name, _key, spec, _optional} -> TypeSpec.serializers(spec) end)
      |> Enum.uniq()
      |> Enum.map(name_of)
      |> Enum.sort()

    if names != [] and is_nil(serializers_dir) do
      raise GenerationError,
            "Inertia props refer to serializers, but config :typelizer, output: [serializers: nil] " <>
              "turns the serializer output off"
    end

    Enum.map(names, fn name ->
      ~s(import type { #{name} } from "#{TS.relative(dir, Path.join(serializers_dir, name))}";)
    end)
  end

  defp index_file(pages) do
    entries =
      [{"SharedProps", "./shared.props"} | Enum.map(pages, &{&1.name, "./#{&1.component}.props"})]

    imports =
      Enum.map_join(entries, "\n", fn {name, path} ->
        ~s(import type { #{name} } from "#{path}";)
      end)

    exports = TS.export_list("export type", Enum.map(entries, &elem(&1, 0)))

    map =
      case pages do
        [] ->
          "export interface Pages {}"

        pages ->
          "export interface Pages {\n" <>
            Enum.map_join(pages, fn page ->
              "  #{TS.property_key(page.component)}: #{page.name};\n"
            end) <>
            "}"
      end

    TS.file(nil, [imports, exports, map])
  end
end
