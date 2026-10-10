
UPDATE ccx_ingestion_queue
SET ingestion_status   = 'PENDING',
    dispatch_count     = 0,
    rejection_reason   = NULL,
    last_dispatched_at = NULL,
    processed_at       = NULL
WHERE ingestion_status IN ('REJECTED', 'FAILED', 'PENDING');
