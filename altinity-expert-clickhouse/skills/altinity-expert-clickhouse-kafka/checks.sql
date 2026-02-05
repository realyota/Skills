-- Kafka Consumption Health
-- Red flag: last_exception_time >= last_poll_time OR last_commit_time → consumer stuck on error
SELECT
    hostName() AS host,
    database,
    table,
    formatReadableQuantity(num_messages_read) AS num_messages_read,
    last_poll_time,
    last_commit_time,
    last_rebalance_time,
    is_currently_used,
    exceptions.time[-1] AS last_exception_time,
    left(exceptions.text[-1], 100) AS last_exception_text
FROM clusterAllReplicas('{cluster}', system.kafka_consumers)
ORDER BY last_rebalance_time DESC, host ASC
;

-- Avg Rows per Commit
-- Shows batch efficiency per consumer
SELECT
    hostName() AS host,
    database,
    `table`,
    length(assignments.topic) AS assigned_partitions,
    num_messages_read / num_commits AS avg_rows_per_commit
FROM clusterAllReplicas('{cluster}', system.kafka_consumers)
ORDER BY database ASC, `table` ASC, host ASC
;

-- Rebalances and Assignments
-- High num_rebalance_assignments/revocations or recent last_rebalance → instability
SELECT
    hostName() AS host,
    database,
    `table`,
    length(assignments.partition_id) AS partitions_assigned,
    formatReadableTimeDelta(now() - last_rebalance_time) AS last_rebalance,
    num_rebalance_assignments,
    num_rebalance_revocations,
    uptime()
FROM clusterAllReplicas('{cluster}', system.kafka_consumers)
ORDER BY last_rebalance_time DESC, host ASC
;

-- Kafka Consumers vs Pool Size
-- Red flag: kafka_consumers > mb_pool_size → thread starvation, consumers waiting for threads
SELECT
    hostName() AS host,
    sumIf(value, metric = 'KafkaConsumers') AS kafka_consumers,
    sumIf(value, metric = 'BackgroundMessageBrokerSchedulePoolSize') AS mb_pool_size
FROM clusterAllReplicas('{cluster}', system.metrics)
WHERE metric IN ('KafkaConsumers', 'BackgroundMessageBrokerSchedulePoolSize')
GROUP BY host
ORDER BY host
;

-- Background Message Broker Pool Over Time (12h)
-- Shows pool task utilization trends to detect thread starvation patterns
SELECT
    hostName() AS host,
    toStartOfMinute(event_time) AS time_bucket,
    min(CurrentMetric_BackgroundMessageBrokerSchedulePoolTask) AS min_kafka_broker_pool,
    max(CurrentMetric_BackgroundMessageBrokerSchedulePoolTask) AS max_kafka_broker_pool
FROM clusterAllReplicas('{cluster}', system.metric_log)
WHERE event_time BETWEEN now() - INTERVAL 12 HOUR AND now()
GROUP BY host, time_bucket
ORDER BY time_bucket ASC, host ASC
;

-- Kafka-related messages in logs
SELECT
    hostName() AS host,
    event_time,
    level,
    message
FROM clusterAllReplicas('{cluster}', system.text_log)
WHERE logger_name LIKE '%Kafka%'
  AND event_time > now() - INTERVAL 1 HOUR
ORDER BY event_time DESC, host ASC
LIMIT 50
;
