/**
 * In-process event broadcaster. SSE clients subscribe; CLI/HTTP writes emit.
 * No replay buffer — clients re-fetch state on (re)connect.
 */

export type EventKind =
  | "task.added"
  | "task.updated"
  | "task.removed"
  | "update.posted"
  | "lane.changed";

export type CortexEvent = {
  kind: EventKind;
  payload: unknown;
  ts: number;
};

export const bus: EventTarget = new EventTarget();

export function emit(ev: CortexEvent): void {
  bus.dispatchEvent(new CustomEvent("cortex", { detail: ev }));
}

export function subscribe(cb: (ev: CortexEvent) => void): () => void {
  const handler = (e: Event): void => {
    const ce = e as CustomEvent<CortexEvent>;
    cb(ce.detail);
  };
  bus.addEventListener("cortex", handler);
  return () => bus.removeEventListener("cortex", handler);
}
