defmodule Typelizer.EncoderTest do
  use ExUnit.Case, async: true

  alias Typelizer.Encoder

  test "dates and times become ISO-8601 strings; strings pass through" do
    assert Encoder.encode(~T[09:30:00], :temporal, []) == "09:30:00"
    assert Encoder.encode(~D[2026-09-30], :temporal, []) == "2026-09-30"
    assert Encoder.encode("2026-09-30", :temporal, []) == "2026-09-30"
    assert Encoder.encode(nil, :temporal, []) == nil
  end

  test "decimals follow decimal_type; other values pass through" do
    assert Encoder.encode(Decimal.new("1.50"), {:decimal, :string}, []) == "1.50"
    assert Encoder.encode(Decimal.new("1.50"), {:decimal, :number}, []) == 1.5
    assert Encoder.encode(3, {:decimal, :number}, []) == 3
  end

  test "enums, records, lists and objects" do
    assert Encoder.encode(:todo, {:enum, ["todo"]}, []) == "todo"
    assert Encoder.encode("todo", {:enum, ["todo"]}, []) == "todo"
    assert Encoder.encode(true, {:enum, ["todo"]}, []) == true

    assert Encoder.encode(%{"a" => Decimal.new("2")}, {:record, {:decimal, :string}}, []) == %{
             "a" => "2"
           }

    assert Encoder.encode([~D[2026-01-01], nil], {:list, {:nullable, :temporal}}, []) == [
             "2026-01-01",
             nil
           ]

    object = {:object, [{:due, "due", :temporal, false}, {"raw", "raw", :any, true}]}

    assert Encoder.encode(%{"raw" => 1, due: ~D[2026-01-01]}, object, []) == %{
             "due" => "2026-01-01",
             "raw" => 1
           }

    assert Encoder.encode(%{"due" => nil}, object, []) == %{"due" => nil}
  end

  test "serializer specs call the serializer with the options" do
    user = %{id: "u1", name: "Ana", role: :admin, nickname: nil}
    assert %{"role" => "admin"} = Encoder.encode(user, {:serializer, MyAppWeb.UserSerializer}, [])
  end
end
