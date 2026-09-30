defmodule Typelizer.Golden do
  @moduledoc false
  # Generation settings of the golden files in test/golden.

  @dir Path.expand("../golden", __DIR__)

  def dir, do: @dir

  def config(root \\ @dir) do
    Typelizer.Config.load(
      app: :typelizer,
      root: root,
      output: [serializers: "serializers", routes: "routes", pages: "pages"],
      columns: MyApp.Database.columns()
    )
  end
end
