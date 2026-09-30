defmodule MyApp.Database do
  @moduledoc false
  # The fixture database: the DDL of the fixture schemas and the column nullability
  # that PostgreSQL reports for it. The golden files are generated with `columns/0`;
  # the PostgreSQL test checks that a real database reports the same map.

  @ddl [
    """
    CREATE TABLE users (
      id uuid PRIMARY KEY,
      name text NOT NULL,
      email text NOT NULL,
      role varchar(255) NOT NULL,
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """,
    """
    CREATE TABLE projects (
      id uuid PRIMARY KEY,
      name text NOT NULL,
      budget numeric,
      settings jsonb,
      links jsonb NOT NULL DEFAULT '[]',
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """,
    """
    CREATE TABLE tasks (
      id uuid PRIMARY KEY,
      title text,
      status varchar(255) NOT NULL,
      priority integer,
      labels varchar(255)[] NOT NULL,
      due_on date,
      estimate numeric,
      position integer NOT NULL,
      done_at timestamp(0),
      metadata jsonb NOT NULL,
      scores jsonb,
      tags text[] NOT NULL,
      assignee_id uuid REFERENCES users(id),
      project_id uuid NOT NULL REFERENCES projects(id),
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """,
    """
    CREATE TABLE comments (
      id bigserial PRIMARY KEY,
      body text NOT NULL,
      task_id uuid NOT NULL REFERENCES tasks(id),
      author_id uuid NOT NULL REFERENCES users(id),
      inserted_at timestamp(0) NOT NULL,
      updated_at timestamp(0) NOT NULL
    )
    """
  ]

  @nullable %{
    "users" => ~w(),
    "projects" => ~w(budget settings),
    "tasks" => ~w(title priority due_on estimate done_at scores assignee_id),
    "comments" => ~w()
  }

  @columns %{
    "users" => ~w(id name email role inserted_at updated_at),
    "projects" => ~w(id name budget settings links inserted_at updated_at),
    "tasks" =>
      ~w(id title status priority labels due_on estimate position done_at metadata scores tags
         assignee_id project_id inserted_at updated_at),
    "comments" => ~w(id body task_id author_id inserted_at updated_at)
  }

  def ddl, do: @ddl

  def tables, do: Enum.sort(Map.keys(@columns))

  def columns do
    for {table, columns} <- @columns, column <- columns, into: %{} do
      {{"public", table, column}, column in @nullable[table]}
    end
  end
end
