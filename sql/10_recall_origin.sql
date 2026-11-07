/* ============================================================
   10  Manufacturer-initiated vs NHTSA-influenced recalls
   ------------------------------------------------------------
   NHTSA records whether a recall was influenced by its Office of
   Defects Investigation (INFLUENCED_BY = ODI / OVSC / ISSUE_INVGSTN)
   or started by the manufacturer (MFR).

   Question: do recalls that needed regulator pressure take longer
   and come after more owner complaints than recalls manufacturers
   start themselves?
   ============================================================ */
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW v2.vw_lag_by_origin AS
SELECT DISTINCT
    RECALL_ORIGIN,
    COUNT(*) OVER (PARTITION BY RECALL_ORIGIN) AS campaigns,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)   OVER (PARTITION BY RECALL_ORIGIN) AS median_lag_first,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY PRIOR_COMPLAINTS) OVER (PARTITION BY RECALL_ORIGIN) AS median_prior_complaints,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY UNITS_AFFECTED)   OVER (PARTITION BY RECALL_ORIGIN) AS median_units_affected
FROM v2.vw_lag_campaigns;
GO

/* All campaigns in the window (including those with no prior complaint) */
CREATE OR ALTER VIEW v2.vw_origin_summary AS
SELECT RECALL_ORIGIN,
       COUNT(*) AS campaigns,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1))          AS pct_of_campaigns,
       SUM(UNITS_AFFECTED)                                                     AS units_affected,
       CAST(100.0 * SUM(UNITS_AFFECTED) / SUM(SUM(UNITS_AFFECTED)) OVER () AS DECIMAL(5,1)) AS pct_of_units,
       CAST(100.0 * AVG(CASE WHEN PRIOR_COMPLAINTS > 0 THEN 1.0 ELSE 0 END) AS DECIMAL(5,1)) AS pct_with_prior_complaint,
       CAST(100.0 * AVG(1.0 * DO_NOT_DRIVE) AS DECIMAL(5,2))                   AS pct_do_not_drive
FROM v2.campaign_lag
WHERE IN_LAG_WINDOW = 1 AND RECALL_ORIGIN <> 'Unknown'
GROUP BY RECALL_ORIGIN;
GO

/* Share of each OEM's recalls that were NHTSA-influenced */
CREATE OR ALTER VIEW v2.vw_origin_by_oem AS
SELECT MFR_NAME_CLEAN,
       COUNT(*) AS campaigns,
       CAST(100.0 * AVG(CASE WHEN RECALL_ORIGIN = 'NHTSA-influenced' THEN 1.0 ELSE 0 END) AS DECIMAL(5,1)) AS pct_nhtsa_influenced
FROM v2.campaign_lag
WHERE IN_LAG_WINDOW = 1
GROUP BY MFR_NAME_CLEAN;
GO

SELECT * FROM v2.vw_origin_summary;
SELECT * FROM v2.vw_lag_by_origin;
SELECT o.* FROM v2.vw_origin_by_oem AS o
JOIN v2.scope_oems AS s ON s.MFR_NAME_CLEAN = o.MFR_NAME_CLEAN
ORDER BY pct_nhtsa_influenced DESC;
