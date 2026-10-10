
-- Reset REJECTED rows back to PENDING with dispatch_count=0 for clean retry
-- after fn-ccx-ingest v7 deploys with error surfacing
UPDATE ccx_ingestion_queue
SET ingestion_status   = 'PENDING',
    dispatch_count     = 0,
    rejection_reason   = NULL,
    last_dispatched_at = NULL,
    processed_at       = NULL
WHERE ingestion_status = 'REJECTED';
