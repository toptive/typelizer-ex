defmodule Typelizer.TypeSpec do
  @moduledoc false
  # Normalizes the type specs that users write (see guides/serializers.md, "Type specs")
  # into one internal form. The runtime encoder and the TypeScript writer both read the
  # internal form, so the serialized value and its type always agree.
  #
  # Internal form:
  #
  #   :string | :number | :boolean | :map | :any | :unknown
  #   :temporal                       dates and times, ISO-8601 strings
  #   {:decimal, :string | :number}
  #   {:enum, [String.t() | integer()]}
  #   {:list, t} | {:record, t} | {:nullable, t}
  #   {:object, [prop]}               prop = {name, key, t, optional?}
  #   {:serializer, module}
  #   {:ts, String.t()}

  alias Typelizer.Naming

  @type ctx :: %{key_transform: :camel | :snake, decimal_type: :string | :number}
  @type prop :: {atom() | String.t(), String.t(), t(), boolean()}
  @type t ::
          :string
          | :number
          | :boolean
          | :map
          | :any
          | :unknown
          | :temporal
          | {:decimal, :string | :number}
          | {:enum, [String.t() | integer()]}
          | {:list, t()}
          | {:record, t()}
          | {:nullable, t()}
          | {:object, [prop()]}
          | {:serializer, module()}
          | {:ts, String.t()}

  @string [:string, :binary_id, :uuid, :binary]
  @number [:integer, :float, :number, :id]
  @temporal [
    :date,
    :time,
    :time_usec,
    :naive_datetime,
    :naive_datetime_usec,
    :utc_datetime,
    :utc_datetime_usec,
    :datetime,
    :datetime_usec
  ]

  @doc """
  Normalizes a user type spec. Raises `ArgumentError` with a hint when it is invalid.
  """
  @spec normalize!(term(), ctx()) :: t()
  def normalize!(spec, ctx) do
    case normalize(spec, ctx) do
      {:ok, normalized} -> normalized
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Normalizes a keyword list of props (page props, shared props, object fields).
  Each value may be wrapped in `{:optional, spec}`.
  """
  @spec normalize_props!(term(), ctx()) :: [prop()]
  def normalize_props!(props, ctx) do
    case normalize_props(props, ctx) do
      {:ok, normalized} -> normalized
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc false
  @spec normalize(term(), ctx()) :: {:ok, t()} | {:error, String.t()}
  def normalize(spec, _ctx) when spec in @string, do: {:ok, :string}
  def normalize(spec, _ctx) when spec in @number, do: {:ok, :number}
  def normalize(spec, _ctx) when spec in @temporal, do: {:ok, :temporal}
  def normalize(:boolean, _ctx), do: {:ok, :boolean}
  def normalize(:map, _ctx), do: {:ok, :map}
  def normalize(:any, _ctx), do: {:ok, :any}
  def normalize(:unknown, _ctx), do: {:ok, :unknown}
  def normalize(:decimal, ctx), do: {:ok, {:decimal, ctx.decimal_type}}

  def normalize({kind, inner}, ctx) when kind in [:list, :array] do
    with {:ok, spec} <- normalize(inner, ctx), do: {:ok, {:list, spec}}
  end

  def normalize({:map, inner}, ctx) do
    with {:ok, spec} <- normalize(inner, ctx), do: {:ok, {:record, spec}}
  end

  def normalize({:nullable, inner}, ctx) do
    with {:ok, spec} <- normalize(inner, ctx), do: {:ok, nullable(spec)}
  end

  def normalize({:enum, values}, _ctx) when is_list(values) and values != [] do
    if Enum.all?(values, &(is_atom(&1) or is_binary(&1) or is_integer(&1))) do
      {:ok, {:enum, Enum.map(values, &enum_value/1)}}
    else
      {:error, "{:enum, values} takes a non-empty list of atoms, strings or integers"}
    end
  end

  def normalize({:object, props}, ctx) do
    with {:ok, props} <- normalize_props(props, ctx), do: {:ok, {:object, props}}
  end

  def normalize({:ts, raw}, _ctx) when is_binary(raw), do: {:ok, {:ts, raw}}

  def normalize({:optional, _inner}, _ctx) do
    {:error,
     "{:optional, spec} is only allowed as a prop value (page props, shared props or " <>
       "{:object, ...} fields). For a value that can be null, use {:nullable, spec}"}
  end

  def normalize(module, _ctx) when is_atom(module) and module not in [nil, true, false] do
    if serializer_like?(module) do
      {:ok, {:serializer, module}}
    else
      {:error, "unknown type #{inspect(module)}. " <> hint()}
    end
  end

  def normalize(other, _ctx), do: {:error, "invalid type spec #{inspect(other)}. " <> hint()}

  @doc false
  @spec normalize_props(term(), ctx()) :: {:ok, [prop()]} | {:error, String.t()}
  def normalize_props(props, ctx) when is_list(props) do
    cond do
      not Keyword.keyword?(props) ->
        props_error(props)

      duplicate = duplicate_name(props) ->
        {:error, "prop #{inspect(duplicate)} is declared twice"}

      true ->
        normalize_each_prop(props, ctx, [])
    end
  end

  def normalize_props(props, _ctx), do: props_error(props)

  defp normalize_each_prop([], _ctx, acc), do: {:ok, Enum.reverse(acc)}

  defp normalize_each_prop([{name, spec} | rest], ctx, acc) do
    with {:ok, prop} <- normalize_prop(name, spec, ctx) do
      normalize_each_prop(rest, ctx, [prop | acc])
    end
  end

  defp normalize_prop(name, {:optional, inner}, ctx) do
    with {:ok, spec} <- normalize(inner, ctx) do
      {:ok, {name, Naming.key(name, ctx.key_transform), spec, true}}
    end
  end

  defp normalize_prop(name, spec, ctx) do
    case normalize(spec, ctx) do
      {:ok, spec} -> {:ok, {name, Naming.key(name, ctx.key_transform), spec, false}}
      {:error, message} -> {:error, "#{name}: #{message}"}
    end
  end

  defp duplicate_name(props) do
    names = Keyword.keys(props)

    case names -- Enum.uniq(names) do
      [] -> nil
      [name | _] -> name
    end
  end

  defp props_error(props) do
    {:error, "expected a keyword list of name: type spec, got: #{inspect(props)}"}
  end

  @doc """
  Wraps a spec in `{:nullable, _}` unless it already is.
  """
  @spec nullable(t()) :: t()
  def nullable({:nullable, _} = spec), do: spec
  def nullable(spec), do: {:nullable, spec}

  @doc """
  The serializer modules that a spec refers to.
  """
  @spec serializers(t()) :: [module()]
  def serializers({:serializer, module}), do: [module]
  def serializers({kind, inner}) when kind in [:list, :record, :nullable], do: serializers(inner)

  def serializers({:object, props}),
    do: Enum.flat_map(props, fn {_, _, s, _} -> serializers(s) end)

  def serializers(_spec), do: []

  @doc """
  True when the runtime encoder leaves values of this spec unchanged.
  """
  @spec passthrough?(t()) :: boolean()
  def passthrough?(spec) when spec in [:string, :number, :boolean, :map, :any, :unknown], do: true
  def passthrough?({:ts, _}), do: true

  def passthrough?({kind, inner}) when kind in [:list, :record, :nullable],
    do: passthrough?(inner)

  def passthrough?(_spec), do: false

  defp enum_value(value) when is_atom(value), do: Atom.to_string(value)
  defp enum_value(value), do: value

  defp serializer_like?(module) do
    case Atom.to_string(module) do
      "Elixir." <> _ -> true
      _ -> false
    end
  end

  defp hint do
    "Use a primitive (:string, :integer, :float, :boolean, :decimal, :date, :utc_datetime, " <>
      ":map, :any, :unknown), a serializer module, or {:list, t}, {:map, t}, {:enum, values}, " <>
      "{:nullable, t}, {:object, [key: t]} or {:ts, \"raw TypeScript\"}"
  end
end
