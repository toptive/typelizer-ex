defmodule Typelizer.NullabilityTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.{Postgres, SQL}
  alias Typelizer.{Config, Generator, Golden, Nullability}

  describe "resolve/2" do
    test "booleans are final" do
      refute Nullability.resolve(false, nil)
      assert Nullability.resolve(true, %{})
    end

    test "a column is nullable when no database was read" do
      assert Nullability.resolve({:column, nil, "tasks", "title"}, nil)
    end

    test "a column follows the database; an unknown column is nullable" do
      columns = %{{"public", "tasks", "title"} => false, {"app", "tasks", "title"} => true}

      refute Nullability.resolve({:column, nil, "tasks", "title"}, columns)
      assert Nullability.resolve({:column, "app", "tasks", "title"}, columns)
      assert Nullability.resolve({:column, nil, "tasks", "missing"}, columns)
    end
  end

  test "without a repo every inferred field except the primary key and timestamps is nullable" do
    config = %{Golden.config(System.tmp_dir!()) | columns: nil}
    [serializers | _] = Generator.generate(config)
    task = serializers.files["Task.ts"]

    assert task =~ "  id: string;\n"
    assert task =~ "  status: \"todo\" | \"doing\" | \"done\" | null;\n"
    assert task =~ "  position: number | null;\n"
    assert task =~ "  title: string;\n"
    assert task =~ "  insertedAt: string;\n"
    assert task =~ "  overdue: boolean;\n"
    assert task =~ "  comments: Comment[];\n"
  end

  describe "PostgreSQL" do
    @describetag :postgres

    setup do
      repo_config = Application.fetch_env!(:typelizer, MyApp.Repo)
      _ = Postgres.storage_down(repo_config)
      :ok = Postgres.storage_up(repo_config)
      {:ok, _} = Application.ensure_all_started(:postgrex)
      {:ok, _} = Application.ensure_all_started(:ecto_sql)
      {:ok, pid} = MyApp.Repo.start_link(pool_size: 1, log: false)
      Enum.each(MyApp.Database.ddl(), &SQL.query!(MyApp.Repo, &1, []))

      on_exit(fn ->
        _ = Postgres.storage_down(repo_config)
      end)

      %{repo: pid}
    end

    test "reads the column nullability of the fixture tables", %{repo: pid} do
      tables = Enum.map(MyApp.Database.tables(), &{nil, &1})
      assert Nullability.fetch(MyApp.Repo, tables) == MyApp.Database.columns()
      Supervisor.stop(pid)
    end

    test "generation with repo: gives the golden files", %{repo: pid} do
      with_repo = %{Golden.config() | columns: nil, repo: MyApp.Repo}
      assert Generator.generate(with_repo) == Generator.generate(Golden.config())
      Supervisor.stop(pid)
    end

    test "starts the repo when it is not running", %{repo: pid} do
      Supervisor.stop(pid)
      columns = Nullability.fetch(MyApp.Repo, [{nil, "users"}])
      assert columns[{"public", "users", "name"}] == false
      MyApp.Repo |> Process.whereis() |> Supervisor.stop()
    end
  end

  @tag :capture_log
  test "a repo that cannot connect is a generation error" do
    defmodule DownRepo do
      use Ecto.Repo, otp_app: :typelizer_test_down, adapter: Ecto.Adapters.Postgres
    end

    Application.put_env(:typelizer_test_down, DownRepo,
      hostname: "localhost",
      port: 1,
      database: "none",
      queue_target: 100,
      queue_interval: 100
    )

    assert_raise Typelizer.GenerationError, ~r/could not read column nullability/, fn ->
      Nullability.fetch(DownRepo, [{nil, "users"}])
    end
  end

  test "a module that is not a repo is a generation error" do
    config = %{Golden.config(System.tmp_dir!()) | columns: nil, repo: String}

    assert_raise Typelizer.GenerationError, ~r/is not an Ecto repo/, fn ->
      Generator.generate(config)
    end
  end

  test "Config.load/1 reads the defaults" do
    config = Config.load(app: :typelizer)
    assert config.output.serializers == "assets/js/generated/serializers"
    assert config.routes == %{include: [], exclude: ["/dev"]}
    assert config.key_transform == :camel
  end
end
