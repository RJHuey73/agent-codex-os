/**
 * Structured failure taxonomy (blueprint §41.C, Appendix B "Error taxonomy" gap).
 *
 * A const object rather than a TS `enum` so the package runs under Node's
 * type stripping (`erasableSyntaxOnly`) with no build step.
 */
export const ErrorType = {
  LLM_FAILURE: "LLM_FAILURE",
  TOOL_FAILURE: "TOOL_FAILURE",
  TIMEOUT: "TIMEOUT",
  POLICY_VIOLATION: "POLICY_VIOLATION",
  BUDGET_EXCEEDED: "BUDGET_EXCEEDED",
  DAG_CYCLE: "DAG_CYCLE",
  DAG_INVALID: "DAG_INVALID",
  MEMORY_OVERFLOW: "MEMORY_OVERFLOW",
  CAPABILITY_DENIED: "CAPABILITY_DENIED",
  CONTRACT_INVALID: "CONTRACT_INVALID",
  UNKNOWN_NODE_TYPE: "UNKNOWN_NODE_TYPE",
  OBSERVABILITY_FAILURE: "OBSERVABILITY_FAILURE",
  INTERNAL: "INTERNAL",
} as const;

export type ErrorType = (typeof ErrorType)[keyof typeof ErrorType];

/** Types a retry may plausibly fix. Governance denials are never retryable. */
const RETRYABLE: ReadonlySet<ErrorType> = new Set([
  ErrorType.LLM_FAILURE,
  ErrorType.TOOL_FAILURE,
  ErrorType.TIMEOUT,
]);

export interface RuntimeErrorOptions {
  nodeId?: string;
  details?: Record<string, unknown>;
  cause?: unknown;
}

export class RuntimeError extends Error {
  readonly type: ErrorType;
  readonly nodeId: string | undefined;
  readonly details: Record<string, unknown>;
  readonly retryable: boolean;

  constructor(type: ErrorType, message: string, opts: RuntimeErrorOptions = {}) {
    super(message, opts.cause === undefined ? undefined : { cause: opts.cause });
    this.name = "RuntimeError";
    this.type = type;
    this.nodeId = opts.nodeId;
    this.details = opts.details ?? {};
    this.retryable = RETRYABLE.has(type);
  }

  /** Shape persisted into `events.payload` / `runs.error`. */
  toJSON(): { type: ErrorType; message: string; node_id: string | null; retryable: boolean; details: Record<string, unknown> } {
    return {
      type: this.type,
      message: this.message,
      node_id: this.nodeId ?? null,
      retryable: this.retryable,
      details: this.details,
    };
  }
}

/**
 * Normalise anything thrown into a RuntimeError. Unclassified errors become
 * `fallback` (the node's own failure class) rather than being silently dropped.
 */
export function classifyError(err: unknown, fallback: ErrorType, nodeId?: string): RuntimeError {
  if (err instanceof RuntimeError) return err;
  const message = err instanceof Error ? err.message : String(err);
  return new RuntimeError(fallback, message, nodeId === undefined ? { cause: err } : { nodeId, cause: err });
}
