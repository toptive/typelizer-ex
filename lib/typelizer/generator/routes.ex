defmodule Typelizer.Generator.Routes do
  @moduledoc false
  # TypeScript route helpers from `Router.__routes__/0`: `runtime.ts`, one
  # `<group>.ts` per route group, and `index.ts`.

  alias Typelizer.{GenerationError, Naming, TS}

  @verbs [:get, :post, :put, :patch, :delete]

  @reserved ~w(await break case catch class const continue debugger default delete do else
    enum export extends false finally for function if implements import in instanceof
    interface let new null package private protected public return static super switch
    this throw true try typeof var void while with yield)

  @doc "The generated files: `%{relative_path => content}`."
  @spec files(module(), map(), :camel | :snake) :: %{String.t() => String.t()}
  def files(router, filters, key_transform) do
    groups =
      router.__routes__()
      |> Enum.filter(&generated?(&1, filters))
      |> Enum.map(&entry(&1, key_transform))
      |> merge()
      |> Enum.group_by(& &1.group)
      |> Enum.sort()

    group_files =
      Map.new(groups, fn {group, entries} ->
        {"#{group}.ts", group_file(group, Enum.sort_by(entries, & &1.action))}
      end)

    group_files
    |> Map.put("runtime.ts", runtime_file())
    |> Map.put("index.ts", index_file(Enum.map(groups, &elem(&1, 0))))
  end

  defp generated?(route, filters) do
    route.verb in @verbs and not Map.has_key?(route.metadata, :forward) and
      included?(route.path, filters)
  end

  defp included?(path, %{include: include, exclude: exclude}) do
    (include == [] or Enum.any?(include, &matches?(path, &1))) and
      not Enum.any?(exclude, &matches?(path, &1))
  end

  defp matches?(path, %Regex{} = regex), do: Regex.match?(regex, path)

  defp matches?(path, prefix) when is_binary(prefix) do
    case String.trim_trailing(prefix, "/") do
      "" -> true
      prefix -> path == prefix or String.starts_with?(path, prefix <> "/")
    end
  end

  defp matches?(_path, other) do
    raise GenerationError,
          "config :typelizer, routes: filters must be path prefixes (strings) or regexes, got: " <>
            inspect(other)
  end

  defp entry(route, key_transform) do
    {group, action} = names(route)

    unless Naming.identifier?(group) and group not in @reserved do
      raise GenerationError,
            "the route #{describe(route)} gets the group name #{inspect(group)}, which is not " <>
              "a valid TypeScript name. Set as: on the route"
    end

    %{
      group: group,
      action: action,
      verb: route.verb,
      path: route.path,
      params: params(route.path, key_transform),
      route: route
    }
  end

  defp names(%{metadata: %{phoenix_live_view: {view, action, _, _}}} = route) do
    group =
      case route.helper do
        helper when helper in [nil, "live"] ->
          view |> Naming.controller_group() |> String.replace_suffix("Live", "")

        helper ->
          Naming.camelize(helper)
      end

    {group, Naming.camelize(to_string(action || :index))}
  end

  defp names(route) do
    group =
      if route.helper,
        do: Naming.camelize(route.helper),
        else: Naming.controller_group(route.plug)

    action = if is_atom(route.plug_opts), do: route.plug_opts, else: :index
    {group, Naming.camelize(to_string(action))}
  end

  defp params(path, key_transform) do
    ~r/[:*]([A-Za-z_][A-Za-z0-9_]*)/
    |> Regex.scan(path)
    |> Enum.map(fn [match, name] ->
      %{key: Naming.key(name, key_transform), glob?: String.starts_with?(match, "*")}
    end)
  end

  # PUT and PATCH to the same action and path become one PATCH helper. Any other
  # pair of routes with the same group and action is a conflict.
  defp merge(entries) do
    entries
    |> Enum.group_by(&{&1.group, &1.action})
    |> Enum.sort()
    |> Enum.map(fn
      {_key, [entry]} ->
        entry

      {{group, action}, several} ->
        case Enum.uniq_by(several, &{&1.path, if(&1.verb == :put, do: :patch, else: &1.verb)}) do
          [_] ->
            Enum.find(several, &(&1.verb == :patch)) || hd(several)

          _ ->
            raise GenerationError,
                  "the routes #{Enum.map_join(several, " and ", &describe(&1.route))} both " <>
                    "become routes.#{group}.#{action}. Set as: on one of them, or exclude one " <>
                    "with config :typelizer, routes: [exclude: [...]]"
        end
    end)
  end

  defp describe(route) do
    "#{route.verb |> to_string() |> String.upcase()} #{route.path} (#{inspect(route.plug)})"
  end

  defp group_file(group, entries) do
    import = ~s(import { buildUrl, type RouteDefinition, type RouteOptions } from "./runtime";)
    body = "export const #{group} = {\n" <> Enum.map_join(entries, &action/1) <> "} as const;"
    TS.file(nil, [import, body])
  end

  defp action(entry) do
    method = entry.verb |> to_string()
    doc = "  /** #{String.upcase(method)} #{entry.path} */\n"
    result = ~s|): RouteDefinition<"#{method}"> => ({|

    signature =
      case entry.params do
        [] ->
          "  #{property(entry.action)}: (options?: RouteOptions" <> result <> "\n"

        params ->
          "  #{property(entry.action)}: (\n" <>
            params_arg(params) <>
            "    options?: RouteOptions,\n" <>
            "  " <> result <> "\n"
      end

    args = if entry.params == [], do: "{}", else: "params"
    url = "    url: buildUrl(#{TS.literal(entry.path)}, #{args}, options),"

    url =
      if String.length(url) <= TS.width(),
        do: url,
        else:
          "    url: buildUrl(\n      #{TS.literal(entry.path)},\n      #{args},\n      options,\n    ),"

    doc <>
      signature <>
      url <>
      "\n    method: #{TS.literal(method)},\n" <>
      "  }),\n"
  end

  # `params: <type>,` on one line when it fits, broken the way Prettier does otherwise.
  defp params_arg(params) do
    line = "    params: #{params_type(params)},"

    cond do
      String.length(line) <= TS.width() ->
        line <> "\n"

      match?([_], params) ->
        [%{key: key, glob?: glob?}] = params

        members = [
          "{ #{TS.property_key(key)}: #{value_type(glob?)} }"
          | String.split(value_type(glob?), " | ")
        ]

        ("    params:\n" <> Enum.map_join(members, fn member -> "      | #{member}\n" end))
        |> String.replace_suffix("\n", ",\n")

      true ->
        "    params: {\n" <>
          Enum.map_join(params, &"      #{TS.property_key(&1.key)}: #{value_type(&1.glob?)};\n") <>
          "    },\n"
    end
  end

  defp property(action), do: TS.property_key(action)

  defp params_type([%{key: key, glob?: glob?}]) do
    value = value_type(glob?)
    "{ #{TS.property_key(key)}: #{value} } | #{value}"
  end

  defp params_type(params) do
    "{ " <>
      Enum.map_join(params, "; ", &"#{TS.property_key(&1.key)}: #{value_type(&1.glob?)}") <> " }"
  end

  defp value_type(true), do: "string | string[]"
  defp value_type(false), do: "string | number"

  defp index_file(groups) do
    imports = Enum.map_join(groups, "\n", &~s(import { #{&1} } from "./#{&1}";))

    exports =
      Enum.join(
        [
          if(groups != [], do: TS.export_list("export", groups)),
          ~s(export { buildUrl, setRoutesBaseUrl } from "./runtime";),
          ~s(export type { Method, RouteDefinition, RouteOptions } from "./runtime";)
        ]
        |> Enum.reject(&is_nil/1),
        "\n"
      )

    routes =
      case groups do
        [] ->
          "export const routes = {} as const;"

        groups ->
          "export const routes = {\n" <> Enum.map_join(groups, &"  #{&1},\n") <> "} as const;"
      end

    TS.file(nil, [imports, exports, routes])
  end

  defp runtime_file do
    TS.file(nil, [
      """
      export type Method = "get" | "post" | "put" | "patch" | "delete";

      export interface RouteDefinition<M extends Method = Method> {
        url: string;
        method: M;
      }

      export interface RouteOptions {
        query?: Record<string, unknown>;
        anchor?: string;
      }

      type ParamValue = string | number | string[];

      let routesBaseUrl = "";

      /**
       * Prefixes every generated URL with an origin, for example
       * "https://app.example.com". Pass "" to go back to relative URLs.
       */
      export function setRoutesBaseUrl(url: string): void {
        routesBaseUrl = url.replace(/\\/+$/, "");
      }

      const PARAM = /([:*])([A-Za-z_][A-Za-z0-9_]*)/g;

      /** Builds a URL from a path template such as "/tasks/:id". */
      export function buildUrl(
        template: string,
        params: Record<string, unknown> | ParamValue,
        options?: RouteOptions,
      ): string {
        const values = toParamObject(template, params);
        const path = template.replace(PARAM, (_match, kind: string, name: string) =>
          encodeParam(kind === "*", paramValue(values, name, template)),
        );
        const query = options?.query ? encodeQuery(options.query) : "";

        return (
          routesBaseUrl +
          path +
          (query ? `?${query}` : "") +
          (options?.anchor ? `#${options.anchor}` : "")
        );
      }

      function toParamObject(
        template: string,
        params: Record<string, unknown> | ParamValue,
      ): Record<string, unknown> {
        if (typeof params === "object" && !Array.isArray(params)) return params;
        const name = new RegExp(PARAM.source).exec(template)?.[2];
        return name ? { [name]: params } : {};
      }

      // Path params accept the snake_case name of the router and its camelCase form.
      function paramValue(
        values: Record<string, unknown>,
        name: string,
        template: string,
      ): unknown {
        const camel = name.replace(/_([a-z0-9])/g, (_m, c: string) =>
          c.toUpperCase(),
        );
        const value = name in values ? values[name] : values[camel];
        if (value === undefined || value === null) {
          throw new Error(
            `typelizer: missing route param "${camel}" for ${template}`,
          );
        }
        return value;
      }

      function encodeParam(glob: boolean, value: unknown): string {
        if (!glob) return encodeURIComponent(String(value));
        const parts = Array.isArray(value) ? value : String(value).split("/");
        return parts.map((part) => encodeURIComponent(String(part))).join("/");
      }

      // Plug conventions: arrays become key[]=v, nested objects become key[sub]=v.
      function encodeQuery(query: Record<string, unknown>, prefix?: string): string {
        const parts: string[] = [];

        for (const [rawKey, value] of Object.entries(query)) {
          const key = prefix
            ? `${prefix}[${encodeURIComponent(rawKey)}]`
            : encodeURIComponent(rawKey);

          if (value === undefined || value === null) continue;

          if (Array.isArray(value)) {
            for (const item of value) {
              if (item === undefined || item === null) continue;
              parts.push(`${key}[]=${encodeURIComponent(String(item))}`);
            }
          } else if (typeof value === "object") {
            const nested = encodeQuery(value as Record<string, unknown>, key);
            if (nested) parts.push(nested);
          } else {
            parts.push(`${key}=${encodeURIComponent(String(value))}`);
          }
        }

        return parts.join("&");
      }
      """
    ])
  end
end
