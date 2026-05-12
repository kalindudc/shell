import { test, expect, describe } from "bun:test";
import { Store } from "../store.ts";

const open = () => Store.open(":memory:");

describe("Store: tasks", () => {
  test("addTask + getTask + listTasks round-trip", () => {
    const s = open();
    const t = s.addTask({ title: "first" });
    expect(t.id).toBeGreaterThan(0);
    expect(t.lane).toBe("now");
    expect(t.status).toBe("open");
    expect(s.getTask(t.id)?.title).toBe("first");
    expect(s.listTasks().length).toBe(1);
    s.close();
  });

  test("listTasks filters by lane and status", () => {
    const s = open();
    s.addLane({ name: "later" });
    s.addTask({ title: "a", lane: "now" });
    s.addTask({ title: "b", lane: "later" });
    const t3 = s.addTask({ title: "c", lane: "now" });
    s.setStatus(t3.id, "done");
    expect(s.listTasks({ lane: "now" }).length).toBe(2);
    expect(s.listTasks({ lane: "later" }).length).toBe(1);
    expect(s.listTasks({ status: "done" }).length).toBe(1);
    expect(s.listTasks({ lane: "now", status: "open" }).length).toBe(1);
    s.close();
  });

  test("listTasks orders by priority ASC (0 = highest, sorts first)", () => {
    const s = open();
    s.addTask({ title: "normal", priority: 1 });
    s.addTask({ title: "top", priority: 0 });
    s.addTask({ title: "low", priority: 5 });
    const order = s.listTasks().map((t) => t.title);
    expect(order).toEqual(["top", "normal", "low"]);
    s.close();
  });

  test("editTask updates only provided fields and bumps updated", async () => {
    const s = open();
    const t = s.addTask({ title: "x", body: "orig", priority: 1 });
    await Bun.sleep(2);
    const edited = s.editTask(t.id, { title: "y" });
    expect(edited.title).toBe("y");
    expect(edited.body).toBe("orig");
    expect(edited.priority).toBe(1);
    expect(edited.updated).toBeGreaterThan(t.updated);
    s.close();
  });

  test("moveTask succeeds for existing lane and auto-creates missing lane", () => {
    const s = open();
    s.addLane({ name: "later" });
    const t = s.addTask({ title: "x" });
    const moved = s.moveTask(t.id, "later");
    expect(moved.lane).toBe("later");
    // missing lane is auto-created with defaults
    const moved2 = s.moveTask(t.id, "new-lane");
    expect(moved2.lane).toBe("new-lane");
    const lane = s.listLanes().find((l) => l.name === "new-lane");
    expect(lane?.wip_limit).toBe(3);
    expect(lane?.color).toBeNull();
    s.close();
  });

  test("addTask auto-creates missing lane", () => {
    const s = open();
    const t = s.addTask({ title: "x", lane: "fresh" });
    expect(t.lane).toBe("fresh");
    expect(s.listLanes().some((l) => l.name === "fresh")).toBe(true);
    s.close();
  });

  test("setStatus mutates only the targeted row", () => {
    const s = open();
    const a = s.addTask({ title: "a" });
    const b = s.addTask({ title: "b" });
    s.setStatus(a.id, "done");
    expect(s.getTask(a.id)?.status).toBe("done");
    expect(s.getTask(b.id)?.status).toBe("open");
    s.close();
  });

  test("removeTask cascades updates via foreign_keys=ON", () => {
    const s = open();
    const t = s.addTask({ title: "x" });
    s.addUpdate({ task_id: t.id, author: "me", summary: "hi" });
    s.addUpdate({ task_id: t.id, author: "me", summary: "ho" });
    expect(s.listUpdates(t.id).length).toBe(2);
    s.removeTask(t.id);
    expect(s.getTask(t.id)).toBeNull();
    expect(s.listUpdates(t.id).length).toBe(0);
    s.close();
  });
});

describe("Store: updates", () => {
  test("addUpdate accepts 200-char summary, throws on 201", () => {
    const s = open();
    const t = s.addTask({ title: "x" });
    expect(() =>
      s.addUpdate({ task_id: t.id, author: "me", summary: "x".repeat(200) }),
    ).not.toThrow();
    expect(() =>
      s.addUpdate({ task_id: t.id, author: "me", summary: "x".repeat(201) }),
    ).toThrow("summary too long");
    s.close();
  });
});

describe("Store: lanes", () => {
  test("add/list/edit/remove lifecycle", () => {
    const s = open();
    expect(s.listLanes().map((l) => l.name)).toEqual(["now"]);
    s.addLane({ name: "later", color: "#abc", wip_limit: 5 });
    expect(s.listLanes().length).toBe(2);
    const edited = s.editLane("later", { wip_limit: 7 });
    expect(edited.wip_limit).toBe(7);
    s.removeLane("later");
    expect(s.listLanes().length).toBe(1);
    s.close();
  });

  test("removeLane refuses 'now' and non-empty lanes", () => {
    const s = open();
    expect(() => s.removeLane("now")).toThrow(/cannot remove the 'now' lane/);
    s.addLane({ name: "later" });
    s.addTask({ title: "x", lane: "later" });
    expect(() => s.removeLane("later")).toThrow(/task\(s\) reference it/);
    s.close();
  });

  test("rename lane cascades to tasks via ON UPDATE CASCADE", () => {
    const s = open();
    s.addLane({ name: "later" });
    const t = s.addTask({ title: "x", lane: "later" });
    s.editLane("later", { rename: "soon" });
    expect(s.listLanes().some((l) => l.name === "soon")).toBe(true);
    expect(s.getTask(t.id)?.lane).toBe("soon");
    s.close();
  });
});
