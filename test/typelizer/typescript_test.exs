defmodule Typelizer.TypeScriptTest do
  # Compiles the golden files with the TypeScript compiler in its strictest common
  # settings, then runs the route helpers in Node. Needs Node and TypeScript:
  #   npm ci --prefix test/typescript
  use ExUnit.Case, async: true

  alias Plug.Conn.Query

  @moduletag :typescript
  @moduletag :tmp_dir

  @strict ~w(--strict --noUncheckedIndexedAccess --exactOptionalPropertyTypes --noImplicitOverride
             --noFallthroughCasesInSwitch --skipLibCheck --target es2020)

  setup %{tmp_dir: tmp_dir} do
    File.cp_r!(Typelizer.Golden.dir(), tmp_dir)
    File.cp!(Path.expand("../typescript/check.ts", __DIR__), Path.join(tmp_dir, "check.ts"))
    %{tsc: Typelizer.TypeScript.tsc!()}
  end

  test "the golden files pass tsc in strict mode", %{tmp_dir: tmp_dir, tsc: tsc} do
    File.write!(Path.join(tmp_dir, "envelope_values.ts"), envelope_values())

    args =
      @strict ++
        ~w(--noEmit --module esnext --moduleResolution bundler --verbatimModuleSyntax check.ts
           envelope_values.ts)

    {output, status} = System.cmd(tsc, args, cd: tmp_dir, stderr_to_stdout: true)
    assert status == 0, output
  end

  test "the golden files use the Prettier default style", %{tmp_dir: tmp_dir} do
    prettier = Path.join(Path.dirname(Typelizer.TypeScript.tsc!()), "prettier")

    if File.exists?(prettier) do
      {output, status} =
        System.cmd(prettier, ["--check", "serializers", "routes", "pages"],
          cd: tmp_dir,
          stderr_to_stdout: true
        )

      assert status == 0, output
    end
  end

  test "the route helpers build the right URLs in Node", %{tmp_dir: tmp_dir, tsc: tsc} do
    args = @strict ++ ~w(--module commonjs --outDir js check.ts)
    {output, status} = System.cmd(tsc, args, cd: tmp_dir, stderr_to_stdout: true)
    assert status == 0, output

    {json, 0} = System.cmd("node", ["js/check.js"], cd: tmp_dir)

    results = Jason.decode!(json)
    {query_plug, results} = Map.pop!(results, "queryPlug")
    ["/api/v1/projects", query] = String.split(query_plug, "?")

    # What Phoenix receives: Plug decodes the query string.
    assert Query.decode(query) == %{
             "due" => "2026-09-30T10:00:00.000Z",
             "sort" => %{
               "0" => %{"field" => "price", "dir" => "asc"},
               "1" => %{"field" => "name"}
             },
             "filter" => %{
               "status" => ["todo", "done"],
               "owner" => %{"id" => "7"},
               "since" => "2026-01-01T00:00:00.000Z"
             },
             "a&b" => "c=d",
             "flag" => "true"
           }

    assert results == %{
             "show" => %{"url" => "/tasks/42", "method" => "get"},
             "showObject" => "/tasks/a%20b",
             "index" => "/tasks",
             "query" => "/api/v1/projects?page=2&tags[]=a&tags[]=b&filter[status]=todo",
             "typedQuery" =>
               "/tasks?page=2&status=todo&due_before=2026-09-30" <>
                 "&updated_after=2026-09-30T10%3A00%3A00.000Z&min_estimate=1.5" <>
                 "&sort[0][field]=price&sort[0][dir]=asc&filter[owner_id]=7",
             "typedShow" => "/tasks/42?include[]=comments&include[]=assignee",
             "anchor" => "/tasks/42#notes",
             "anchorEncoded" => "/tasks/42#a%20b%23c",
             "nested" => "/tasks/7/comments",
             "snakeParam" => "/tasks/7/comments",
             "twoParams" => "/api/v1/projects/1/members/2",
             "globArray" => "/files/a/b%20c",
             "globString" => "/files/x/y",
             "update" => "patch",
             "live" => "/board",
             "baseUrl" => "https://app.example.com/",
             "relativeAgain" => "/about",
             "defaultScalar" => "/en/articles/intro",
             "defaultOverride" => "/es/articles/intro",
             "defaultOnly" => "/en",
             "defaultWithOptions" => "/en?q=x",
             "defaultFunction" => "/fr",
             "defaultFunctionLater" => "/de",
             "addDefault" => "/de/sections/news/a/b",
             "addToObject" => "/it",
             "missingDefault" => ~s(typelizer: missing route param "locale" for /:locale),
             "missingParam" =>
               ~s(typelizer: missing route param "memberId" for /api/v1/projects/:project_id/members/:member_id)
           }
  end

  # The values that Typelizer.Envelope builds, typed with the generated types: tsc
  # fails when the runtime helpers and the types disagree.
  defp envelope_values do
    user =
      MyAppWeb.UserSerializer.serialize(%{id: "u1", name: "Ana", role: :admin, nickname: nil})

    entries = [%{"id" => 1}]

    """
    import type { CursorPaginated, Envelope, Paginated, User } from "./serializers";

    export const paginated: Paginated<{ id: number }> = #{json(Typelizer.Envelope.paginated(entries, page: 1, page_size: 20, total: 41))};
    export const emptyPage: Paginated<{ id: number }> = #{json(Typelizer.Envelope.paginated([], page: 1, page_size: 20, total: 0))};
    export const cursor: CursorPaginated<{ id: number }> = #{json(Typelizer.Envelope.cursor_paginated(entries, next_cursor: "abc"))};
    export const wrapped: Envelope<User[], { generatedAt: string }> = #{json(Typelizer.Envelope.wrap([user], generated_at: "2026-09-30T10:00:00Z"))};
    export const bare: Envelope<number[]> = #{json(Typelizer.Envelope.wrap([1, 2]))};
    """
  end

  defp json(value), do: Jason.encode!(value)
end
