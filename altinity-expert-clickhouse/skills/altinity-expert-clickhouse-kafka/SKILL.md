---
name: altinity-expert-clickhouse-kafka
description: Diagnose ClickHouse Kafka engine health, consumer status, thread pool capacity, and consumption issues. Use for Kafka lag, consumer errors, and thread starvation.
---

## Diagnostics

Run all queries from the file checks.sql and analyze the results.

## Interpreting Results

### Kafka Consumption Health

Check if consumers are stuck on errors by comparing exception time vs activity times:

```
if last_exception_time >= last_poll_time OR last_exception_time >= last_commit_time:
    → Consumer stuck on error, not progressing
else:
    → Consumer healthy
```

The `exceptions` column is a tuple of arrays with matching indices - getting `[-1]` from both `exceptions.time` and `exceptions.text` gives the most recent error.

### Thread Pool Capacity

Compare `kafka_consumers` vs `mb_pool_size`:

```
if kafka_consumers > mb_pool_size:
    → Thread starvation - consumers waiting for available threads
    → Consider increasing background_message_broker_schedule_pool_size
```

### Pool Utilization Over Time

The 12-hour pool task trend shows:
- Sustained high values near pool size → capacity pressure
- Spikes correlating with lag → temporary overload
- Flat zero → Kafka consumers may not be active

## Problem-Specific Investigation

### Kafka Consumer Exception Drill-Down (Targeted)

Use this only for problematic Kafka tables to avoid noisy output.

```sql
-- Filter to a specific Kafka table when lag is observed
SELECT
    hostName() AS host,
    database,
    table,
    consumer_id,
    is_currently_used,
    dateDiff('second', last_poll_time, now()) AS last_poll_age_s,
    dateDiff('second', last_commit_time, now()) AS last_commit_age_s,
    num_messages_read,
    num_commits,
    length(assignments.topic) AS assigned_partitions,
    length(exceptions.text) AS exception_count,
    exceptions.text[-1] AS last_exception
FROM clusterAllReplicas('{cluster}', system.kafka_consumers)
WHERE database = '{db}'
  AND table = '{kafka_table}'
ORDER BY is_currently_used DESC, last_poll_age_s DESC
LIMIT 50
```

### Check Current Consumption Speed

Measure real-time consumption rate by comparing two snapshots:

```sql
-- Step 1: Take a snapshot
CREATE TEMPORARY TABLE kafka_consumers_dump AS
SELECT now64(3) AS ts, * FROM system.kafka_consumers;

-- Step 2: Wait (adjust time as needed)
SELECT sleepEachRow(1) FROM numbers(60) SETTINGS max_block_size=1, max_threads=1 FORMAT Null;

-- Step 3: Calculate consumption rate
SELECT
    database,
    table,
    dateDiff('ms', old.ts, now64(3)) / 1000 AS time_since_dump,
    new.num_messages_read - old.num_messages_read AS delta_num_messages_read,
    delta_num_messages_read / time_since_dump AS per_sec
FROM system.kafka_consumers AS new
LEFT JOIN kafka_consumers_dump AS old USING (database, table, consumer_id)
ORDER BY per_sec
```

## Advanced Diagnostics: Topic Lag Measurement

To measure actual topic lag (messages behind), you need to enable librdkafka statistics gathering. This is **not enabled by default**.

### Enabling Statistics

Add to your Kafka table engine settings:

```xml
<kafka>
    <statistics_interval_ms>10000</statistics_interval_ms>
</kafka>
```

Once enabled, `system.kafka_consumers` will have a `rdkafka_stat` column (String type) containing detailed JSON statistics from librdkafka.

### Query: Total Consumer Lag per Table

This query parses the `rdkafka_stat` JSON to extract consumer lag per partition and calculates total lag:

```sql
WITH JSONExtract(
    rdkafka_stat,
    'Tuple(
        topics Map(String, Tuple(
            partitions Map(String, Tuple(
                partition Int64,
                consumer_lag Int64
            ))
        ))
    )'
) AS parsed_json,
    tupleElement(parsed_json, 'topics') AS topics_map,
    arrayMap(
        (topic) -> arrayMap(
            (partition) -> (
                topic,
                partition,
                tupleElement(tupleElement(topics_map[topic], 'partitions')[partition], 'consumer_lag')
            ),
            mapKeys(tupleElement(topics_map[topic], 'partitions'))
        ),
        mapKeys(topics_map)
    ) AS topics_details_tmp,
    arrayFlatten(topics_details_tmp) AS topics_details,
    arrayFilter(t -> t.3 <> -1, topics_details) AS lags,
    arraySum(arrayMap(t -> t.3, lags)) AS total_lag
SELECT
    hostName() AS host,
    database,
    table,
    total_lag
FROM clusterAllReplicas('{cluster}', system.kafka_consumers)
ORDER BY total_lag DESC
```

### Query: Detailed Lag per Partition

```sql
WITH JSONExtract(
    rdkafka_stat,
    'Tuple(
        topics Map(String, Tuple(
            partitions Map(String, Tuple(
                partition Int64,
                consumer_lag Int64,
                committed_offset Int64,
                hi_offset Int64,
                lo_offset Int64
            ))
        ))
    )'
) AS parsed_json,
    tupleElement(parsed_json, 'topics') AS topics_map
SELECT
    hostName() AS host,
    database,
    table,
    topic,
    partition,
    tupleElement(partition_data, 'consumer_lag') AS consumer_lag,
    tupleElement(partition_data, 'committed_offset') AS committed_offset,
    tupleElement(partition_data, 'hi_offset') AS hi_offset
FROM clusterAllReplicas('{cluster}', system.kafka_consumers)
ARRAY JOIN
    mapKeys(topics_map) AS topic,
    mapValues(topics_map) AS topic_data
ARRAY JOIN
    mapKeys(tupleElement(topic_data, 'partitions')) AS partition,
    mapValues(tupleElement(topic_data, 'partitions')) AS partition_data
WHERE tupleElement(partition_data, 'consumer_lag') <> -1
ORDER BY consumer_lag DESC
```

### Query: Broker Connection Health

```sql
WITH JSONExtract(
    rdkafka_stat,
    'Tuple(
        brokers Map(String, Tuple(
            state String,
            stateage Int64,
            tx Int64,
            rx Int64,
            txerrs Int64,
            rxerrs Int64,
            connects Int64,
            disconnects Int64
        ))
    )'
) AS parsed_json,
    tupleElement(parsed_json, 'brokers') AS brokers_map
SELECT
    hostName() AS host,
    database,
    table,
    broker,
    tupleElement(broker_data, 'state') AS state,
    tupleElement(broker_data, 'txerrs') AS tx_errors,
    tupleElement(broker_data, 'rxerrs') AS rx_errors,
    tupleElement(broker_data, 'connects') AS connects,
    tupleElement(broker_data, 'disconnects') AS disconnects
FROM clusterAllReplicas('{cluster}', system.kafka_consumers)
ARRAY JOIN
    mapKeys(brokers_map) AS broker,
    mapValues(brokers_map) AS broker_data
ORDER BY tx_errors + rx_errors DESC
```

## Troubleshooting Common Errors

### Topic Authorization Failed (ACL Errors)

If you see errors like this in logs:

```
error "Broker: Topic authorization failed"
Fetch from broker 2 failed: Broker: Topic authorization failed
```

This indicates missing Kafka ACLs. For brokers like AWS MSK or Confluent with SCRAM authentication or Multi-VPC, the default property blocks unauthorized access:

```properties
allow.everyone.if.no.acl.found = false
```

**Solution:** Explicitly create ACLs for topic/host/users:

```bash
kafka-acls --bootstrap-server <broker>:9096 \
  --command-config adminclient-configs.conf \
  --add \
  --allow-principal User:<username> \
  --allow-host <clickhouse-host> \
  --operation read \
  --operation describe \
  --topic <topic-name>
```

Required operations for ClickHouse Kafka consumers:
- `read` - consume messages
- `describe` - get topic metadata

### Application Maximum Poll Interval Exceeded

If you see errors like:

```
Application maximum poll interval (300000ms) exceeded by 176ms (adjust max.poll.interval.ms for long-running message processing): leaving group
```

This means the consumer is too slow to process messages within the poll interval, causing it to be kicked from the consumer group.

**Root cause:** ClickHouse Kafka engine uses librdkafka (C++ library). A consumer must process records within `max.poll.interval.ms` (default: 300000ms / 5 minutes). Slow consumers (large messages, complex MVs, slow disks) exceed this limit.

**Tuning options:**

1. **Increase `max.poll.interval.ms`** - gives more processing time, but slower rebalance detection
2. **Reduce batch size** - less data per poll, but lower throughput (more overhead)

For librdkafka, `max.poll.records` (Java property) doesn't exist directly, but batch size can be tuned via other settings: https://github.com/confluentinc/librdkafka/issues/1653

**Solution:** Increase `max.poll.interval.ms` in ClickHouse config. Start with small increments:

```xml
<kafka>
    <!-- Default is 300000 (5 min), increase to 480000 (8 min) -->
    <max_poll_interval_ms>480000</max_poll_interval_ms>
</kafka>
```

**References:**
- librdkafka configuration: https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md
- Altinity KB - Adjusting librdkafka settings: https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-adjusting-librdkafka-settings/

### Thread Pool Starvation (No Available Threads)

If consumers disconnect or you see poll interval warnings **not because ClickHouse fails to poll, but because there are no available threads**, the background pool is saturated.

**Symptoms:**
- Consumer group disconnections
- Poll interval exceeded warnings despite correct `max.poll.interval.ms`
- `BackgroundMessageBrokerSchedulePoolTask` equals `BackgroundMessageBrokerSchedulePoolSize`

**Solution:** Increase `background_message_broker_schedule_pool_size` (default: 16):

```xml
<!-- /etc/clickhouse-server/config.d/background_message_broker_schedule_pool_size.xml -->
<clickhouse>
    <background_message_broker_schedule_pool_size>32</background_message_broker_schedule_pool_size>
</clickhouse>
```

**Sizing formula:** Total Kafka consumers + RabbitMQ/NATS tables + 25% buffer.

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/background_message_broker_schedule_pool_size/

### Parsing Errors and Dead Letter Queue

For handling malformed messages without stopping consumption:

**Version 21.6+:** Stream errors to a separate table:

```sql
CREATE TABLE kafka_errors (
    topic String,
    partition UInt64,
    offset UInt64,
    raw_message String,
    error String,
    timestamp DateTime DEFAULT now()
) ENGINE = MergeTree ORDER BY (topic, timestamp);

CREATE MATERIALIZED VIEW kafka_errors_mv TO kafka_errors AS
SELECT
    _topic AS topic,
    _partition AS partition,
    _offset AS offset,
    _raw_message AS raw_message,
    _error AS error
FROM kafka_source
WHERE length(_error) > 0;
```

Enable with: `kafka_handle_error_mode='stream'`

**Version 25.8+:** Native dead letter queue support with `kafka_handle_error_mode='dead_letter'`

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/error-handling/

### Data Loss with Multiple Materialized Views

If multiple MVs attach to one Kafka table, early-starting MVs can consume data before other MVs load, causing data loss.

**Pre-25.5 Solution:** Disable async table loading:

```xml
<clickhouse>
    <async_load_databases>false</async_load_databases>
</clickhouse>
```

**Better pattern:** Use intermediate Null table:

```
KafkaTable → MV → NullTable → [MV1, MV2, ...] → [Table1, Table2, ...]
```

**Version 25.5+:** Native fix included.

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-kafka-mv-consuming/

### Rewind / Replay Offsets

To replay messages or skip to latest:

```bash
# Step 1: Detach table
DETACH TABLE kafka_table;

# Step 2: Reset offsets using Kafka CLI
kafka-consumer-groups.sh --bootstrap-server kafka:9092 \
    --topic my_topic --group clickhouse \
    --reset-offsets --to-earliest --execute

# Step 3: Reattach table
ATTACH TABLE kafka_table;
```

**Offset options:** `--to-earliest`, `--to-latest`, `--to-offset <N>`, `--shift-by <N>`

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-rewind-fast-forward-replay/

## Configuration Reference

### Parallel Consumption

For high-throughput topics, enable parallel consumers:

```sql
CREATE TABLE kafka_source (...)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'broker:9092',
    kafka_topic_list = 'topic',
    kafka_group_name = 'clickhouse',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 4,
    kafka_thread_per_consumer = 1;  -- Required for parallel inserts
```

**Constraints:**
- `kafka_num_consumers` limited by physical cores (use `kafka_disable_num_consumers_limit` to override)
- Ensure `background_message_broker_schedule_pool_size` >= total consumers
- Topic must have >= `kafka_num_consumers` partitions

**Reference:** https://kb.altinity.com/altinity-kb-integrations/altinity-kb-kafka/altinity-kb-kafka-parallel-consuming/

### Common librdkafka Settings

```xml
<kafka>
    <!-- Timeouts -->
    <max_poll_interval_ms>300000</max_poll_interval_ms>
    <session_timeout_ms>60000</session_timeout_ms>
    <heartbeat_interval_ms>10000</heartbeat_interval_ms>

    <!-- Message size -->
    <message_max_bytes>20971520</message_max_bytes>

    <!-- Debugging -->
    <debug>all</debug>

    <!-- SASL/SCRAM (AWS MSK) -->
    <security_protocol>sasl_ssl</security_protocol>
    <sasl_mechanism>SCRAM-SHA-512</sasl_mechanism>
    <sasl_username>user</sasl_username>
    <sasl_password>pass</sasl_password>
</kafka>
```

**Reference:** https://github.com/confluentinc/librdkafka/blob/master/CONFIGURATION.md
