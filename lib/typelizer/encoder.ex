defmodule Typelizer.Encoder do
  @moduledoc false
  # Turns Elixir values into JSON-ready values that match their TypeScript type.
  # Serializers call it only for fields whose spec is not a passthrough
  # (see `Typelizer.TypeSpec.passthrough?/1`).

  alias Typelizer.TypeSpec

  @doc "Encodes `value` according to the internal type spec."
  @spec encode(term(), TypeSpec.t(), keyword()) :: term()
  def encode(nil, _spec, _opts), do: nil
  def encode(value, :temporal, _opts), do: temporal(value)

  def encode(%{__struct__: Decimal} = value, {:decimal, :string}, _opts),
    do: decimal_string(value)

  def encode(%{__struct__: Decimal} = value, {:decimal, :number}, _opts), do: decimal_float(value)

  def encode(value, {:enum, _values}, _opts) when is_atom(value) and not is_boolean(value),
    do: Atom.to_string(value)

  def encode(value, {:nullable, spec}, opts), do: encode(value, spec, opts)

  def encode(values, {:list, spec}, opts) when is_list(values),
    do: Enum.map(values, &encode(&1, spec, opts))

  def encode(%{} = map, {:record, spec}, opts),
    do: Map.new(map, fn {key, value} -> {key, encode(value, spec, opts)} end)

  # An optional prop (`key?: T` in TypeScript) is left out when its value is nil.
  def encode(%{} = map, {:object, props}, opts) do
    Enum.reduce(props, %{}, fn {name, key, spec, optional}, acc ->
      case get(map, name) do
        nil when optional -> acc
        value -> Map.put(acc, key, encode(value, spec, opts))
      end
    end)
  end

  def encode(value, {:serializer, module}, opts), do: module.serialize(value, opts)
  def encode(value, _spec, _opts), do: value

  defp get(map, name) when is_atom(name) do
    case map do
      %{^name => value} -> value
      _ -> Map.get(map, Atom.to_string(name))
    end
  end

  defp get(map, name), do: Map.get(map, name)

  defp temporal(%Date{} = value), do: Date.to_iso8601(value)
  defp temporal(%Time{} = value), do: Time.to_iso8601(value)
  defp temporal(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp temporal(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp temporal(value), do: value

  # Decimal comes with Ecto, an optional dependency (see `xref` in mix.exs).
  defp decimal_string(value), do: Decimal.to_string(value, :normal)
  defp decimal_float(value), do: Decimal.to_float(value)
end
