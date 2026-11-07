/* ============================================================
   05  Are severe complaints followed by a recall more often
            or sooner?
   ------------------------------------------------------------
   Works per complaint (v2.complaint_outcomes), so each complaint
   counts once:

   - recalled_within_2y: share of complaints whose vehicle+component
     was recalled within 2 years of the complaint. Only complaints
     filed at least 2 years before the data extract are counted, so
     recent complaints don't look "never recalled" just because
     there hasn't been time (right-censoring).
   - median_days_to_recall: among complaints that were recalled
     within the lookback window.
   Significance tests are in notebook/02_analysis.ipynb.
   ============================================================ */
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW v2.vw_complaint_severity_outcome AS
SELECT o.*,
       CASE WHEN o.DEATHS  > 0 THEN '1 Fatal'
            WHEN o.INJURED > 0 THEN '2 Injury'
            WHEN o.CRASH   = 1 THEN '3 Crash, no injury'
            WHEN o.FIRE    = 1 THEN '4 Fire, no crash'
            ELSE '5 No crash, fire or injury' END AS SEVERITY_TIER,
       CASE WHEN o.NEXT_RECALL_DATE IS NOT NULL AND o.DAYS_TO_NEXT_RECALL <= 730 THEN 1 ELSE 0 END AS RECALLED_WITHIN_2Y
FROM v2.complaint_outcomes AS o
CROSS JOIN v2.params AS p
WHERE o.COMPLAINT_DATE >= '2000-01-01'
  AND o.COMPLAINT_DATE <= DATEADD(YEAR, -2, p.EXTRACT_DATE)
  AND o.COMPONENT_CLEAN NOT IN ('UNKNOWN OR OTHER', 'OTHER', 'FIRERELATED', 'ROLLOVER');
GO

CREATE OR ALTER VIEW v2.vw_severity_vs_recall AS
SELECT DISTINCT
    SEVERITY_TIER,
    COUNT(*)                OVER (PARTITION BY SEVERITY_TIER) AS complaints,
    AVG(1.0 * RECALLED_WITHIN_2Y) OVER (PARTITION BY SEVERITY_TIER) AS share_recalled_within_2y
FROM v2.vw_complaint_severity_outcome;
GO

SELECT s.SEVERITY_TIER, s.complaints,
       CAST(100 * s.share_recalled_within_2y AS DECIMAL(5,2)) AS pct_recalled_within_2y,
       m.median_days_to_recall, m.recalled_complaints
FROM v2.vw_severity_vs_recall AS s
LEFT JOIN (
    SELECT DISTINCT SEVERITY_TIER,
           COUNT(*) OVER (PARTITION BY SEVERITY_TIER) AS recalled_complaints,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DAYS_TO_NEXT_RECALL)
               OVER (PARTITION BY SEVERITY_TIER) AS median_days_to_recall
    FROM v2.vw_complaint_severity_outcome
    WHERE NEXT_RECALL_DATE IS NOT NULL
) AS m ON m.SEVERITY_TIER = s.SEVERITY_TIER
ORDER BY s.SEVERITY_TIER;

/* Same question, controlling for component: crash vs no crash within each top component */
SELECT o.COMPONENT_CLEAN,
       SUM(CASE WHEN CRASH = 1 THEN 1 ELSE 0 END) AS crash_complaints,
       CAST(100.0 * SUM(CASE WHEN CRASH = 1 THEN RECALLED_WITHIN_2Y END) / NULLIF(SUM(CASE WHEN CRASH = 1 THEN 1 END), 0) AS DECIMAL(5,2)) AS pct_recalled_2y_crash,
       CAST(100.0 * SUM(CASE WHEN CRASH = 0 THEN RECALLED_WITHIN_2Y END) / NULLIF(SUM(CASE WHEN CRASH = 0 THEN 1 END), 0) AS DECIMAL(5,2)) AS pct_recalled_2y_no_crash
FROM v2.vw_complaint_severity_outcome AS o
JOIN v2.scope_components AS s ON s.COMPONENT_CLEAN = o.COMPONENT_CLEAN
GROUP BY o.COMPONENT_CLEAN
ORDER BY o.COMPONENT_CLEAN;
