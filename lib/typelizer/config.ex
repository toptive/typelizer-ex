defmodule Typelizer.Config do
  @moduledoc false
  # Reads `config :typelizer` for generation and fills in the defaults.
  # See guides/configuration.md.

  @default_output [
    serializers: "assets/js/generated/serializers",
    routes: "assets/js/generated/routes",
    pages: "assets/js/generated/pages"
  ]

  @default_routes [include: [], exclude: ["/dev"], defaults: []]

  defstruct app: nil,
            root: ".",
            serializers: :auto,
            pages: :auto,
            router: :auto,
            output: Map.new(@default_output),
            key_transform: :camel,
            decimal_type: :string,
            type_names: %{},
            repo: nil,
            routes: Map.new(@default_routes),
            prettier: false,
            columns: nil

  @type t :: %__MODULE__{
          app: atom() | nil,
          root: String.t(),
          serializers: :auto | [module()],
          pages: :auto | [module()],
          router: :auto | false | module(),
          output: %{optional(atom()) => String.t() | nil},
          key_transform: :camel | :snake,
          decimal_type: :string | :number,
          type_names: %{optional(module()) => String.t()},
          repo: module() | nil,
          routes: %{include: list(), exclude: list(), defaults: list()},
          prettier: boolean(),
          columns: map() | nil
        }

  @keys [
    :serializers,
    :pages,
    :router,
    :output,
    :key_transform,
    :decimal_type,
    :type_names,
    :repo,
    :routes,
    :prettier
  ]

  @doc """
  Builds the configuration from the application environment of `:typelizer`, then
  applies `overrides` (used by tests: `:app`, `:root`, `:columns` and any config key).
  """
  @spec load(keyword()) :: t()
  def load(overrides \\ []) do
    env = Application.get_all_env(:typelizer) |> Keyword.take(@keys)
    opts = Keyword.merge(env, overrides)

    %__MODULE__{
      app: Keyword.get(opts, :app),
      root: Keyword.get(opts, :root, "."),
      serializers: Keyword.get(opts, :serializers, :auto),
      pages: Keyword.get(opts, :pages, :auto),
      router: Keyword.get(opts, :router, :auto),
      output: merge_keyword(@default_output, Keyword.get(opts, :output, [])),
      key_transform: one_of!(opts, :key_transform, [:camel, :snake], :camel),
      decimal_type: one_of!(opts, :decimal_type, [:string, :number], :string),
      type_names: Map.new(Keyword.get(opts, :type_names, %{})),
      repo: Keyword.get(opts, :repo),
      routes: merge_keyword(@default_routes, Keyword.get(opts, :routes, [])),
      prettier: Keyword.get(opts, :prettier, false),
      columns: Keyword.get(opts, :columns)
    }
  end

  @doc "The absolute path of an output directory, or nil when that output is off."
  @spec output_dir(t(), atom()) :: String.t() | nil
  def output_dir(%__MODULE__{output: output, root: root}, kind) do
    case Map.get(output, kind) do
      nil -> nil
      dir -> Path.expand(dir, root)
    end
  end

  defp merge_keyword(defaults, overrides) do
    defaults |> Keyword.merge(Enum.to_list(overrides)) |> Map.new()
  end

  defp one_of!(opts, key, allowed, default) do
    value = Keyword.get(opts, key, default)

    if value in allowed do
      value
    else
      raise Typelizer.GenerationError,
            "config :typelizer, #{key}: must be one of #{inspect(allowed)}, got: #{inspect(value)}"
    end
  end
end
