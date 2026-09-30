defmodule Typelizer.Serializer do
  @moduledoc """
  A serializer DSL that is also the source of a TypeScript interface.

      defmodule MyAppWeb.TaskSerializer do
        use Typelizer.Serializer, schema: MyApp.Tasks.Task

        attributes [:id, :title, :status, :due_on, :inserted_at]
        attribute :overdue, type: :boolean, value: &MyApp.Tasks.overdue?/1
        has_one :assignee, serializer: MyAppWeb.UserSerializer, nullable: true
        has_many :comments, serializer: MyAppWeb.CommentSerializer
      end

      MyAppWeb.TaskSerializer.serialize(task)
      #=> %{"id" => "…", "title" => "…", "dueOn" => "2026-10-01", …}

      MyAppWeb.TaskSerializer.serialize_many(tasks, user_id: current_user.id)

  `mix typelizer.gen` writes the matching TypeScript interface.

  ## Options

    * `:schema` - an Ecto schema or embedded schema. Types are inferred from it and
      each attribute is checked against it.
    * `:name` - the TypeScript interface name. Default: derived from the module name
      (`MyAppWeb.Admin.TaskSerializer` → `AdminTask`).
    * `:key_transform` - `:camel` or `:snake`. Default: `config :typelizer, :key_transform`
      (`:camel`).

  ## Generated functions

    * `serialize(record, opts \\\\ [])` - returns a map with string keys, or `nil` for `nil`.
    * `serialize_many(records, opts \\\\ [])` - returns a list of maps.

  The options are passed to arity-2 `value:` functions and to nested serializers.

  See the [Serializers guide](serializers.md) for type specs, type inference and
  nullability.
  """

  alias Typelizer.{EctoSchema, Naming, TypeSpec}
  alias Typelizer.Serializer.Runtime

  @attribute_opts [:type, :nullable, :value]
  @has_one_opts [:serializer, :nullable, :value]
  @has_many_opts [:serializer, :value]

  @doc false
  defmacro __using__(opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)
    Keyword.validate!(opts, [:schema, :name, :key_transform])

    key_transform =
      Keyword.get_lazy(opts, :key_transform, fn ->
        Application.compile_env(__CALLER__, :typelizer, :key_transform, :camel)
      end)

    decimal_type = Application.compile_env(__CALLER__, :typelizer, :decimal_type, :string)
    check_option!(__CALLER__, :key_transform, key_transform, [:camel, :snake])
    check_option!(__CALLER__, :decimal_type, decimal_type, [:string, :number])

    name = Keyword.get_lazy(opts, :name, fn -> Naming.serializer_name(__CALLER__.module) end)

    unless is_binary(name) and Naming.identifier?(name) do
      compile_error!(
        __CALLER__,
        "name: must be a valid TypeScript identifier, got: #{inspect(name)}"
      )
    end

    config = %{
      schema: opts[:schema],
      name: name,
      ctx: %{key_transform: key_transform, decimal_type: decimal_type}
    }

    # `require` makes the schema a compile-time dependency: when the schema changes,
    # the serializer recompiles with the new types.
    require_schema = if opts[:schema], do: quote(do: require(unquote(opts[:schema])))

    quote do
      unquote(require_schema)

      import Typelizer.Serializer,
        only: [attributes: 1, attribute: 1, attribute: 2, attribute: 3, has_one: 2, has_many: 2]

      Module.register_attribute(__MODULE__, :typelizer_fields, accumulate: true)
      @typelizer_config unquote(Macro.escape(config))
      Typelizer.Serializer.__check_schema__(@typelizer_config, __ENV__)
      @before_compile Typelizer.Serializer
    end
  end

  @doc """
  Declares schema fields. Needs the `:schema` option.

      attributes [:id, :title, :status]
  """
  defmacro attributes(names) do
    quote do
      for name <- unquote(names) do
        Typelizer.Serializer.__field__(__MODULE__, :attribute, name, [], nil, __ENV__)
      end
    end
  end

  @doc """
  Declares one field.

  ## Options

    * `:type` - a type spec. Required with `:value` or without a schema.
    * `:nullable` - `true` or `false`. Always wins over inference.
    * `:value` - a function of the record (arity 1) or of the record and the
      options (arity 2) that computes the value.

  ## Examples

      attribute :title
      attribute :title, nullable: false
      attribute :overdue, type: :boolean, value: &MyApp.Tasks.overdue?/1
      attribute :overdue, [type: :boolean], fn task -> MyApp.Tasks.overdue?(task) end
  """
  defmacro attribute(name, opts \\ []) do
    field(:attribute, name, opts, __CALLER__)
  end

  @doc """
  Declares a computed field. The function is the last argument, so the options must
  be written in brackets:

      attribute :overdue, [type: :boolean], fn task -> MyApp.Tasks.overdue?(task) end
  """
  defmacro attribute(name, opts, fun) do
    unless is_list(opts) do
      compile_error!(__CALLER__, "attribute/3 expects a keyword list of options in brackets")
    end

    field(:attribute, name, opts ++ [value: fun], __CALLER__)
  end

  @doc """
  Declares one nested object, serialized with another serializer.

  ## Options

    * `:serializer` - required. The serializer of the nested value.
    * `:nullable` - `true` or `false`.
    * `:value` - a function (arity 1 or 2) that returns the nested value.

  ## Examples

      has_one :assignee, serializer: MyAppWeb.UserSerializer, nullable: true
  """
  defmacro has_one(name, opts) do
    field(:has_one, name, opts, __CALLER__)
  end

  @doc """
  Declares a list of nested objects, serialized with another serializer.

  ## Options

    * `:serializer` - required. The serializer of each nested value.
    * `:value` - a function (arity 1 or 2) that returns the nested values.

  ## Examples

      has_many :comments, serializer: MyAppWeb.CommentSerializer
  """
  defmacro has_many(name, opts) do
    field(:has_many, name, opts, __CALLER__)
  end

  # The `value:` function is code, not data: it becomes a private function of the
  # serializer, defined where the field is declared. The other options are data and
  # are evaluated in the module body.
  defp field(kind, name, opts, caller) do
    {value, opts} = pop_value(opts, caller)

    case value do
      nil ->
        quote do
          Typelizer.Serializer.__field__(
            __MODULE__,
            unquote(kind),
            unquote(name),
            unquote(opts),
            nil,
            __ENV__
          )
        end

      value ->
        unless is_atom(name) do
          compile_error!(
            caller,
            "a field with value: needs a literal atom name, got: #{Macro.to_string(name)}"
          )
        end

        fun_name = :"__typelizer_value_#{name}__"

        quote do
          unquote(value_function(fun_name, value))

          Typelizer.Serializer.__field__(
            __MODULE__,
            unquote(kind),
            unquote(name),
            unquote(opts),
            unquote(fun_name),
            __ENV__
          )
        end
    end
  end

  defp pop_value(opts, caller) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Keyword.pop(opts, :value)
    else
      compile_error!(caller, "expected a keyword list of options, got: #{Macro.to_string(opts)}")
    end
  end

  defp pop_value(opts, _caller), do: {nil, opts}

  defp value_function(fun_name, value) do
    record = Macro.var(:record, __MODULE__)
    opts = Macro.var(:opts, __MODULE__)

    case fun_arity(value) do
      1 ->
        quote do
          defp unquote(fun_name)(unquote(record), _opts), do: unquote(value).(unquote(record))
        end

      2 ->
        quote do
          defp unquote(fun_name)(unquote(record), unquote(opts)),
            do: unquote(value).(unquote(record), unquote(opts))
        end

      nil ->
        quote do
          defp unquote(fun_name)(unquote(record), unquote(opts)),
            do: Runtime.call(unquote(value), unquote(record), unquote(opts))
        end
    end
  end

  defp fun_arity({:fn, _, [{:->, _, [args, _body]} | _]}) do
    case args do
      [{:when, _, when_args}] -> length(when_args) - 1
      args -> length(args)
    end
  end

  defp fun_arity({:&, _, [{:/, _, [_fun, arity]}]}) when is_integer(arity), do: arity
  defp fun_arity(_value), do: nil

  @doc false
  def __check_schema__(%{schema: nil}, _env), do: :ok

  def __check_schema__(%{schema: schema}, env) do
    unless is_atom(schema) and match?({:module, _}, Code.ensure_compiled(schema)) and
             EctoSchema.schema?(schema) do
      compile_error!(env, "schema: #{inspect(schema)} is not an Ecto schema")
    end

    :ok
  end

  @doc false
  def __field__(module, kind, name, opts, fun_name, env) do
    config = Module.get_attribute(module, :typelizer_config)
    fields = Module.get_attribute(module, :typelizer_fields)

    unless is_atom(name) do
      compile_error!(env, "a field name must be an atom, got: #{inspect(name)}")
    end

    if Enum.any?(fields, &(&1.name == name)) do
      compile_error!(env, "the field #{inspect(name)} is declared twice")
    end

    opts = check_opts!(env, kind, name, opts)
    source = if fun_name, do: {:fun, fun_name}, else: {:field, name}

    field =
      try do
        build_field(kind, name, opts, source, config)
      rescue
        error in ArgumentError -> compile_error!(env, "#{inspect(name)}: " <> error.message)
      end

    Module.put_attribute(module, :typelizer_fields, field)
  end

  defp check_opts!(env, kind, name, opts) do
    allowed =
      case kind do
        :attribute -> @attribute_opts
        :has_one -> @has_one_opts
        :has_many -> @has_many_opts
      end

    unless Keyword.keyword?(opts) do
      compile_error!(
        env,
        "#{inspect(name)}: expected a keyword list of options, got: #{inspect(opts)}"
      )
    end

    check_known_opts!(env, kind, name, opts, allowed)

    case Keyword.fetch(opts, :nullable) do
      {:ok, value} when not is_boolean(value) ->
        compile_error!(env, "#{inspect(name)}: nullable: must be true or false")

      _ ->
        opts
    end
  end

  defp check_known_opts!(env, kind, name, opts, allowed) do
    case Keyword.keys(opts) -- allowed do
      [] ->
        :ok

      [:value | _] ->
        compile_error!(env, "#{inspect(name)}: value: must be written inline in the #{kind} call")

      unknown ->
        compile_error!(
          env,
          "#{inspect(name)}: unknown option(s) #{inspect(unknown)} for #{kind}. " <>
            "Allowed: #{inspect(allowed)}"
        )
    end
  end

  defp build_field(:attribute, name, opts, source, config) do
    {spec, nullability} = attribute_type(name, opts, source, config)

    nullable = explicit_nullable(opts, spec, nullability)

    %{
      name: name,
      key: Naming.key(name, config.ctx.key_transform),
      kind: :attribute,
      spec: if(nullable == false, do: unwrap_nullable(spec), else: spec),
      nullable: nullable,
      source: source
    }
  end

  defp build_field(kind, name, opts, source, config) do
    serializer = opts[:serializer]

    unless is_atom(serializer) and serializer not in [nil, true, false] do
      raise ArgumentError,
            "#{kind} needs serializer: SomeSerializer (the serializer of the nested value)"
    end

    nullability = relation_nullability(kind, name, source, config)

    spec =
      if kind == :has_many,
        do: {:list, {:serializer, serializer}},
        else: {:serializer, serializer}

    %{
      name: name,
      key: Naming.key(name, config.ctx.key_transform),
      kind: kind,
      spec: spec,
      nullable: if(kind == :has_one, do: Keyword.get(opts, :nullable, nullability), else: false),
      source: source,
      serializer: serializer
    }
  end

  defp attribute_type(name, opts, source, config) do
    case Keyword.fetch(opts, :type) do
      {:ok, type} ->
        spec = TypeSpec.normalize!(type, config.ctx)
        if config.schema && source == {:field, name}, do: schema_describe!(config, name)
        {spec, match?({:nullable, _}, spec)}

      :error ->
        if match?({:fun, _}, source) do
          raise ArgumentError,
                "a computed attribute must declare its TypeScript type, for example " <>
                  "attribute #{inspect(name)}, type: :boolean, value: ..."
        end

        unless config.schema do
          raise ArgumentError,
                "add type: (for example type: :string) or set schema: in use Typelizer.Serializer"
        end

        schema_describe!(config, name)
    end
  end

  defp schema_describe!(config, name) do
    case EctoSchema.describe(config.schema, name, :attribute, config.ctx) do
      {:field, spec, nullability} ->
        {spec, nullability}

      {:association, cardinality, _} ->
        macro = if cardinality == :one, do: "has_one", else: "has_many"

        raise ArgumentError,
              "#{inspect(name)} is an association of #{inspect(config.schema)}. " <>
                "Use #{macro} #{inspect(name)}, serializer: ..."

      {:error, message} ->
        raise ArgumentError, message <> ". Check the name, or add type: and value:"
    end
  end

  defp relation_nullability(kind, name, {:field, name}, %{schema: schema} = config)
       when not is_nil(schema) do
    expected = if kind == :has_one, do: :one, else: :many

    case EctoSchema.describe(schema, name, :relation, config.ctx) do
      {type, ^expected, nullability} when type in [:association, :embed] ->
        nullability

      {type, cardinality, _} when type in [:association, :embed] ->
        other = if cardinality == :one, do: "has_one", else: "has_many"

        raise ArgumentError,
              "#{inspect(name)} holds #{if cardinality == :one, do: "one value", else: "a list"}. " <>
                "Use #{other} instead of #{kind}"

      _ ->
        raise ArgumentError,
              "#{inspect(schema)} has no association or embed #{inspect(name)}. " <>
                "Check the name, or add value: to compute it"
    end
  end

  defp relation_nullability(_kind, _name, _source, _config), do: true

  defp explicit_nullable(opts, spec, nullability) do
    case Keyword.fetch(opts, :nullable) do
      {:ok, value} -> value
      :error -> if match?({:nullable, _}, spec), do: true, else: nullability
    end
  end

  defp unwrap_nullable({:nullable, spec}), do: spec
  defp unwrap_nullable(spec), do: spec

  @doc false
  defmacro __before_compile__(env) do
    config = Module.get_attribute(env.module, :typelizer_config)
    fields = env.module |> Module.get_attribute(:typelizer_fields) |> Enum.reverse()
    record = Macro.var(:record, __MODULE__)
    opts = Macro.var(:opts, __MODULE__)
    pairs = Enum.map(fields, &{&1.key, value_ast(&1, record, opts)})
    public_fields = Enum.map(fields, &Map.drop(&1, [:source]))

    quote do
      @doc false
      def __typelizer__(:name), do: unquote(config.name)
      def __typelizer__(:schema), do: unquote(config.schema)
      def __typelizer__(:fields), do: unquote(Macro.escape(public_fields))
      def __typelizer__(:key_transform), do: unquote(config.ctx.key_transform)

      @doc """
      Serializes one record into a map with string keys. Returns `nil` for `nil`.
      """
      @spec serialize(struct() | map() | nil, keyword()) :: map() | nil
      def serialize(record, opts \\ [])
      def serialize(nil, _opts), do: nil

      def serialize(unquote(record), unquote(opts)) when is_list(unquote(opts)) do
        %{unquote_splicing(pairs)}
      end

      @doc """
      Serializes a list of records.
      """
      @spec serialize_many([struct() | map()], keyword()) :: [map()]
      def serialize_many(records, opts \\ []) when is_list(records) do
        Enum.map(records, &serialize(&1, opts))
      end
    end
  end

  defp value_ast(%{kind: :attribute} = field, record, opts) do
    raw = raw_ast(field, record, opts)

    if TypeSpec.passthrough?(field.spec) do
      raw
    else
      quote do
        Typelizer.Encoder.encode(unquote(raw), unquote(Macro.escape(field.spec)), unquote(opts))
      end
    end
  end

  defp value_ast(%{kind: kind} = field, record, opts) do
    helper = if kind == :has_one, do: :one, else: :many

    quote do
      Runtime.unquote(helper)(
        unquote(raw_ast(field, record, opts)),
        unquote(field.serializer),
        unquote(opts),
        __MODULE__,
        unquote(field.name)
      )
    end
  end

  defp raw_ast(%{source: {:field, name}}, record, _opts) do
    quote do
      Runtime.fetch!(unquote(record), unquote(name), __MODULE__)
    end
  end

  defp raw_ast(%{source: {:fun, fun_name}}, record, opts) do
    quote do: unquote(fun_name)(unquote(record), unquote(opts))
  end

  defp check_option!(env, key, value, allowed) do
    unless value in allowed do
      compile_error!(env, "#{key}: must be one of #{inspect(allowed)}, got: #{inspect(value)}")
    end
  end

  defp compile_error!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end
