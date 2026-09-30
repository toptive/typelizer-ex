defmodule Typelizer.Envelope do
  @moduledoc """
  Wraps JSON-ready data in an envelope: `%{"data" => ..., "meta" => ...}`.

      json(conn, Typelizer.Envelope.wrap(MyAppWeb.TaskSerializer.serialize_many(tasks)))

      json(conn, Typelizer.Envelope.paginated(
        MyAppWeb.TaskSerializer.serialize_many(page.entries),
        page: page.page_number, page_size: page.page_size, total: page.total_entries
      ))

  The matching types are the specs `{:envelope, spec}`, `{:envelope, spec, meta_spec}`,
  `{:paginated, item_spec}` and `{:cursor_paginated, item_spec}`, which generate
  `Envelope<T, M>`, `Paginated<T>` and `CursorPaginated<T>` in TypeScript.

  The data is not changed: serialize it first. The keys of the meta map follow the key
  transform (`:camel` by default: `page_size` → `pageSize`).

  See the [Serializers guide](serializers.md#envelopes-and-pagination).
  """

  alias Typelizer.Naming

  @key_transform Application.compile_env(:typelizer, :key_transform, :camel)

  @typedoc "An envelope: `data`, and `meta` when there is one."
  @type t :: %{required(String.t()) => term()}

  @doc """
  Wraps data in an envelope. `meta` is optional; its keys follow the key transform, at
  every level.

      iex> Typelizer.Envelope.wrap([1, 2])
      %{"data" => [1, 2]}

      iex> Typelizer.Envelope.wrap([1, 2], %{generated_at: "2026-09-30", source_ids: [3]})
      %{"data" => [1, 2], "meta" => %{"generatedAt" => "2026-09-30", "sourceIds" => [3]}}
  """
  @spec wrap(term(), map() | keyword() | nil) :: t()
  def wrap(data, meta \\ nil)
  def wrap(data, nil), do: %{"data" => data}
  def wrap(data, meta) when is_list(meta), do: wrap(data, Map.new(meta))
  def wrap(data, %{} = meta), do: %{"data" => data, "meta" => transform_keys(meta)}

  @doc """
  Wraps one page of a list with page-based pagination metadata.

  Options (required): `:page` (1-based), `:page_size` and `:total` (the number of
  entries in all pages). `totalPages` is computed.

      iex> Typelizer.Envelope.paginated([%{"id" => 1}], page: 2, page_size: 10, total: 11)
      %{
        "data" => [%{"id" => 1}],
        "meta" => %{"page" => 2, "pageSize" => 10, "total" => 11, "totalPages" => 2}
      }
  """
  @spec paginated(list(), keyword() | map()) :: t()
  def paginated(entries, opts) when is_list(entries) do
    page = fetch_integer!(opts, :page, 1)
    page_size = fetch_integer!(opts, :page_size, 1)
    total = fetch_integer!(opts, :total, 0)

    wrap(entries,
      page: page,
      page_size: page_size,
      total: total,
      total_pages: div(total + page_size - 1, page_size)
    )
  end

  @doc """
  Wraps one page of a list with cursor pagination metadata.

  Options: `:next_cursor` and `:previous_cursor`, strings or `nil` (the default).

      iex> Typelizer.Envelope.cursor_paginated([], next_cursor: "g3Q")
      %{"data" => [], "meta" => %{"nextCursor" => "g3Q", "previousCursor" => nil}}
  """
  @spec cursor_paginated(list(), keyword() | map()) :: t()
  def cursor_paginated(entries, opts \\ []) when is_list(entries) do
    wrap(entries,
      next_cursor: fetch_cursor!(opts, :next_cursor),
      previous_cursor: fetch_cursor!(opts, :previous_cursor)
    )
  end

  defp fetch_integer!(opts, key, min) do
    case Access.get(opts, key) do
      value when is_integer(value) and value >= min ->
        value

      other ->
        raise ArgumentError,
              "Typelizer.Envelope.paginated/2 needs #{key}: an integer >= #{min}, got: #{inspect(other)}"
    end
  end

  defp fetch_cursor!(opts, key) do
    case Access.get(opts, key) do
      value when is_binary(value) or is_nil(value) ->
        value

      other ->
        raise ArgumentError,
              "Typelizer.Envelope.cursor_paginated/2 needs #{key}: a string or nil, got: #{inspect(other)}"
    end
  end

  defp transform_keys(%{__struct__: _} = struct), do: struct

  defp transform_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {Naming.key(key, @key_transform), transform_keys(value)} end)
  end

  defp transform_keys(list) when is_list(list), do: Enum.map(list, &transform_keys/1)
  defp transform_keys(value), do: value
end
