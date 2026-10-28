import assert from "node:assert/strict";

// The small Pi surface exercised by these subprocess scenarios. Pi's production
// import is type-only, so running them needs Node, not an installed Pi package.
export type LifecycleName = "session_start" | "before_agent_start" | "session_shutdown";
export type NoticeKind = "info" | "warning" | "error";
export type Notice = { text: string; kind: NoticeKind | undefined };
export type FixtureContext = {
  ui: { notify(text: string, kind?: NoticeKind): void };
};
// Only start/shutdown are dispatched here; neither handler reads event fields.
export type LifecycleHandler = (event: object, ctx: FixtureContext) => void | Promise<void>;
export type FixtureAPI = {
  on(name: LifecycleName, handler: LifecycleHandler): void;
  registerCommand?(name: string, command: {
    description: string;
    handler(args: string, ctx: FixtureContext): void | Promise<void>;
  }): void;
  sendUserMessage(text: string, options: { deliverAs: "followUp" }): void | Promise<void>;
};

export function required<T>(value: T | undefined, name: string): T {
  assert.ok(value !== undefined, `missing ${name}`);
  return value;
}

export function env(name: string): string {
  return required(process.env[name], name);
}

// The dynamic path loads the actual checkout extension. This annotation is the
// unchecked module boundary, not a claim to type-check Pi or production code.
const extensionModule: { default(pi: FixtureAPI): void } = await import(env("RIDDIM_EXTENSION"));
export const extension = extensionModule.default;

export function parseRecord(json: string): Record<string, unknown> {
  const value: unknown = JSON.parse(json);
  assert.ok(value !== null && typeof value === "object" && !Array.isArray(value));
  return Object.fromEntries(Object.entries(value));
}

export function notificationIds(json: string): string[] {
  const rows: unknown = JSON.parse(json);
  assert.ok(Array.isArray(rows));
  return rows.map((row: unknown) => {
    assert.ok(row !== null && typeof row === "object" && "id" in row);
    assert.ok(typeof row.id === "string");
    return row.id;
  });
}
