// Compiled together with the golden files by test/typelizer/typescript_test.exs.
// It uses the generated types and prints the results of the route helpers as JSON.
import { addUrlDefault, routes, setRoutesBaseUrl, setUrlDefaults } from "./routes";
import type { UrlDefaults } from "./routes";
import type {
  Comment,
  CursorMeta,
  DashboardStats,
  PaginationMeta,
  Project,
  Task,
  User,
} from "./serializers";
import type { Pages, SharedProps, TasksArchiveProps, TasksIndexProps } from "./pages";

const task: Pick<Task, "id" | "status" | "labels" | "assignee"> = {
  id: "t1",
  status: "todo",
  labels: ["bug"],
  assignee: null,
};
const comment: Comment["author"]["role"] = "admin";
const link: NonNullable<Project["settings"]>["theme"] = "dark";
const window: DashboardStats["window"] = { from: "2026-09-01", to: "2026-09-30" };
const user: User | null = null;
const shared: Pick<SharedProps, "locale"> = { locale: "en" };
const props: Pick<TasksIndexProps, "nextCursor" | "stats"> = { nextCursor: null };
const page: Pages["tasks/index"]["tasks"] = [];
const subject: DashboardStats["subject"] = { id: "u1", name: "Ana", role: "member", nickname: null };
const card: DashboardStats["ownerCard"] = { id: "u1", name: "Ana", nickname: null, online: true };
const mixed: DashboardStats["mixed"] = ["a", 1];
const history: DashboardStats["history"] = ["a", 2];
const pageMeta: PaginationMeta = { page: 1, pageSize: 20, total: 0, totalPages: 0 };
const cursorMeta: CursorMeta = { nextCursor: null, previousCursor: "a" };
const archive: Pick<TasksArchiveProps, "summary"> = { summary: { data: "ok" } };
const latest: DashboardStats["latestUsers"] = { data: [], meta: { generatedAt: "2026-09-30" } };

const results: Record<string, unknown> = {
  show: routes.task.show(42),
  showObject: routes.task.show({ id: "a b" }).url,
  index: routes.task.index().url,
  query: routes.apiV1Project.index({ query: { page: 2, tags: ["a", "b"], filter: { status: "todo" }, skip: null } })
    .url,
  typedQuery: routes.task.index({
    query: {
      page: 2,
      status: "todo",
      due_before: new Date(Date.UTC(2026, 8, 30)),
      min_estimate: "1.5",
      sort: [{ field: "price", dir: "asc" }],
      filter: { owner_id: 7 },
    },
  }).url,
  typedShow: routes.task.show(42, { query: { include: ["comments", "assignee"] } }).url,
  anchor: routes.task.show(42, { anchor: "notes" }).url,
  anchorEncoded: routes.task.show(42, { anchor: "a b#c" }).url,
  queryPlug: routes.apiV1Project.index({
    query: {
      due: new Date(Date.UTC(2026, 8, 30, 10, 0, 0)),
      sort: [{ field: "price", dir: "asc" }, { field: "name" }],
      filter: { status: ["todo", "done"], owner: { id: 7 }, since: new Date(Date.UTC(2026, 0, 1)) },
      "a&b": "c=d",
      flag: true,
      skip: undefined,
    },
  }).url,
  nested: routes.taskComment.create({ taskId: 7 }).url,
  snakeParam: routes.taskComment.index({ task_id: 7 } as unknown as { taskId: number }).url,
  twoParams: routes.apiV1Member.show({ projectId: 1, memberId: 2 }).url,
  globArray: routes.file.show(["a", "b c"]).url,
  globString: routes.file.show("x/y").url,
  update: routes.task.update(1).method,
  live: routes.board.index().url,
};

setRoutesBaseUrl("https://app.example.com/");
results["baseUrl"] = routes.page.home().url;
setRoutesBaseUrl("");
results["relativeAgain"] = routes.page.about().url;

const defaults: UrlDefaults = { locale: "en" };
setUrlDefaults(defaults);
results["defaultScalar"] = routes.localizedPage.article("intro").url;
results["defaultOverride"] = routes.localizedPage.article({ slug: "intro", locale: "es" }).url;
results["defaultOnly"] = routes.localizedPage.index().url;
results["defaultWithOptions"] = routes.localizedPage.index({}, { query: { q: "x" } }).url;
let current = "fr";
setUrlDefaults(() => ({ locale: current }));
results["defaultFunction"] = routes.localizedPage.index().url;
current = "de";
results["defaultFunctionLater"] = routes.localizedPage.index().url;
addUrlDefault("section", "news");
results["addDefault"] = routes.localizedFile.show({ path: ["a", "b"] } as unknown as {
  section: string;
  path: string[];
}).url;
setUrlDefaults({});
addUrlDefault("locale", "it");
results["addToObject"] = routes.localizedPage.index().url;
setUrlDefaults({});
try {
  routes.localizedPage.index();
} catch (error) {
  results["missingDefault"] = (error as Error).message;
}

// Type checks only (never called).
const typeOnly = (): void => {
  // @ts-expect-error: the options of a route with defaulted params come second.
  routes.localizedPage.index({ query: { q: "x" } });
  // @ts-expect-error: a typo in a typed query param.
  routes.task.index({ query: { stauts: "todo" } });
  // @ts-expect-error: a value outside the enum.
  routes.task.index({ query: { status: "archived" } });
  // @ts-expect-error: a required query param is missing.
  routes.task.show(1, { query: {} });
  // @ts-expect-error: an action declared with no query params.
  routes.task.edit(1, { query: { x: 1 } });
};
void typeOnly;

try {
  routes.apiV1Member.show({ projectId: 1 } as unknown as { projectId: number; memberId: number });
} catch (error) {
  results["missingParam"] = (error as Error).message;
}

void [task, comment, link, window, user, shared, props, page, subject, card, mixed, history];
void [pageMeta, cursorMeta, archive, latest];
console.log(JSON.stringify(results));
