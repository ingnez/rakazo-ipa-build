import { ORPCError } from "@orpc/server";
import type { ScenarioModelsView } from "@rakazo/contracts";
import { appContract, SCENARIO_DEFAULT_THINKING, SCENARIO_SLOTS } from "@rakazo/contracts";
import { getLogger } from "@rakazo/logging";
import { markExpectedFailure } from "@rakazo/logging/hono";

type Node = Record<string, unknown>;

const isProcedure = (node: unknown): node is Node =>
  Boolean(node) && typeof node === "object" && "~orpc" in (node as Node);

const hasHandler = (node: unknown): boolean =>
  isProcedure(node) && typeof (node as { "~orpc": { handler?: unknown } })["~orpc"].handler === "function";

/**
 * Scenes with nothing chosen: every scene follows the daily model and none resolves to one.
 * What a server answers when it has no scene settings yet, so the Models page draws its six
 * scenes instead of hitting an error.
 */
export function emptyScenarioModels(): ScenarioModelsView {
  return {
    slots: SCENARIO_SLOTS.map((slot) => ({
      slot,
      primary: null,
      backups: [],
      source: "none" as const,
      thinkingLevel: slot === "daily" ? null : SCENARIO_DEFAULT_THINKING[slot],
      resolved: null,
    })),
  };
}

/** `models/scenarios` -> ["models", "scenarios"] for each contract procedure, in order. */
export function contractProcedurePaths(node: unknown = appContract, path: string[] = []): string[][] {
  if (isProcedure(node)) return [path];
  if (!node || typeof node !== "object") return [];
  return Object.entries(node as Node).flatMap(([key, child]) =>
    contractProcedurePaths(child, [...path, key]),
  );
}

/**
 * The contract can name a procedure this server build has no handler for (a client built
 * against a newer contract, or a fork's procedure). oRPC answers such a call with an opaque
 * 500 and reports it as a crash. Give every missing one a handler that answers 501 with a
 * plain message and logs a warning, and give the scene list a real empty answer.
 *
 * `authed` is the signed-in implementer; `routes` is the router object built from the real
 * handlers. Real handlers are kept as they are.
 */
// biome-ignore lint/suspicious/noExplicitAny: the filled router has the full contract's shape, which the partial spread cannot express
export function withUnimplementedProcedures(authed: unknown, routes: unknown): any {
  const fill = (contract: unknown, built: unknown, implementer: unknown, path: string[]): unknown => {
    if (isProcedure(contract)) {
      if (hasHandler(built)) return built;
      const name = path.join("/");
      const builder = implementer as { handler: (fn: () => unknown) => unknown };
      if (name === "models/scenarios") return builder.handler(() => emptyScenarioModels());
      return builder.handler(() => {
        getLogger().warn(`rpc ${name} is not implemented on this server`);
        markExpectedFailure();
        throw new ORPCError("NOT_IMPLEMENTED", {
          message: `${name} is not available on this server`,
        });
      });
    }
    const out: Node = {};
    for (const [key, child] of Object.entries(contract as Node)) {
      out[key] = fill(
        child,
        (built as Node | undefined)?.[key],
        (implementer as Node)[key],
        [...path, key],
      );
    }
    return out;
  };
  return fill(appContract, routes, authed, []);
}
