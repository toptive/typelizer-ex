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
    defaults = defaults!(Map.get(filters, :defaults, []))

    groups =
      router.__routes__()
      |> Enum.filter(&generated?(&1, filters))
      |> Enum.map(&entry(&1, key_transform, defaults))
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

  defp defaults!(defaults) do
    if is_list(defaults) and Enum.all?(defaults, &(is_atom(&1) or is_binary(&1))) do
      Enum.map(defaults, &to_string/1)
    else
      raise GenerationError,
            "config :typelizer, routes: [defaults: ...] takes a list of path param names, " <>
              "for example [:locale], got: #{inspect(defaults)}"
    end
  end

  defp entry(route, key_transform, defaults) do
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
      params: params(route.path, key_transform, defaults),
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

  defp params(path, key_transform, defaults) do
    ~r/[:*]([A-Za-z_][A-Za-z0-9_]*)/
    |> Regex.scan(path)
    |> Enum.map(fn [match, name] ->
      %{
        name: name,
        key: Naming.key(name, key_transform),
        glob?: String.starts_with?(match, "*"),
        default?: name in defaults
      }
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
    required = Enum.reject(entry.params, & &1.default?)

    signature =
      case entry.params do
        [] ->
          "  #{property(entry.action)}: (options?: RouteOptions" <> result <> "\n"

        params ->
          "  #{property(entry.action)}: (\n" <>
            params_arg(params, required) <>
            "    options?: RouteOptions,\n" <>
            "  " <> result <> "\n"
      end

    doc <>
      signature <>
      url_line(entry, required) <>
      "\n    method: #{TS.literal(method)},\n" <>
      "  }),\n"
  end

  # The arguments of buildUrl. When every param has a default, `params` may be left
  # out. When the one required param is not the first param of the path, buildUrl is
  # told which param a single value is for.
  defp url_line(entry, required) do
    args =
      case {entry.params, required} do
        {[], _} ->
          ["{}", "options"]

        {_, []} ->
          ["params ?? {}", "options"]

        {[first | _], [%{name: name}]} when first.name != name ->
          ["params", "options", TS.literal(name)]

        _ ->
          ["params", "options"]
      end

    args = [TS.literal(entry.path) | args]
    line = "    url: buildUrl(#{Enum.join(args, ", ")}),"

    if String.length(line) <= TS.width(),
      do: line,
      else: "    url: buildUrl(\n" <> Enum.map_join(args, &"      #{&1},\n") <> "    ),"
  end

  # `params: <type>,` on one line when it fits, broken the way Prettier does otherwise.
  defp params_arg(params, required) do
    {head, members} = params_type(params, required)
    line = "    #{head} #{Enum.join(members, " | ")},"

    next_line = "      #{Enum.join(members, " | ")},"

    cond do
      String.length(line) <= TS.width() ->
        line <> "\n"

      match?([_, _ | _], members) and String.length(next_line) <= TS.width() ->
        "    #{head}\n" <> next_line <> "\n"

      match?([_, _ | _], members) ->
        ("    #{head}\n" <> Enum.map_join(members, fn member -> "      | #{member}\n" end))
        |> String.replace_suffix("\n", ",\n")

      true ->
        "    #{head} {\n" <>
          Enum.map_join(params, &"      #{param_property(&1)};\n") <>
          "    },\n"
    end
  end

  defp property(action), do: TS.property_key(action)

  # `params:` (or `params?:` when every param has a default) and the members of its
  # type: the object form, plus the bare value when exactly one param is required.
  defp params_type(params, required) do
    object = "{ " <> Enum.map_join(params, "; ", &param_property/1) <> " }"

    case required do
      [] -> {"params?:", [object]}
      [%{glob?: glob?}] -> {"params:", [object | String.split(value_type(glob?), " | ")]}
      _ -> {"params:", [object]}
    end
  end

  defp param_property(param) do
    mark = if param.default?, do: "?", else: ""
    "#{TS.property_key(param.key)}#{mark}: #{value_type(param.glob?)}"
  end

  defp value_type(true), do: "string | string[]"
  defp value_type(false), do: "string | number"

  defp index_file(groups) do
    imports = Enum.map_join(groups, "\n", &~s(import { #{&1} } from "./#{&1}";))

    exports =
      Enum.join(
        [
          if(groups != [], do: TS.export_list("export", groups)),
          ~s(export {\n  addUrlDefault,\n  buildUrl,\n  setRoutesBaseUrl,\n  setUrlDefaults,\n} from "./runtime";),
          ~s(export type {\n  Method,\n  RouteDefinition,\n  RouteOptions,\n  UrlDefaults,\n} from "./runtime";)
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

      export type UrlDefaults = Record<string, unknown>;

      let routesBaseUrl = "";
      let urlDefaults: UrlDefaults | (() => UrlDefaults) = {};

      /**
       * Prefixes every generated URL with an origin, for example
       * "https://app.example.com". Pass "" to go back to relative URLs.
       */
      export function setRoutesBaseUrl(url: string): void {
        routesBaseUrl = url.replace(/\\/+$/, "");
      }

      /**
       * Sets values for path params that many routes share, such as a locale. Pass a
       * function to read the current values on every call. A param given to a helper
       * wins over its default.
       */
      export function setUrlDefaults(
        defaults: UrlDefaults | (() => UrlDefaults),
      ): void {
        urlDefaults = defaults;
      }

      /** Adds one URL default and keeps the others. */
      export function addUrlDefault(key: string, value: unknown): void {
        const current = urlDefaults;
        urlDefaults =
          typeof current === "function"
            ? () => ({ ...current(), [key]: value })
            : { ...current, [key]: value };
      }

      const PARAM = /([:*])([A-Za-z_][A-Za-z0-9_]*)/g;

      /**
       * Builds a URL from a path template such as "/tasks/:id". A single value (not an
       * object) is the value of `scalarParam`, or of the first param of the template.
       */
      export function buildUrl(
        template: string,
        params: Record<string, unknown> | ParamValue,
        options?: RouteOptions,
        scalarParam?: string,
      ): string {
        const values = toParamObject(template, params, scalarParam);
        const defaults =
          typeof urlDefaults === "function" ? urlDefaults() : urlDefaults;
        const path = template.replace(PARAM, (_match, kind: string, name: string) =>
          encodeParam(kind === "*", paramValue(values, defaults, name, template)),
        );
        const query = options?.query ? encodeQuery(options.query) : "";

        return (
          routesBaseUrl +
          path +
          (query ? `?${query}` : "") +
          (options?.anchor ? `#${encodeURIComponent(options.anchor)}` : "")
        );
      }

      function toParamObject(
        template: string,
        params: Record<string, unknown> | ParamValue,
        scalarParam?: string,
      ): Record<string, unknown> {
        if (typeof params === "object" && !Array.isArray(params)) return params;
        const name = scalarParam ?? new RegExp(PARAM.source).exec(template)?.[2];
        return name ? { [name]: params } : {};
      }

      // Path params accept the snake_case name of the router and its camelCase form.
      // A given value wins over a URL default.
      function paramValue(
        values: Record<string, unknown>,
        defaults: UrlDefaults,
        name: string,
        template: string,
      ): unknown {
        const camel = name.replace(/_([a-z0-9])/g, (_m, c: string) =>
          c.toUpperCase(),
        );
        const value = lookup(values, name, camel) ?? lookup(defaults, name, camel);
        if (value === undefined || value === null) {
          throw new Error(
            `typelizer: missing route param "${camel}" for ${template}`,
          );
        }
        return value;
      }

      function lookup(
        values: Record<string, unknown>,
        name: string,
        camel: string,
      ): unknown {
        return name in values ? values[name] : values[camel];
      }

      function encodeParam(glob: boolean, value: unknown): string {
        if (!glob) return encodeURIComponent(String(value));
        const parts = Array.isArray(value) ? value : String(value).split("/");
        return parts.map((part) => encodeURIComponent(String(part))).join("/");
      }

      // Plug conventions: arrays of scalars become key[]=v, objects become key[sub]=v,
      // arrays of objects become key[0][sub]=v (as Phoenix forms send them), dates
      // become ISO-8601 strings, and null or undefined values are left out.
      function encodeQuery(query: Record<string, unknown>): string {
        const parts: string[] = [];
        for (const [key, value] of Object.entries(query)) {
          appendQuery(parts, encodeURIComponent(key), value);
        }
        return parts.join("&");
      }

      function appendQuery(parts: string[], key: string, value: unknown): void {
        if (value === undefined || value === null) return;

        if (value instanceof Date) {
          parts.push(`${key}=${encodeURIComponent(value.toISOString())}`);
        } else if (Array.isArray(value)) {
          const indexed = value.some(
            (item) =>
              typeof item === "object" && item !== null && !(item instanceof Date),
          );
          value.forEach((item, index) =>
            appendQuery(parts, indexed ? `${key}[${index}]` : `${key}[]`, item),
          );
        } else if (typeof value === "object") {
          for (const [name, item] of Object.entries(value)) {
            appendQuery(parts, `${key}[${encodeURIComponent(name)}]`, item);
          }
        } else {
          parts.push(`${key}=${encodeURIComponent(String(value))}`);
        }
      }
      """
    ])
  end
end
