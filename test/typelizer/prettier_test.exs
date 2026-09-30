defmodule Typelizer.PrettierTest do
  # Uses a fake `prettier` script, so the test needs no Node.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias Typelizer.{Config, GenerationError, Prettier}

  defp fake_prettier(root, script) do
    bin = Path.join(root, "assets/node_modules/.bin/prettier")
    File.mkdir_p!(Path.dirname(bin))
    File.write!(bin, "#!/bin/sh\n" <> script)
    File.chmod!(bin, 0o755)
    File.write!(Path.join(root, "args.log"), "")
  end

  defp outputs(root) do
    [
      %{
        kind: :serializers,
        dir: Path.join(root, "gen"),
        files: %{"A.ts" => "a\n", "sub/B.ts" => "b\n"}
      }
    ]
  end

  test "formats every file with the project configuration", %{tmp_dir: root} do
    fake_prettier(root, """
    echo "$@" >> args.log
    if [ "$1" = "--find-config-path" ]; then echo ".prettierrc"; exit 0; fi
    for last; do :; done
    find "$last" -name '*.ts' | while read f; do printf 'formatted\\n' >> "$f"; done
    """)

    [output] = Prettier.format(outputs(root), Config.load(root: root, prettier: true))

    assert output.files == %{"A.ts" => "a\nformatted\n", "sub/B.ts" => "b\nformatted\n"}
    log = File.read!(Path.join(root, "args.log"))
    assert log =~ "--find-config-path #{root}/gen/index.ts"
    assert log =~ "--write --log-level warn --config #{root}/.prettierrc"
  end

  test "works without a configuration file", %{tmp_dir: root} do
    fake_prettier(root, """
    echo "$@" >> args.log
    if [ "$1" = "--find-config-path" ]; then exit 1; fi
    """)

    [output] = Prettier.format(outputs(root), Config.load(root: root, prettier: true))
    assert output.files == %{"A.ts" => "a\n", "sub/B.ts" => "b\n"}
    refute File.read!(Path.join(root, "args.log")) =~ "--config"
  end

  test "a Prettier failure is a generation error", %{tmp_dir: root} do
    fake_prettier(root, """
    if [ "$1" = "--find-config-path" ]; then exit 1; fi
    echo "SyntaxError: boom"; exit 2
    """)

    assert_raise GenerationError, ~r/prettier failed:\nSyntaxError: boom/, fn ->
      Prettier.format(outputs(root), Config.load(root: root, prettier: true))
    end
  end

  test "does nothing when off or when there is no output", %{tmp_dir: root} do
    assert Prettier.format(outputs(root), Config.load(root: root)) == outputs(root)
    assert Prettier.format([], Config.load(root: root, prettier: true)) == []
  end
end
