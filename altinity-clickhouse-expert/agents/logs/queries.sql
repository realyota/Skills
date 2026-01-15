-- Query 1: System log tables disk usage (top by bytes)
SELECT
    database,
    table,
    formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk,
    count() AS parts
FROM system.parts
WHERE active
  AND database = 'system'
  AND table LIKE '%_log%'
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC
LIMIT 50;

-- Query 2: Oldest/newest parts for system log tables (retention hints)
SELECT
    table,
    min(modification_time) AS oldest_part,
    max(modification_time) AS newest_part
FROM system.parts
WHERE active
  AND database = 'system'
  AND table LIKE '%_log%'
GROUP BY table
ORDER BY oldest_part ASC
LIMIT 50;

-- Query 3: System log tables with many parts (churn)
SELECT
    table,
    count() AS parts,
    round(avg(bytes_on_disk)) AS avg_part_bytes
FROM system.parts
WHERE active
  AND database = 'system'
  AND table LIKE '%_log%'
GROUP BY table
ORDER BY parts DESC
LIMIT 50;

