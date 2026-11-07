/* ============================================================
   03  Complaint severity by component
   ------------------------------------------------------------
   Question: which components produce the most harmful complaints,
   both in total and per complaint?

   Method
   - One complaint (ODINO) can appear on many rows (one per component
     line), so summing DEATHS/INJURED over rows would count the same
     deaths several times. Each complaint is counted once per component.
   - Raw totals mostly track complaint volume, so rates per 1,000
     complaints are reported alongside them.
   Note: a complaint naming two components is counted under both, so the
   component rows can add up to more than the overall total.
   ============================================================ */
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW v2.vw_severity_by_component AS
WITH per_complaint AS (
    SELECT ODINO, COMPONENT_CLEAN,
           MAX(CRASH) AS CRASH, MAX(FIRE) AS FIRE, MAX(INJURED) AS INJURED, MAX(DEATHS) AS DEATHS
    FROM v2.complaints
    GROUP BY ODINO, COMPONENT_CLEAN
)
SELECT COMPONENT_CLEAN,
       COUNT(*)                                              AS complaints,
       SUM(CRASH)                                            AS crash_complaints,
       SUM(FIRE)                                             AS fire_complaints,
       SUM(CASE WHEN INJURED > 0 THEN 1 ELSE 0 END)          AS injury_complaints,
       SUM(CASE WHEN DEATHS  > 0 THEN 1 ELSE 0 END)          AS fatal_complaints,
       SUM(INJURED)                                          AS people_injured,
       SUM(DEATHS)                                           AS deaths,
       CAST(100.0  * SUM(CRASH) / COUNT(*) AS DECIMAL(6,2))  AS pct_crash,
       CAST(100.0  * SUM(FIRE)  / COUNT(*) AS DECIMAL(6,2))  AS pct_fire,
       CAST(1000.0 * SUM(INJURED) / COUNT(*) AS DECIMAL(8,2)) AS injured_per_1000,
       CAST(1000.0 * SUM(DEATHS)  / COUNT(*) AS DECIMAL(8,2)) AS deaths_per_1000
FROM per_complaint
GROUP BY COMPONENT_CLEAN;
GO

/* Overall totals, each complaint counted exactly once */
CREATE OR ALTER VIEW v2.vw_severity_totals AS
WITH per_complaint AS (
    SELECT ODINO, MAX(CRASH) AS CRASH, MAX(FIRE) AS FIRE, MAX(INJURED) AS INJURED, MAX(DEATHS) AS DEATHS
    FROM v2.complaints GROUP BY ODINO
)
SELECT COUNT(*) AS complaints, SUM(CRASH) AS crash_complaints, SUM(FIRE) AS fire_complaints,
       SUM(INJURED) AS people_injured, SUM(DEATHS) AS deaths
FROM per_complaint;
GO

-- Ranked by deaths per 1,000 complaints, components with at least 1,000 complaints
SELECT * FROM v2.vw_severity_by_component
WHERE complaints >= 1000
ORDER BY deaths_per_1000 DESC;

SELECT * FROM v2.vw_severity_totals;
