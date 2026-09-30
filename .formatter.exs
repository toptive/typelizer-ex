# Used by "mix format"
locals_without_parens = [
  attributes: 1,
  attribute: 1,
  attribute: 2,
  attribute: 3,
  has_one: 2,
  has_many: 2,
  page: 2,
  shared: 1
]

[
  import_deps: [:ecto, :phoenix, :plug],
  inputs: ["{mix,.formatter,.check}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
