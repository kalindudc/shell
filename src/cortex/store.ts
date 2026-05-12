import { Database } from "bun:sqlite";
import { dbPath, ensureConfigDir } from "./paths.ts";

export type TaskStatus = "open" | "review" | "blocked" | "done";
export type Severity = "progress" | "review" | "blocked";

export type Task = {
  id: number;
  lane: string;
  title: string;
  body: string | null;
  status: TaskStatus;
  priority: number;
  created: number;
  updated: number;
};

export type Update = {
  id: number;
  task_id: number;
  author: string;
  summary: string;
  body: string | null;
  severity: Severity;
  created: number;
};

export type Lane = {
  name: string;
  color: string | null;
  wip_limit: number;
  sort: number;
};

export type AddTaskInput = {
  title: string;
  lane?: string;
  body?: string | null;
  priority?: number;
  status?: TaskStatus;
};

export type EditTaskFields = {
  title?: string;
  body?: string | null;
  priority?: number;
};

export type AddUpdateInput = {
  task_id: number;
  author: string;
  summary: string;
  body?: string | null;
};

export type AddLaneInput = {
  name: string;
  color?: string | null;
  wip_limit?: number;
  sort?: number;
};

export type EditLaneFields = {
  color?: string | null;
  wip_limit?: number;
  sort?: number;
  /** new lane name. ON UPDATE CASCADE propagates to tasks.lane FK. */
  rename?: string;
};

export type ListTasksFilter = {
  lane?: string;
  status?: TaskStatus;
};

const now = (): number => Date.now();

export class Store {
  private constructor(private readonly db: Database) {}

  static open(path: string = dbPath()): Store {
    if (path !== ":memory:") {
      ensureConfigDir();
    }
    const db = new Database(path, { strict: true, create: true });
    db.run("PRAGMA journal_mode = WAL;");
    db.run("PRAGMA foreign_keys = ON;");
    const store = new Store(db);
    store.migrate();
    return store;
  }

  migrate(): void {
    this.db.transaction(() => {
      this.db.run(`
        CREATE TABLE IF NOT EXISTS lanes (
          name      TEXT PRIMARY KEY,
          color     TEXT,
          wip_limit INTEGER NOT NULL DEFAULT 3,
          sort      INTEGER NOT NULL DEFAULT 0
        );
      `);
      this.db.run(`
        CREATE TABLE IF NOT EXISTS tasks (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          lane     TEXT    NOT NULL DEFAULT 'now',
          title    TEXT    NOT NULL,
          body     TEXT,
          status   TEXT    NOT NULL DEFAULT 'open'
                   CHECK(status IN ('open','review','blocked','done')),
          priority INTEGER NOT NULL DEFAULT 1,
          created  INTEGER NOT NULL,
          updated  INTEGER NOT NULL,
          FOREIGN KEY(lane) REFERENCES lanes(name) ON UPDATE CASCADE
        );
      `);
      this.db.run(`
        CREATE TABLE IF NOT EXISTS updates (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id  INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
          author   TEXT    NOT NULL,
          summary  TEXT    NOT NULL CHECK(length(summary) <= 200),
          body     TEXT,
          severity TEXT    NOT NULL
                   CHECK(severity IN ('progress','review','blocked')),
          created  INTEGER NOT NULL
        );
      `);
      this.db.run(
        `INSERT OR IGNORE INTO lanes (name, color, wip_limit, sort)
         VALUES ('now', '#fe8019', 3, 0);`,
      );
    })();
  }

  // ---------- task methods ----------

  /**
   * Idempotently create a lane with default settings if it doesn't exist.
   * Used by addTask/moveTask so callers don't have to pre-create lanes.
   */
  private ensureLane(name: string): void {
    this.db.run(
      `INSERT OR IGNORE INTO lanes (name, color, wip_limit, sort)
       VALUES (?, NULL, 3, 0);`,
      [name],
    );
  }

  addTask(input: AddTaskInput): Task {
    const ts = now();
    const lane = input.lane ?? "now";
    const status: TaskStatus = input.status ?? "open";
    const priority = input.priority ?? 1;
    const body = input.body ?? null;
    return this.db.transaction(() => {
      this.ensureLane(lane);
      const row = this.db
        .query<Task, [string, string, string | null, TaskStatus, number, number, number]>(
          `INSERT INTO tasks (lane, title, body, status, priority, created, updated)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           RETURNING *;`,
        )
        .get(lane, input.title, body, status, priority, ts, ts);
      if (!row) throw new Error("failed to insert task");
      return row;
    })();
  }

  listTasks(filter: ListTasksFilter = {}): Task[] {
    const clauses: string[] = [];
    const params: Array<string> = [];
    if (filter.lane) {
      clauses.push("lane = ?");
      params.push(filter.lane);
    }
    if (filter.status) {
      clauses.push("status = ?");
      params.push(filter.status);
    }
    const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
    // priority ASC so 0 (highest) sorts first; tie-break by oldest-created.
    const sql = `SELECT * FROM tasks ${where} ORDER BY priority ASC, created ASC;`;
    return this.db.query<Task, string[]>(sql).all(...params);
  }

  getTask(id: number): Task | null {
    const row = this.db
      .query<Task, [number]>(`SELECT * FROM tasks WHERE id = ?;`)
      .get(id);
    return row ?? null;
  }

  editTask(id: number, fields: EditTaskFields): Task {
    const sets: string[] = [];
    const params: Array<string | number | null> = [];
    if (fields.title !== undefined) {
      sets.push("title = ?");
      params.push(fields.title);
    }
    if (fields.body !== undefined) {
      sets.push("body = ?");
      params.push(fields.body);
    }
    if (fields.priority !== undefined) {
      sets.push("priority = ?");
      params.push(fields.priority);
    }
    if (sets.length === 0) {
      const existing = this.getTask(id);
      if (!existing) throw new Error(`task ${id} not found`);
      return existing;
    }
    sets.push("updated = ?");
    params.push(now());
    params.push(id);
    const sql = `UPDATE tasks SET ${sets.join(", ")} WHERE id = ? RETURNING *;`;
    const row = this.db.query<Task, (string | number | null)[]>(sql).get(...params);
    if (!row) throw new Error(`task ${id} not found`);
    return row;
  }

  moveTask(id: number, lane: string): Task {
    const existing = this.getTask(id);
    if (!existing) throw new Error(`task ${id} not found`);
    const ts = now();
    return this.db.transaction(() => {
      this.ensureLane(lane);
      const row = this.db
        .query<Task, [string, number, number]>(
          `UPDATE tasks SET lane = ?, updated = ? WHERE id = ? RETURNING *;`,
        )
        .get(lane, ts, id);
      if (!row) throw new Error(`task ${id} not found`);
      return row;
    })();
  }

  setStatus(id: number, status: TaskStatus): Task {
    const ts = now();
    const row = this.db
      .query<Task, [TaskStatus, number, number]>(
        `UPDATE tasks SET status = ?, updated = ? WHERE id = ? RETURNING *;`,
      )
      .get(status, ts, id);
    if (!row) throw new Error(`task ${id} not found`);
    return row;
  }

  removeTask(id: number): void {
    const existing = this.getTask(id);
    if (!existing) throw new Error(`task ${id} not found`);
    this.db.run(`DELETE FROM tasks WHERE id = ?;`, [id]);
  }

  // ---------- update methods ----------

  addUpdate(input: AddUpdateInput): Update {
    const ts = now();
    // Schema requires a non-null severity; we always write 'progress' in Plan 1.
    // Plan 3 will re-introduce a CLI/API surface for routed alerting badges.
    const severity: Severity = "progress";
    const body = input.body ?? null;
    try {
      const row = this.db
        .query<Update, [number, string, string, string | null, Severity, number]>(
          `INSERT INTO updates (task_id, author, summary, body, severity, created)
           VALUES (?, ?, ?, ?, ?, ?)
           RETURNING *;`,
        )
        .get(input.task_id, input.author, input.summary, body, severity, ts);
      if (!row) throw new Error("failed to insert update");
      return row;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes("CHECK constraint failed")) {
        throw new Error("summary too long");
      }
      throw err;
    }
  }

  listUpdates(taskId: number): Update[] {
    return this.db
      .query<Update, [number]>(
        `SELECT * FROM updates WHERE task_id = ? ORDER BY created ASC;`,
      )
      .all(taskId);
  }

  // ---------- lane methods ----------

  addLane(input: AddLaneInput): Lane {
    const color = input.color ?? null;
    const wip = input.wip_limit ?? 3;
    const sort = input.sort ?? 0;
    const row = this.db
      .query<Lane, [string, string | null, number, number]>(
        `INSERT INTO lanes (name, color, wip_limit, sort)
         VALUES (?, ?, ?, ?)
         RETURNING *;`,
      )
      .get(input.name, color, wip, sort);
    if (!row) throw new Error("failed to insert lane");
    return row;
  }

  listLanes(): Lane[] {
    return this.db
      .query<Lane, []>(`SELECT * FROM lanes ORDER BY sort ASC, name ASC;`)
      .all();
  }

  editLane(name: string, fields: EditLaneFields): Lane {
    return this.db.transaction(() => {
      const sets: string[] = [];
      const params: Array<string | number | null> = [];
      if (fields.color !== undefined) {
        sets.push("color = ?");
        params.push(fields.color);
      }
      if (fields.wip_limit !== undefined) {
        sets.push("wip_limit = ?");
        params.push(fields.wip_limit);
      }
      if (fields.sort !== undefined) {
        sets.push("sort = ?");
        params.push(fields.sort);
      }
      if (fields.rename !== undefined) {
        sets.push("name = ?");
        params.push(fields.rename);
      }
      if (sets.length === 0) {
        const existing = this.db
          .query<Lane, [string]>(`SELECT * FROM lanes WHERE name = ?;`)
          .get(name);
        if (!existing) throw new Error(`lane ${name} not found`);
        return existing;
      }
      params.push(name);
      const sql = `UPDATE lanes SET ${sets.join(", ")} WHERE name = ? RETURNING *;`;
      const row = this.db
        .query<Lane, (string | number | null)[]>(sql)
        .get(...params);
      if (!row) throw new Error(`lane ${name} not found`);
      return row;
    })();
  }

  removeLane(name: string): void {
    if (name === "now") {
      throw new Error("cannot remove the 'now' lane");
    }
    const refs = this.db
      .query<{ n: number }, [string]>(
        `SELECT COUNT(*) AS n FROM tasks WHERE lane = ?;`,
      )
      .get(name);
    if (refs && refs.n > 0) {
      throw new Error(`cannot remove lane '${name}': ${refs.n} task(s) reference it`);
    }
    const existing = this.db
      .query<Lane, [string]>(`SELECT * FROM lanes WHERE name = ?;`)
      .get(name);
    if (!existing) throw new Error(`lane ${name} not found`);
    this.db.run(`DELETE FROM lanes WHERE name = ?;`, [name]);
  }

  close(): void {
    this.db.close();
  }
}
