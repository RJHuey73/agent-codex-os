
-- Option B: P5 Semantic Abstraction View
-- Resolves schema drift between P5 Node Spec Contract and live agent_messages substrate
-- P5 runtime queries this view — substrate columns untouched

CREATE OR REPLACE VIEW public.sfx_p5_agent_messages AS
SELECT
    id,
    trace_id,
    created_at,
    payload,
    from_agent   AS from_node,
    to_agent     AS to_node,
    type         AS message_type
FROM public.agent_messages;

COMMENT ON VIEW public.sfx_p5_agent_messages IS 'P5 semantic layer. Maps agent_messages substrate columns to P5 Node Spec Contract nomenclature (from_node, to_node, message_type). Substrate schema is immutable.';
