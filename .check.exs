# Configuration of `mix check` (ex_check). It runs the quality gates listed in AGENTS.md.
[
  parallel: true,
  skipped: false,
  tools: [
    {:compiler, "mix compile --warnings-as-errors --force"},
    {:formatter, "mix format --check-formatted"},
    {:credo, "mix credo --strict"},
    {:dialyzer, "mix dialyzer"},
    {:ex_unit, "mix test"},
    {:ex_doc, "mix docs --warnings-as-errors", env: %{"MIX_ENV" => "dev"}},
    # Not used by this project.
    {:npm_test, false},
    {:sobelow, false},
    {:mix_audit, false},
    {:doctor, false},
    {:gettext, false}
  ]
]
