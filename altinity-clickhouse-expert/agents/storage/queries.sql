-- Query 1: Disk free space
SELECT
    name,
    path,
    formatReadableSize(total_space) AS total,
    formatReadableSize(free_space) AS free,
    round(100.0 * free_space / nullIf(total_space, 0), 1) AS free_pct
FROM system.disks
ORDER BY free_space ASC;

-- Query 2: Biggest tables by bytes on disk
SELECT
    database,
    table,
    formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk,
    count() AS parts,
    formatReadableSize(avg(bytes_on_disk)) AS avg_part_size
FROM system.parts
WHERE active
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC
LIMIT 30;

-- Query 3: Tiny parts hotlist (IO amplification risk)
SELECT
    database,
    table,
    countIf(bytes_on_disk < 16 * 1024 * 1024) AS tiny_parts,
    count() AS total_parts,
    round(100.0 * tiny_parts / nullIf(total_parts, 0), 1) AS tiny_pct
FROM system.parts
WHERE active
GROUP BY database, table
HAVING total_parts >= 50
ORDER BY tiny_pct DESC, total_parts DESC
LIMIT 30;

-- Query 4: System log tables disk usage
SELECT
    database,
    table,
    formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk,
    count() AS parts,
    min(modification_time) AS oldest_part,
    max(modification_time) AS newest_part
FROM system.parts
WHERE active
  AND database = 'system'
  AND table LIKE '%_log%'
GROUP BY database, table
ORDER BY sum(bytes_on_disk) DESC
LIMIT 20;
