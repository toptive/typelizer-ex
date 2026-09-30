defmodule Typelizer.InertiaPage.PropsError do
  @moduledoc """
  Raised by `Typelizer.InertiaPage.ValidateProps` when the props of a rendered Inertia
  page do not match the page declaration.
  """

  defexception [:message]
end
