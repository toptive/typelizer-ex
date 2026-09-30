defmodule Typelizer.SerializationError do
  @moduledoc """
  Raised by `serialize/2` when a record cannot be serialized, for example when an
  association is not preloaded or a field is missing from the record.
  """

  defexception [:message]
end
