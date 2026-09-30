defmodule Typelizer.TypeScriptTest do
  # Compiles the golden files with the TypeScript compiler in its strictest common
  # settings, then runs the route helpers in Node. Needs Node and TypeScript:
  #   npm ci --prefix test/typescript
  use ExUnit.Case, async: true

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
    args =
      @strict ++
        ~w(--noEmit --module esnext --moduleResolution bundler --verbatimModuleSyntax check.ts)

    {output, status} = System.cmd(tsc, args, cd: tmp_dir, stderr_to_stdout: true)
    assert status == 0, output
  end

  test "the route helpers build the right URLs in Node", %{tmp_dir: tmp_dir, tsc: tsc} do
    args = @strict ++ ~w(--module commonjs --outDir js check.ts)
    {output, status} = System.cmd(tsc, args, cd: tmp_dir, stderr_to_stdout: true)
    assert status == 0, output

    {json, 0} = System.cmd("node", ["js/check.js"], cd: tmp_dir)

    assert Jason.decode!(json) == %{
             "show" => %{"url" => "/tasks/42", "method" => "get"},
             "showObject" => "/tasks/a%20b",
             "index" => "/tasks",
             "query" => "/tasks?page=2&tags[]=a&tags[]=b&filter[status]=todo",
             "anchor" => "/tasks/42#notes",
             "nested" => "/tasks/7/comments",
             "snakeParam" => "/tasks/7/comments",
             "twoParams" => "/api/v1/projects/1/members/2",
             "globArray" => "/files/a/b%20c",
             "globString" => "/files/x/y",
             "update" => "patch",
             "live" => "/board",
             "baseUrl" => "https://app.example.com/",
             "relativeAgain" => "/about",
             "missingParam" =>
               ~s(typelizer: missing route param "memberId" for /api/v1/projects/:project_id/members/:member_id)
           }
  end
end
