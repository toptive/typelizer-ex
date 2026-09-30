defmodule Typelizer.Generator.Serializers do
  @moduledoc false
  # One `<Name>.ts` file per serializer, plus `index.ts`.

  alias Typelizer.{Config, GenerationError, TS, TypeSpec}

  @doc """
  Maps each serializer module to its interface name. Raises when two serializers
  have the same name.
  """
  @spec names(Config.t(), [module()]) :: %{module() => String.t()}
  def names(config, serializers) do
    names =
      Map.new(serializers, fn module ->
        {module, Map.get(config.type_names, module) || module.__typelizer__(:name)}
      end)

    names
    |> Enum.group_by(fn {_module, name} -> name end, fn {module, _name} -> module end)
    |> Enum.sort()
    |> Enum.each(fn
      {_name, [_]} ->
        :ok

      {name, modules} ->
        raise GenerationError,
              "#{modules |> Enum.sort() |> Enum.map_join(" and ", &inspect/1)} have the same " <>
                "TypeScript name #{inspect(name)}. Set name: in use Typelizer.Serializer " <>
                "or config :typelizer, type_names: %{...}"
    end)

    names
  end

  @doc """
  A function that returns the interface name of a serializer module referenced from
  `where`, or raises a clear error.
  """
  @spec name_of(%{module() => String.t()}, String.t()) :: (module() -> String.t())
  def name_of(names, where) do
    fn module ->
      case Map.fetch(names, module) do
        {:ok, name} ->
          name

        :error ->
          raise GenerationError, unknown_serializer_message(module, where)
      end
    end
  end

  defp unknown_serializer_message(module, where) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__typelizer__, 1) do
      "#{where} refers to #{inspect(module)}, which is not in config :typelizer, serializers: [...]. Add it"
    else
      "#{where} refers to #{inspect(module)}, which does not use Typelizer.Serializer"
    end
  end

  @doc "The generated files: `%{relative_path => content}`."
  @spec files([module()], %{module() => String.t()}, (term() -> boolean())) :: %{
          String.t() => String.t()
        }
  def files(serializers, names, nullable?) do
    interfaces =
      Map.new(serializers, fn module ->
        {"#{names[module]}.ts", interface_file(module, names, nullable?)}
      end)

    Map.put(interfaces, "index.ts", index_file(serializers, names))
  end

  defp interface_file(module, names, nullable?) do
    name = names[module]
    name_of = name_of(names, inspect(module))
    fields = module.__typelizer__(:fields)

    props =
      Enum.map(fields, fn field ->
        spec = if nullable?.(field.nullable), do: TypeSpec.nullable(field.spec), else: field.spec
        {field.key, spec, false}
      end)

    imports =
      fields
      |> Enum.flat_map(&TypeSpec.serializers(&1.spec))
      |> Enum.uniq()
      |> Enum.map(name_of)
      |> Enum.reject(&(&1 == name))
      |> Enum.sort()
      |> Enum.map_join("\n", &~s(import type { #{&1} } from "./#{&1}";))

    body =
      case props do
        [] -> "export interface #{name} {}"
        props -> "export interface #{name} {\n" <> TS.props(props, name_of, 1) <> "}"
      end

    TS.file(inspect(module), [imports, body])
  end

  defp index_file(serializers, names) do
    exports =
      serializers
      |> Enum.map(&names[&1])
      |> Enum.sort()
      |> Enum.map_join("\n", &~s(export type { #{&1} } from "./#{&1}";))

    TS.file(nil, [exports])
  end
end
