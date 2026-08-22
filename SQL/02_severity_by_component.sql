-- Quick check: what columns exist in complaints_clean?
-- (confirming field names before building the severity analysis on top of them)

SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'complaints_clean';

-- Quick check: what values does CRASH/FIRE actually contain?
	SELECT DISTINCT CRASH FROM complaints_clean;
	SELECT DISTINCT FIRE FROM complaints_clean;


-- ============================================================
-- ANALYSIS 1: Complaint Severity by Component
-- Question: which components have the highest rate of severe
-- outcomes (crashes, fires, injuries, deaths) among complaints?
-- This tells us which defect types are riskiest in practice,
-- not just which are most commonly complained about.
-- ============================================================

SELECT
    COMPONENT_CLEAN,
    COUNT(*) AS total_complaints,
    SUM(CASE WHEN CRASH = 'Y' THEN 1 ELSE 0 END) AS crash_count,
    SUM(CASE WHEN FIRE = 'Y' THEN 1 ELSE 0 END) AS fire_count,
    SUM(INJURED) AS total_injured,
    SUM(DEATHS) AS total_deaths,
    CAST(100.0 * SUM(CASE WHEN CRASH = 'Y' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS pct_crash,
    CAST(100.0 * SUM(CASE WHEN FIRE = 'Y' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS pct_fire
FROM complaints_clean
GROUP BY COMPONENT_CLEAN
ORDER BY total_deaths DESC, total_injured DESC;