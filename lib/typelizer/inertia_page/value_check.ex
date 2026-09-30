defmodule Typelizer.InertiaPage.ValueCheck do
  @moduledoc false
  # Checks a rendered prop value against its declared type spec, in dev and test
  # (`config :typelizer, validate_inertia_props: :values`). Values are checked as they
  # will be encoded to JSON: atoms count as strings, dates and decimals as strings.

  alias Typelizer.{Naming, TS}

  @max_errors 20

  @doc """
  Returns the mismatches of the props (`%{key => value}`) with their specs
  (`[{key, spec}]`), as lines such as `tasks[3].status: expected "todo" | "done", got "x"`.
  At most #{@max_errors} lines, plus a line with the number of the others.
  """
  @spec errors(%{String.t() => term()}, [{String.t(), term()}]) :: [String.t()]
  def errors(values, specs) do
    errors =
      Enum.flat_map(specs, fn {key, spec} ->
        case Map.fetch(values, key) do
          {:ok, value} -> check(value, spec, key)
          :error -> []
        end
      end)

    case Enum.split(errors, @max_errors) do
      {shown, []} -> shown
      {shown, hidden} -> shown ++ ["… and #{length(hidden)} more"]
    end
  end

  @doc false
  @spec check(term(), term(), String.t()) :: [String.t()]
  def check(value, spec, path)

  def check(_value, spec, _path) when spec in [:any, :unknown], do: []
  def check(_value, {:ts, _raw, _modules}, _path), do: []
  def check(_value, {:intersection, _specs}, _path), do: []
  def check(nil, {:nullable, _spec}, _path), do: []
  def check(value, {:nullable, spec}, path), do: check(value, spec, path)
  def check(nil, spec, path), do: [mismatch(path, spec, nil)]

  def check(value, :string, path) do
    if is_binary(value) or (is_atom(value) and not is_boolean(value)),
      do: [],
      else: [mismatch(path, :string, value)]
  end

  def check(value, :number, path), do: expect(is_number(value), path, :number, value)
  def check(value, :boolean, path), do: expect(is_boolean(value), path, :boolean, value)
  def check(value, :map, path), do: expect(is_map(value), path, :map, value)

  def check(value, :temporal, path),
    do: expect(is_binary(value) or temporal?(value), path, :temporal, value)

  def check(value, {:decimal, :string} = spec, path),
    do: expect(is_binary(value) or decimal?(value), path, spec, value)

  def check(value, {:decimal, :number} = spec, path),
    do: expect(is_number(value), path, spec, value)

  def check(value, {:enum, values} = spec, path) do
    normalized =
      if is_atom(value) and not is_boolean(value), do: Atom.to_string(value), else: value

    expect(normalized in values, path, spec, value)
  end

  def check(value, {:union, specs} = spec, path) do
    if Enum.any?(specs, &(check(value, &1, path) == [])),
      do: [],
      else: [mismatch(path, spec, value)]
  end

  def check(values, {:list, spec}, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} -> check(value, spec, "#{path}[#{index}]") end)
  end

  def check(%{} = map, {:record, spec}, path) when not is_struct(map) do
    Enum.flat_map(map, fn {key, value} -> check(value, spec, "#{path}.#{key}") end)
  end

  def check(%{} = map, {:object, props}, path) when not is_struct(map) do
    fields = for {_name, key, spec, optional} <- props, do: {key, spec, not optional, false}
    check_fields(map, fields, path)
  end

  def check(%{} = map, {:serializer, module} = spec, path) when not is_struct(map) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__typelizer__, 1) do
      fields =
        for field <- module.__typelizer__(:fields),
            do:
              {field.key, field.spec, not Map.get(field, :optional, false),
               field.nullable != false}

      check_fields(map, fields, path)
    else
      [mismatch(path, spec, map)]
    end
  end

  def check(%{} = map, {:envelope, data, meta}, path) when not is_struct(map) do
    meta_fields = if meta, do: [{"meta", meta, false, false}], else: []
    check_fields(map, [{"data", data, true, false} | meta_fields], path, false)
  end

  def check(%{} = map, {kind, item}, path)
      when kind in [:paginated, :cursor_paginated] and not is_struct(map) do
    meta = {:object, Enum.map(meta_keys(kind), fn {key, spec} -> {key, key, spec, false} end)}
    check_fields(map, [{"data", {:list, item}, true, false}, {"meta", meta, true, false}], path)
  end

  def check(value, spec, path), do: [mismatch(path, spec, value)]

  # A field is `{key, spec, required?, nullable?}`. Keys may be atoms or strings (the
  # value is not encoded yet).
  defp check_fields(map, fields, path, strict? \\ true) do
    map = Map.new(map, fn {key, value} -> {to_string(key), value} end)
    {missing_errors, twins} = missing_keys(map, fields, path)
    extra_errors = if strict?, do: extra_keys(map, fields, twins, path), else: []
    missing_errors ++ field_values(map, fields, path) ++ extra_errors
  end

  # A missing camelCase key with its snake_case twin present is one problem, not two.
  defp missing_keys(map, fields, path) do
    missing = for {key, _spec, true, _nullable} <- fields, not Map.has_key?(map, key), do: key

    Enum.map_reduce(missing, [], fn key, twins ->
      case Enum.find(Map.keys(map), &(&1 != key and Naming.camelize(&1) == key)) do
        nil -> {"#{path}: missing key #{key}", twins}
        twin -> {"#{path}: missing key #{key} (got #{twin})", [twin | twins]}
      end
    end)
  end

  defp extra_keys(map, fields, twins, path) do
    declared = Enum.map(fields, &elem(&1, 0))

    for key <- Enum.sort(Map.keys(map)),
        key not in declared and key not in twins,
        do: "#{path}.#{key}: not declared"
  end

  defp field_values(map, fields, path) do
    Enum.flat_map(fields, fn {key, spec, _required, nullable} ->
      case Map.fetch(map, key) do
        {:ok, nil} when nullable -> []
        {:ok, value} -> check(value, spec, "#{path}.#{key}")
        :error -> []
      end
    end)
  end

  defp meta_keys(:paginated) do
    for key <- [:page, :page_size, :total, :total_pages], do: {meta_key(key), :number}
  end

  defp meta_keys(:cursor_paginated) do
    for key <- [:next_cursor, :previous_cursor], do: {meta_key(key), {:nullable, :string}}
  end

  defp meta_key(key), do: Naming.key(key, Application.get_env(:typelizer, :key_transform, :camel))

  defp expect(true, _path, _spec, _value), do: []
  defp expect(false, path, spec, value), do: [mismatch(path, spec, value)]

  defp mismatch(path, spec, value) do
    "#{path}: expected #{describe(spec)}, got #{inspect(value, limit: 5, printable_limit: 40)}"
  end

  defp describe({:serializer, module}), do: "a #{serializer_name(module)} object"

  defp describe(spec) do
    rendered = TS.type(spec, &serializer_name/1)
    if String.contains?(rendered, "\n"), do: "an object", else: rendered
  end

  defp serializer_name(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__typelizer__, 1),
      do: module.__typelizer__(:name),
      else: inspect(module)
  end

  defp temporal?(%struct{}) when struct in [Date, Time, NaiveDateTime, DateTime], do: true
  defp temporal?(_value), do: false

  defp decimal?(%{__struct__: Decimal}), do: true
  defp decimal?(_value), do: false
end
