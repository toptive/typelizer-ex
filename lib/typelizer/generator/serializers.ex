defmodule Typelizer.Generator.Serializers do
  @moduledoc false
  # One `<Name>.ts` file per serializer, plus `index.ts`.

  alias Typelizer.{Config, GenerationError, Naming, TS, TypeSpec}

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

  @envelope_types ~w(CursorMeta CursorPaginated Envelope Paginated PaginationMeta)

  @doc """
  The generated files: `%{relative_path => content}`. With `envelope: key_transform`,
  the shared `Envelope.ts` file is generated too.
  """
  @spec files([module()], %{module() => String.t()}, (term() -> boolean()), keyword()) :: %{
          String.t() => String.t()
        }
  def files(serializers, names, nullable?, opts \\ []) do
    envelope = Keyword.get(opts, :envelope)
    if envelope, do: check_envelope_names!(names)

    interfaces =
      Map.new(serializers, fn module ->
        {"#{names[module]}.ts", interface_file(module, names, nullable?)}
      end)

    interfaces
    |> Map.put("index.ts", index_file(serializers, names, envelope != nil))
    |> then(&if(envelope, do: Map.put(&1, "Envelope.ts", envelope_file(envelope)), else: &1))
  end

  @doc """
  The `import type` lines for the serializers and envelope types that `specs` use.
  `path_of` maps a file name (without extension) to a module specifier.
  """
  @spec import_lines([TypeSpec.t()], (module() -> String.t()), String.t() | nil, (String.t() ->
                                                                                    String.t())) ::
          [String.t()]
  def import_lines(specs, name_of, self, path_of) do
    serializers =
      specs
      |> Enum.flat_map(&TypeSpec.serializers/1)
      |> Enum.uniq()
      |> Enum.map(name_of)
      |> Enum.reject(&(&1 == self))
      |> Enum.uniq()
      |> Enum.map(&{path_of.(&1), [&1]})

    envelope = specs |> Enum.flat_map(&TypeSpec.envelopes/1) |> Enum.uniq() |> Enum.sort()

    entries =
      if envelope == [], do: serializers, else: [{path_of.("Envelope"), envelope} | serializers]

    entries
    |> Enum.sort()
    |> Enum.map(fn {path, names} ->
      TS.export_list("import type", names, path)
    end)
  end

  defp check_envelope_names!(names) do
    case Enum.filter(names, fn {_module, name} -> name in @envelope_types end) do
      [] ->
        :ok

      [{module, name} | _] ->
        raise GenerationError,
              "#{inspect(module)} has the TypeScript name #{inspect(name)}, which the envelope " <>
                "types use. Set name: in use Typelizer.Serializer"
    end
  end

  defp interface_file(module, names, nullable?) do
    name = names[module]
    name_of = name_of(names, inspect(module))
    fields = module.__typelizer__(:fields)

    props =
      Enum.map(fields, fn field ->
        spec = if nullable?.(field.nullable), do: TypeSpec.nullable(field.spec), else: field.spec
        {field.key, spec, field.optional}
      end)

    imports =
      fields
      |> Enum.map(& &1.spec)
      |> import_lines(name_of, name, &"./#{&1}")
      |> Enum.join("\n")

    body =
      case props do
        [] -> "export interface #{name} {}"
        props -> "export interface #{name} {\n" <> TS.props(props, name_of, 1) <> "}"
      end

    TS.file(inspect(module), [imports, body])
  end

  defp index_file(serializers, names, envelope?) do
    serializer_exports =
      Enum.map(serializers, &{names[&1], ~s(export type { #{names[&1]} } from "./#{names[&1]}";)})

    envelope_exports =
      if envelope?,
        do: [
          {"Envelope", TS.export_list("export type", @envelope_types, "./Envelope")}
        ],
        else: []

    exports =
      (serializer_exports ++ envelope_exports)
      |> Enum.sort()
      |> Enum.map_join("\n", &elem(&1, 1))

    TS.file(nil, [exports])
  end

  defp envelope_file(key_transform) do
    key = &Naming.key(&1, key_transform)

    TS.file(nil, [
      """
      /** Data wrapped in an envelope, with optional metadata. */
      export interface Envelope<T, M = Record<string, unknown>> {
        data: T;
        meta?: M;
      }

      export interface PaginationMeta {
        page: number;
        #{key.(:page_size)}: number;
        total: number;
        #{key.(:total_pages)}: number;
      }

      /** One page of a list, with page-based pagination metadata. */
      export interface Paginated<T> {
        data: T[];
        meta: PaginationMeta;
      }

      export interface CursorMeta {
        #{key.(:next_cursor)}: string | null;
        #{key.(:previous_cursor)}: string | null;
      }

      /** One page of a list, with cursor pagination metadata. */
      export interface CursorPaginated<T> {
        data: T[];
        meta: CursorMeta;
      }
      """
    ])
  end
end
