defmodule Typelizer.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Typelizer.{Config, Envelope, GenerationError, Generator, TS, TypeSpec}
  alias Typelizer.Generator.Serializers

  doctest Typelizer.Envelope

  describe "runtime helpers" do
    test "meta keys follow the key transform at every level; structs are kept" do
      meta = %{"already_string" => [%{item_id: 1}], source: %{last_sync: ~D[2026-09-30]}}

      assert Envelope.wrap([], meta) == %{
               "data" => [],
               "meta" => %{
                 "source" => %{"lastSync" => ~D[2026-09-30]},
                 "alreadyString" => [%{"itemId" => 1}]
               }
             }
    end

    test "paginated/2 computes totalPages and checks its options" do
      assert %{"meta" => %{"totalPages" => 0}} =
               Envelope.paginated([], page: 1, page_size: 10, total: 0)

      assert %{"meta" => %{"totalPages" => 3}} =
               Envelope.paginated([], %{page: 3, page_size: 10, total: 21})

      assert_raise ArgumentError, ~r/needs page_size: an integer >= 1, got: 0/, fn ->
        Envelope.paginated([], page: 1, page_size: 0, total: 0)
      end

      assert_raise ArgumentError, ~r/needs total: an integer >= 0, got: nil/, fn ->
        Envelope.paginated([], page: 1, page_size: 10)
      end
    end

    test "cursor_paginated/2 checks its cursors" do
      assert %{"meta" => %{"nextCursor" => nil, "previousCursor" => nil}} =
               Envelope.cursor_paginated([])

      assert_raise ArgumentError, ~r/needs next_cursor: a string or nil, got: 1/, fn ->
        Envelope.cursor_paginated([], next_cursor: 1)
      end
    end
  end

  describe "type specs" do
    @ctx %{key_transform: :camel, decimal_type: :string}

    test "normalize, render and report their envelope types" do
      spec =
        TypeSpec.normalize!(
          {:list, {:paginated, {:envelope, :string, {:object, n: :integer}}}},
          @ctx
        )

      name_of = fn _ -> "X" end

      assert TS.type(spec, name_of) == "Paginated<Envelope<string, { n: number }>>[]"
      assert TypeSpec.envelopes(spec) == ["Paginated", "Envelope"]
      assert TypeSpec.passthrough?(spec)

      nested =
        TypeSpec.normalize!({:envelope, :string, {:object, a: {:object, b: :integer}}}, @ctx)

      assert TS.type(nested, name_of) =~ "Envelope<string, {\n  a: {\n"

      assert TS.type(
               TypeSpec.normalize!({:cursor_paginated, MyAppWeb.UserSerializer}, @ctx),
               name_of
             ) ==
               "CursorPaginated<X>"
    end

    test "invalid inner specs are rejected" do
      assert_raise ArgumentError, ~r/unknown type :nope/, fn ->
        TypeSpec.normalize!({:paginated, :nope}, @ctx)
      end

      assert_raise ArgumentError, ~r/unknown type :nope/, fn ->
        TypeSpec.normalize!({:envelope, :string, :nope}, @ctx)
      end
    end
  end

  describe "generation" do
    test "Envelope.ts follows the key transform" do
      files = Serializers.files([], %{}, fn _ -> false end, envelope: :snake)
      assert files["Envelope.ts"] =~ "  page_size: number;\n"
      assert files["Envelope.ts"] =~ "  next_cursor: string | null;\n"
      assert files["index.ts"] =~ ~s(} from "./Envelope";)
    end

    test "a serializer named like an envelope type" do
      names = %{MyAppWeb.UserSerializer => "Paginated"}
      message = ~r/MyAppWeb.UserSerializer has the TypeScript name "Paginated"/
      generate = fn -> Serializers.files([], names, fn _ -> false end, envelope: :camel) end

      assert_raise GenerationError, message, generate
    end

    test "Inertia props with envelopes need the serializer output" do
      defmodule EnvelopePage do
        use Typelizer.InertiaPage
        page "list", props: [items: {:paginated, :string}]
      end

      config =
        Config.load(
          app: :typelizer,
          pages: [EnvelopePage],
          output: [serializers: nil],
          columns: %{}
        )

      assert_raise GenerationError, ~r/serializers or envelope types/, fn ->
        Generator.generate(config)
      end
    end
  end
end
