// Compiled together with the golden files by test/typelizer/typescript_test.exs.
// It uses the generated types and prints the results of the route helpers as JSON.
import { routes, setRoutesBaseUrl } from "./routes";
import type { Comment, DashboardStats, Project, Task, User } from "./serializers";
import type { Pages, SharedProps, TasksIndexProps } from "./pages";

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

const results: Record<string, unknown> = {
  show: routes.task.show(42),
  showObject: routes.task.show({ id: "a b" }).url,
  index: routes.task.index().url,
  query: routes.task.index({ query: { page: 2, tags: ["a", "b"], filter: { status: "todo" }, skip: null } }).url,
  anchor: routes.task.show(42, { anchor: "notes" }).url,
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

try {
  routes.apiV1Member.show({ projectId: 1 } as unknown as { projectId: number; memberId: number });
} catch (error) {
  results["missingParam"] = (error as Error).message;
}

void [task, comment, link, window, user, shared, props, page];
console.log(JSON.stringify(results));
