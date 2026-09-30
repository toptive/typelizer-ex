defmodule Typelizer.EctoSchema do
  @moduledoc false
  # Reads Ecto schema reflection (`__schema__/1,2`) and infers type specs.
  # It only calls the reflection functions of the user's schemas, so typelizer
  # compiles without Ecto.

  alias Typelizer.{Naming, TypeSpec}

  @typedoc """
  How the nullability of a field is decided at generation time:
  `true`/`false`, or a database column to look up when a repo is configured.
  """
  @type nullability :: boolean() | {:column, String.t() | nil, String.t(), String.t()}

  @direct %{
    :id => :number,
    :integer => :number,
    :float => :number,
    :boolean => :boolean,
    :string => :string,
    :binary => :string,
    :binary_id => :string,
    :bitstring => :string,
    :map => :map,
    # Ecto :any holds any term: `unknown` makes TypeScript check it before use.
    :any => :unknown,
    :date => :temporal,
    :time => :temporal,
    :time_usec => :temporal,
    :naive_datetime => :temporal,
    :naive_datetime_usec => :temporal,
    :utc_datetime => :temporal,
    :utc_datetime_usec => :temporal
  }

  @doc "True when `module` is an Ecto schema or embedded schema."
  @spec schema?(module()) :: boolean()
  def schema?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
      function_exported?(module, :__schema__, 2)
  end

  @doc """
  Describes a schema field:

    * `{:field, spec, nullability}` for a regular or virtual field (embeds included,
      as nested objects);
    * `{:association, :one | :many, nullability}` for an association;
    * `{:embed, :one | :many, nullability}` for an embed (used by `has_one`/`has_many`);
    * `{:error, message}` when the field does not exist or its type is unknown.

  `as` is `:attribute` or `:relation`: an embed is a field for `:attribute` and an
  `{:embed, ...}` for `:relation`.
  """
  @spec describe(module(), atom(), :attribute | :relation, TypeSpec.ctx()) ::
          {:field, TypeSpec.t(), nullability()}
          | {:association | :embed, :one | :many, nullability()}
          | {:error, String.t()}
  def describe(schema, field, as, ctx) do
    cond do
      association = schema.__schema__(:association, field) ->
        {:association, association.cardinality, association_nullability(schema, association)}

      as == :relation and embed(schema, field) != nil ->
        {cardinality, _related} = embed(schema, field)
        {:embed, cardinality, column(schema, field)}

      type = schema.__schema__(:type, field) ->
        with {:ok, spec} <- infer(type, ctx) do
          {:field, spec, field_nullability(schema, field)}
        end

      type = virtual_type(schema, field) ->
        with {:ok, spec} <- infer(type, ctx), do: {:field, spec, true}

      true ->
        {:error, "#{inspect(schema)} has no field #{inspect(field)}"}
    end
  end

  @doc "Infers the internal type spec of an Ecto type."
  @spec infer(term(), TypeSpec.ctx()) :: {:ok, TypeSpec.t()} | {:error, String.t()}
  def infer(type, _ctx) when is_map_key(@direct, type), do: {:ok, Map.fetch!(@direct, type)}
  def infer(:decimal, ctx), do: {:ok, {:decimal, ctx.decimal_type}}
  def infer(Ecto.UUID, _ctx), do: {:ok, :string}

  def infer({:array, inner}, ctx) do
    with {:ok, spec} <- infer(inner, ctx), do: {:ok, {:list, spec}}
  end

  def infer({:map, inner}, ctx) do
    with {:ok, spec} <- infer(inner, ctx), do: {:ok, {:record, spec}}
  end

  # Ecto >= 3.12 uses {:parameterized, {module, params}}; older versions use a 3-tuple.
  def infer({:parameterized, {module, params}}, ctx), do: parameterized(module, params, ctx)
  def infer({:parameterized, module, params}, ctx), do: parameterized(module, params, ctx)

  def infer(module, ctx) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :type, 0) do
      infer(module.type(), ctx)
    else
      unknown(module)
    end
  end

  def infer(other, _ctx), do: unknown(other)

  defp parameterized(Ecto.Enum, %{mappings: mappings}, _ctx) do
    {:ok, {:enum, Enum.map(mappings, fn {value, _dumped} -> Atom.to_string(value) end)}}
  end

  defp parameterized(Ecto.Embedded, %{cardinality: cardinality, related: related}, ctx) do
    with {:ok, props} <- embed_props(related, ctx) do
      object = {:object, props}
      {:ok, if(cardinality == :many, do: {:list, object}, else: object)}
    end
  end

  defp parameterized(module, params, ctx) do
    if Code.ensure_loaded?(module) and function_exported?(module, :type, 1) do
      infer(module.type(params), ctx)
    else
      unknown(module)
    end
  end

  defp unknown(type) do
    {:error, "typelizer cannot map the Ecto type #{inspect(type)} to TypeScript"}
  end

  # Every field of an embedded schema, in declaration order. Only the primary key is
  # not nullable: embeds have no database column to read.
  defp embed_props(related, ctx) do
    embed_props(related, related.__schema__(:fields), ctx, [])
  end

  defp embed_props(_related, [], _ctx, acc), do: {:ok, Enum.reverse(acc)}

  defp embed_props(related, [field | rest], ctx, acc) do
    case infer(related.__schema__(:type, field), ctx) do
      {:ok, spec} ->
        primary_key? = field in related.__schema__(:primary_key)
        spec = if primary_key?, do: spec, else: TypeSpec.nullable(spec)
        prop = {field, Naming.key(field, ctx.key_transform), spec, false}
        embed_props(related, rest, ctx, [prop | acc])

      {:error, message} ->
        {:error, embed_error(related, field, message)}
    end
  end

  defp embed_error(related, field, message) do
    "#{message} (field #{inspect(field)} of the embedded schema #{inspect(related)}). " <>
      "Write a serializer for #{inspect(related)} and use has_one or has_many, " <>
      "or declare this attribute with type: and value:"
  end

  defp field_nullability(schema, field) do
    if field in schema.__schema__(:primary_key) or field in autogenerated(schema) do
      false
    else
      column(schema, field)
    end
  end

  defp association_nullability(schema, %{relationship: :parent, owner_key: owner_key}),
    do: column(schema, owner_key)

  defp association_nullability(_schema, %{cardinality: :many}), do: false
  defp association_nullability(_schema, _association), do: true

  defp column(schema, field) do
    case schema.__schema__(:source) do
      nil ->
        true

      source ->
        {:column, schema.__schema__(:prefix), source,
         Atom.to_string(schema.__schema__(:field_source, field))}
    end
  end

  defp autogenerated(schema) do
    schema.__schema__(:autogenerate_fields)
  rescue
    _ -> []
  end

  defp embed(schema, field) do
    case schema.__schema__(:embed, field) do
      %{cardinality: cardinality, related: related} -> {cardinality, related}
      nil -> nil
    end
  end

  defp virtual_type(schema, field) do
    schema.__schema__(:virtual_type, field)
  rescue
    _ -> nil
  end
end
