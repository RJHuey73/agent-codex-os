import { test } from "node:test";
import assert from "node:assert/strict";
import { ErrorType, RuntimeError, topoSort } from "../src/index.ts";

const ids = (ns: { id: string }[]) => ns.map((n) => n.id);
const isType = (t: string) => (e: unknown) => e instanceof RuntimeError && e.type === t;

test("orders dependencies before dependents, deterministically", () => {
  const nodes = [
    { id: "c", type: "evaluator", depends_on: ["a", "b"] },
    { id: "a", type: "planner" },
    { id: "b", type: "worker", depends_on: ["a"] },
  ];
  assert.deepEqual(ids(topoSort(nodes)), ["a", "b", "c"]);
  assert.deepEqual(ids(topoSort(nodes)), ids(topoSort(nodes)));
});

test("independent nodes keep input order", () => {
  assert.deepEqual(ids(topoSort([{ id: "x", type: "worker" }, { id: "y", type: "worker" }])), ["x", "y"]);
});

test("rejects cycles (blueprint topoSort accepted them silently)", () => {
  assert.throws(
    () => topoSort([{ id: "a", type: "worker", depends_on: ["b"] }, { id: "b", type: "worker", depends_on: ["a"] }, { id: "c", type: "worker" }]),
    (e: unknown) => isType(ErrorType.DAG_CYCLE)(e) && JSON.stringify((e as RuntimeError).details) === '{"nodes":["a","b"]}',
  );
  assert.throws(() => topoSort([{ id: "a", type: "worker", depends_on: ["a"] }]), isType(ErrorType.DAG_CYCLE));
});

test("rejects unknown dependencies, duplicate ids, and oversize DAGs", () => {
  assert.throws(() => topoSort([{ id: "a", type: "worker", depends_on: ["ghost"] }]), isType(ErrorType.DAG_INVALID));
  assert.throws(() => topoSort([{ id: "a", type: "worker" }, { id: "a", type: "worker" }]), isType(ErrorType.DAG_INVALID));
  assert.throws(() => topoSort([{ id: "a", type: "worker" }, { id: "b", type: "worker" }], 1), isType(ErrorType.DAG_INVALID));
});
