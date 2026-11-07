/* ============================================================
   06  Trends over time
   ------------------------------------------------------------
   a) Volume: distinct complaints and recall campaigns per year.
   b) Lag: median complaint -> recall lag by RECALL year.
      Anchoring on the recall year avoids right-censoring: every
      campaign in a given recall year is complete, so recent years
      don't need to be cut off. Recalls before FIRST_RECALL_DATE
      are excluded because complaints only start in 1995, which would
      cap their lag (left truncation).
   ============================================================ */
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW v2.vw_yearly_volume AS
SELECT y.yr AS year,
       ISNULL(c.complaints, 0) AS complaints,
       ISNULL(r.campaigns, 0)  AS recall_campaigns,
       ISNULL(r.units_affected, 0) AS units_affected
FROM (SELECT DISTINCT YEAR(COMPLAINT_DATE) AS yr FROM v2.complaints
      UNION SELECT DISTINCT RECALL_YEAR FROM v2.campaigns WHERE RECALL_YEAR >= 1995) AS y
LEFT JOIN (SELECT YEAR(COMPLAINT_DATE) AS yr, COUNT(DISTINCT ODINO) AS complaints
           FROM v2.complaints GROUP BY YEAR(COMPLAINT_DATE)) AS c ON c.yr = y.yr
LEFT JOIN (SELECT RECALL_YEAR AS yr, COUNT(*) AS campaigns, SUM(UNITS_AFFECTED) AS units_affected
           FROM v2.campaigns GROUP BY RECALL_YEAR) AS r ON r.yr = y.yr;
GO

CREATE OR ALTER VIEW v2.vw_lag_by_recall_year AS
SELECT DISTINCT
    RECALL_YEAR,
    COUNT(*) OVER (PARTITION BY RECALL_YEAR) AS campaigns,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)  OVER (PARTITION BY RECALL_YEAR) AS median_lag_first,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_SIGNAL_DAYS) OVER (PARTITION BY RECALL_YEAR) AS median_lag_signal,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY PRIOR_COMPLAINTS) OVER (PARTITION BY RECALL_YEAR) AS median_prior_complaints
FROM v2.vw_lag_campaigns;
GO

SELECT * FROM v2.vw_yearly_volume ORDER BY year;
SELECT * FROM v2.vw_lag_by_recall_year ORDER BY RECALL_YEAR;
