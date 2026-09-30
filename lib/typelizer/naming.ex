defmodule Typelizer.Naming do
  @moduledoc false
  # Name conversions shared by the serializers, the route helpers and the pages.

  @doc """
  Converts an Elixir name to a TypeScript key with the given key transform.

      iex> Typelizer.Naming.key(:due_on, :camel)
      "dueOn"
      iex> Typelizer.Naming.key(:due_on, :snake)
      "due_on"
  """
  @spec key(atom() | String.t(), :camel | :snake) :: String.t()
  def key(name, :camel), do: camelize(to_string(name))
  def key(name, :snake), do: to_string(name)

  @doc """
  Converts `snake_case` to `camelCase`. Leading underscores are kept.

      iex> Typelizer.Naming.camelize("task_comment")
      "taskComment"
      iex> Typelizer.Naming.camelize("api_v1_task")
      "apiV1Task"
  """
  @spec camelize(String.t()) :: String.t()
  def camelize(string) do
    {leading, rest} = split_leading_underscores(string)

    case String.split(rest, "_", trim: true) do
      [] -> string
      [first | others] -> leading <> first <> Enum.map_join(others, &upcase_first/1)
    end
  end

  @doc """
  Converts a string with `/`, `-`, `_`, `.` or space separators to PascalCase.

      iex> Typelizer.Naming.pascalize("settings/profile-edit")
      "SettingsProfileEdit"
  """
  @spec pascalize(String.t()) :: String.t()
  def pascalize(string) do
    string
    |> String.split(["/", "-", "_", ".", " "], trim: true)
    |> Enum.map_join(&upcase_first/1)
  end

  @doc """
  The default TypeScript interface name of a serializer module.

      iex> Typelizer.Naming.serializer_name(MyAppWeb.Admin.TaskSerializer)
      "AdminTask"
      iex> Typelizer.Naming.serializer_name(MyApp.Serializers.TaskSerializer)
      "Task"
  """
  @spec serializer_name(module()) :: String.t()
  def serializer_name(module) do
    module
    |> Module.split()
    |> drop_namespace()
    |> Enum.reject(&(&1 == "Serializers"))
    |> strip_last_suffix("Serializer")
    |> Enum.join()
  end

  @doc """
  The route group name for a controller or LiveView module.

      iex> Typelizer.Naming.controller_group(MyAppWeb.Admin.UserController)
      "adminUser"
  """
  @spec controller_group(module()) :: String.t()
  def controller_group(module) do
    module
    |> Module.split()
    |> drop_namespace()
    |> strip_last_suffix("Controller")
    |> Enum.join()
    |> lower_first()
  end

  @doc """
  True when `name` can be used as a TypeScript property name without quotes.
  """
  @spec identifier?(String.t()) :: boolean()
  def identifier?(name), do: Regex.match?(~r/^[A-Za-z_$][A-Za-z0-9_$]*$/, name)

  @doc """
  Upcases the first character of a string.
  """
  @spec upcase_first(String.t()) :: String.t()
  def upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  def upcase_first(""), do: ""

  defp lower_first(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest
  defp lower_first(""), do: ""

  defp drop_namespace([_namespace | [_ | _] = rest]), do: rest
  defp drop_namespace(segments), do: segments

  defp strip_last_suffix(segments, suffix) do
    {init, [last]} = Enum.split(segments, -1)

    case String.replace_suffix(last, suffix, "") do
      "" -> init
      stripped -> init ++ [stripped]
    end
  end

  defp split_leading_underscores(string) do
    rest = String.trim_leading(string, "_")
    {String.duplicate("_", byte_size(string) - byte_size(rest)), rest}
  end
end
