defmodule Typelizer.InertiaPage.Validation do
  @moduledoc false
  # Compares the top-level keys of a rendered Inertia page with its declaration.

  alias Typelizer.Discovery
  alias Typelizer.InertiaPage.ValueCheck

  @default_shared ["errors", "flash"]

  @type rendered :: %{
          optional(:values) => %{String.t() => term()},
          component: String.t(),
          keys: [String.t()],
          partial?: boolean(),
          deferred: [String.t()],
          once: [String.t()]
        }

  @doc """
  Checks a rendered page against the declarations found in `modules`. `first` is a
  module to look in first (the controller that rendered the page).
  """
  @spec check(rendered(), module() | nil, [module()], :raise | :ignore) ::
          :ok | {:error, String.t()}
  def check(rendered, first, modules, undeclared) do
    declared = Enum.filter([first | modules], &(is_atom(&1) and Discovery.page_module?(&1)))

    case find_page(declared, rendered.component) do
      nil when undeclared == :ignore ->
        :ok

      nil ->
        {:error,
         "Inertia page #{inspect(rendered.component)} has no declaration. Add " <>
           "page #{inspect(rendered.component)}, props: [...] to the controller " <>
           "(it needs use Typelizer.InertiaPage), or set " <>
           "config :typelizer, undeclared_inertia_pages: :ignore"}

      page ->
        compare(rendered, page, find_shared(declared))
    end
  end

  defp find_page(modules, component) do
    Enum.find_value(modules, fn module ->
      Enum.find(module.__typelizer_pages__(), &(&1.component == component))
    end)
  end

  defp find_shared(modules) do
    Enum.find_value(modules, [], & &1.__typelizer_shared__())
  end

  defp compare(rendered, page, shared) do
    props = shared ++ page.props
    declared = Enum.map(props, &elem(&1, 1)) ++ @default_shared
    required = for {_name, key, _spec, false} <- props, do: key
    present = rendered.keys

    missing =
      if rendered.partial? do
        []
      else
        (required -- present) -- rendered.once
      end

    deferred_required = Enum.filter(missing, &(&1 in rendered.deferred))
    missing = missing -- deferred_required
    extra = present -- declared

    problems =
      [
        list("missing", missing),
        list("deferred but not optional", deferred_required),
        list("not declared", extra)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.concat(value_problems(rendered, props))

    case problems do
      [] ->
        :ok

      problems ->
        {:error,
         "Inertia page #{inspect(page.component)} does not match its declaration in " <>
           "#{inspect(page.module)}:\n" <>
           Enum.join(problems, "\n") <> hints(missing, extra, deferred_required)}
    end
  end

  # With `validate_inertia_props: :values`, the values of the present props are
  # checked against their specs too. Undeclared `errors` and `flash` are only checked
  # to be maps: error bags nest one level deeper.
  defp value_problems(%{values: values}, props) when is_map(values) do
    declared = Enum.map(props, fn {_name, key, spec, _optional} -> {key, spec} end)

    defaults =
      for key <- @default_shared,
          not List.keymember?(declared, key, 0),
          do: {key, {:record, :unknown}}

    values
    |> ValueCheck.errors(declared ++ defaults)
    |> Enum.map(&("  " <> &1))
  end

  defp value_problems(_rendered, _props), do: []

  defp list(_label, []), do: nil
  defp list(label, keys), do: "  #{label}: #{Enum.join(Enum.sort(keys), ", ")}"

  defp hints(missing, extra, deferred) do
    [
      if Enum.any?(extra, &(String.contains?(&1, "_") and camelize(&1) in missing)) do
        "Hint: the keys are not camelCase. Set `config :inertia, camelize_props: true` " <>
          "or call camelize_props/1."
      end,
      if deferred != [] do
        "Hint: a deferred prop is not sent on the first load. Declare it as {:optional, spec}."
      end
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(&("\n" <> &1))
  end

  defp camelize(key), do: Typelizer.Naming.camelize(key)
end
