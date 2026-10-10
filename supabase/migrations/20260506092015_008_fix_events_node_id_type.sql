
-- events.node_id must be text, not uuid.
-- Node IDs from inline requests are arbitrary strings (e.g. "plan-1").
-- Node IDs from the agents table are UUIDs.
-- text accepts both without casting errors.
-- No FK constraint exists on this column — safe to alter directly.

alter table events alter column node_id type text using node_id::text;
