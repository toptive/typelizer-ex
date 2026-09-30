defmodule Typelizer.Prettier do
  @moduledoc false
  # Optional Prettier pass (`config :typelizer, prettier: true`). The files are
  # formatted in a temporary directory with the Prettier configuration that applies
  # to the real output directory, so `mix typelizer.gen` and `mix typelizer.check`
  # produce the same bytes.

  alias Typelizer.{Config, GenerationError}

  @doc "Formats the outputs when Prettier is enabled."
  @spec format([Typelizer.Generator.output()], Config.t()) :: [Typelizer.Generator.output()]
  def format(outputs, %Config{prettier: false}), do: outputs
  def format([], _config), do: []

  def format(outputs, %Config{prettier: true, root: root}) do
    bin = find_bin!(root)
    tmp = Path.join(System.tmp_dir!(), "typelizer-prettier-#{System.unique_integer([:positive])}")

    try do
      Enum.map(outputs, &format_output(&1, bin, root, Path.join(tmp, to_string(&1.kind))))
    after
      File.rm_rf!(tmp)
    end
  end

  defp format_output(output, bin, root, tmp) do
    Enum.each(output.files, fn {relative, content} ->
      path = Path.join(tmp, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end)

    config_args =
      case System.cmd(bin, ["--find-config-path", Path.join(output.dir, "index.ts")],
             cd: root,
             stderr_to_stdout: true
           ) do
        {path, 0} when path != "" -> ["--config", Path.expand(String.trim(path), root)]
        _ -> []
      end

    case System.cmd(bin, ["--write", "--log-level", "warn" | config_args] ++ [tmp],
           cd: root,
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {out, _} -> raise GenerationError, "prettier failed:\n#{out}"
    end

    files =
      Map.new(output.files, fn {relative, _} ->
        {relative, File.read!(Path.join(tmp, relative))}
      end)

    %{output | files: files}
  end

  defp find_bin!(root) do
    ["node_modules/.bin/prettier", "assets/node_modules/.bin/prettier"]
    |> Enum.map(&Path.expand(&1, root))
    |> Enum.find(&File.exists?/1)
    |> case do
      nil ->
        raise GenerationError,
              "config :typelizer, prettier: true, but Prettier is not installed in " <>
                "node_modules or assets/node_modules"

      bin ->
        bin
    end
  end
end
