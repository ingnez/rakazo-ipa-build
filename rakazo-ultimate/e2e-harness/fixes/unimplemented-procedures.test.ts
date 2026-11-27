import { createRouterClient } from "@orpc/server";
import type { Actor } from "@rakazo/contracts";
import { appContract, ScenarioModelsViewSchema } from "@rakazo/contracts";
import { describe, expect, it } from "vitest";
import type { RouterDeps } from "./router.js";
import { createRouter } from "./router.js";
import { contractProcedurePaths, emptyScenarioModels } from "./unimplemented-procedures.js";

const actor: Actor = {
  spaceId: "space-1",
  userId: "user-1",
  email: "user@rakazo.test",
  isDeploymentOwner: true,
};

const client = () =>
  createRouterClient(createRouter({ env: {} } as unknown as RouterDeps), { context: { actor } });

function call(path: string[], input: unknown = {}) {
  let node: unknown = client();
  for (const key of path) node = (node as Record<string, unknown>)[key];
  return (node as (input: unknown) => Promise<unknown>)(input);
}

const id = "cmwyp7s0g32a35giop6kbqlxe";

function hasHandler(router: unknown, path: string[]): boolean {
  let node: unknown = router;
  for (const key of path) node = (node as Record<string, unknown> | undefined)?.[key];
  const def = (node as { "~orpc"?: { handler?: unknown } } | undefined)?.["~orpc"];
  return typeof def?.handler === "function";
}

describe("every contract procedure answers, never an opaque 500", () => {
  const paths = contractProcedurePaths(appContract);

  it("covers the whole contract", () => {
    expect(paths.length).toBeGreaterThan(300);
  });

  it("gives every contract procedure a handler (a missing one answers an opaque 500)", () => {
    const router = createRouter({ env: {} } as unknown as RouterDeps);
    expect(paths.filter((path) => !hasHandler(router, path)).map((p) => p.join("/"))).toEqual([]);
  });

  it("models/scenarios answers an empty scene list that satisfies its schema", async () => {
    const view = await call(["models", "scenarios"]);
    expect(ScenarioModelsViewSchema.safeParse(view).success).toBe(true);
    expect(view).toEqual(emptyScenarioModels());
    expect((view as { slots: unknown[] }).slots).toHaveLength(6);
  });

  it.each<[string[], unknown]>([
    [["models", "setScenario"], { slot: "fast", primary: null }],
    [["models", "scenarioCatalog"], { slot: "fast" }],
    [["models", "refreshModels"], { credentialId: id }],
    [["memory", "diaries"], { botId: id }],
    [["memory", "diary"], { diaryId: id }],
    [["memory", "learnings"], {}],
    [["memory", "decideLearning"], { learningId: id, status: "approved" }],
    [["memory", "usedByRun"], { runId: id }],
    [["usage", "details"], {}],
    [["threads", "taskSteps"], { taskId: id }],
    [["bots", "tasks"], { botId: id }],
    [["bots", "setMain"], { botId: id }],
    [["voice", "realtimeCatalog"], undefined],
  ])("%j without a handler answers NOT_IMPLEMENTED, not INTERNAL_SERVER_ERROR", async (path, input) => {
    await expect(call(path, input)).rejects.toMatchObject({ code: "NOT_IMPLEMENTED", status: 501 });
  });
});
