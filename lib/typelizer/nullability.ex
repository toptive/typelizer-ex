defmodule Typelizer.Nullability do
  @moduledoc false
  # Reads column nullability from PostgreSQL `information_schema.columns`.

  alias Ecto.Adapters.SQL
  alias Typelizer.GenerationError

  @type columns :: %{{String.t(), String.t(), String.t()} => boolean()}

  @doc """
  Returns `%{{schema, table, column} => nullable?}` for the given tables
  (`{prefix, table}` pairs; a nil prefix means `"public"`).
  """
  @spec fetch(module(), [{String.t() | nil, String.t()}]) :: columns()
  def fetch(_repo, []), do: %{}

  def fetch(repo, tables) do
    ensure_repo_started!(repo)

    {schemas, names} =
      tables |> Enum.map(fn {prefix, table} -> {prefix || "public", table} end) |> Enum.unzip()

    sql = """
    SELECT table_schema, table_name, column_name, is_nullable
    FROM information_schema.columns
    WHERE (table_schema, table_name) IN (SELECT * FROM unnest($1::text[], $2::text[]))
    """

    case SQL.query(repo, sql, [schemas, names], log: false) do
      {:ok, %{rows: rows}} ->
        Map.new(rows, fn [schema, table, column, nullable] ->
          {{schema, table, column}, nullable == "YES"}
        end)

      {:error, error} ->
        raise GenerationError,
              "could not read column nullability with #{inspect(repo)}: " <>
                Exception.message(error) <>
                ". Start the database, or remove config :typelizer, repo:"
    end
  end

  @doc "Resolves a field nullability rule to a boolean."
  @spec resolve(boolean() | tuple(), columns() | nil) :: boolean()
  def resolve(value, _columns) when is_boolean(value), do: value
  def resolve({:column, _prefix, _table, _column}, nil), do: true

  def resolve({:column, prefix, table, column}, columns) do
    Map.get(columns, {prefix || "public", table, column}, true)
  end

  defp ensure_repo_started!(repo) do
    unless Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) do
      raise GenerationError, "config :typelizer, repo: #{inspect(repo)} is not an Ecto repo"
    end

    unless repo.__adapter__() == Ecto.Adapters.Postgres do
      raise GenerationError,
            "config :typelizer, repo: only PostgreSQL repos are supported, " <>
              "#{inspect(repo)} uses #{inspect(repo.__adapter__())}"
    end

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:postgrex)

    case Process.whereis(repo) do
      nil -> start_repo!(repo)
      _pid -> :ok
    end
  end

  defp start_repo!(repo) do
    case repo.start_link(pool_size: 1, log: false) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, reason} ->
        raise GenerationError, "could not start #{inspect(repo)}: #{inspect(reason)}"
    end
  end
end
