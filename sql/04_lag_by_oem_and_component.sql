/* ============================================================
   04  Recall lag by manufacturer, component and both
   ------------------------------------------------------------
   Question: how long after the first complaints does a recall come,
   and does that differ by manufacturer or by component?

   Unit of analysis: one recall campaign (v2.campaign_lag), only
   campaigns that had at least one matching complaint and fall in the
   lag window (recall on or after FIRST_RECALL_DATE).
   Medians are used because lag is heavily right-skewed.
   Confidence intervals and significance tests are in
   notebook/02_analysis.ipynb.
   ============================================================ */
SET NOCOUNT ON;
GO

/* Base set reused by every lag view */
CREATE OR ALTER VIEW v2.vw_lag_campaigns AS
SELECT *
FROM v2.campaign_lag
WHERE IN_LAG_WINDOW = 1 AND PRIOR_COMPLAINTS > 0;
GO

CREATE OR ALTER VIEW v2.vw_lag_by_oem AS
SELECT DISTINCT
    MFR_NAME_CLEAN,
    COUNT(*) OVER (PARTITION BY MFR_NAME_CLEAN) AS campaigns,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)  OVER (PARTITION BY MFR_NAME_CLEAN) AS p25_lag_first,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)  OVER (PARTITION BY MFR_NAME_CLEAN) AS median_lag_first,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)  OVER (PARTITION BY MFR_NAME_CLEAN) AS p75_lag_first,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY PRIOR_COMPLAINTS) OVER (PARTITION BY MFR_NAME_CLEAN) AS median_prior_complaints
FROM v2.vw_lag_campaigns;
GO

/* LAG_SIGNAL_DAYS only exists for campaigns with >= SIGNAL_COMPLAINTS complaints */
CREATE OR ALTER VIEW v2.vw_lag_signal_by_oem AS
SELECT DISTINCT
    MFR_NAME_CLEAN,
    COUNT(*) OVER (PARTITION BY MFR_NAME_CLEAN) AS campaigns,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_SIGNAL_DAYS) OVER (PARTITION BY MFR_NAME_CLEAN) AS median_lag_signal
FROM v2.vw_lag_campaigns
WHERE LAG_SIGNAL_DAYS IS NOT NULL;
GO

CREATE OR ALTER VIEW v2.vw_lag_by_component AS
SELECT DISTINCT
    PRIMARY_COMPONENT AS COMPONENT_CLEAN,
    COUNT(*) OVER (PARTITION BY PRIMARY_COMPONENT) AS campaigns,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)  OVER (PARTITION BY PRIMARY_COMPONENT) AS p25_lag_first,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)  OVER (PARTITION BY PRIMARY_COMPONENT) AS median_lag_first,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)  OVER (PARTITION BY PRIMARY_COMPONENT) AS p75_lag_first,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY PRIOR_COMPLAINTS) OVER (PARTITION BY PRIMARY_COMPONENT) AS median_prior_complaints
FROM v2.vw_lag_campaigns;
GO

CREATE OR ALTER VIEW v2.vw_lag_oem_component AS
SELECT DISTINCT
    MFR_NAME_CLEAN,
    PRIMARY_COMPONENT AS COMPONENT_CLEAN,
    COUNT(*) OVER (PARTITION BY MFR_NAME_CLEAN, PRIMARY_COMPONENT) AS campaigns,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS)
        OVER (PARTITION BY MFR_NAME_CLEAN, PRIMARY_COMPONENT) AS median_lag_first
FROM v2.vw_lag_campaigns;
GO

/* Overall distribution */
SELECT TOP 1
    COUNT(*) OVER () AS campaigns,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS) OVER () AS p25_lag_first,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS) OVER () AS median_lag_first,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS) OVER () AS p75_lag_first,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY LAG_FIRST_DAYS) OVER () AS p90_lag_first
FROM v2.vw_lag_campaigns;

SELECT o.* FROM v2.vw_lag_by_oem AS o
JOIN v2.scope_oems AS s ON s.MFR_NAME_CLEAN = o.MFR_NAME_CLEAN
ORDER BY median_lag_first;

SELECT c.* FROM v2.vw_lag_by_component AS c
JOIN v2.scope_components AS s ON s.COMPONENT_CLEAN = c.COMPONENT_CLEAN
ORDER BY median_lag_first;

-- Cross-tab cells with at least 15 campaigns (smaller cells are too noisy to rank)
SELECT x.* FROM v2.vw_lag_oem_component AS x
JOIN v2.scope_oems AS so ON so.MFR_NAME_CLEAN = x.MFR_NAME_CLEAN
JOIN v2.scope_components AS sc ON sc.COMPONENT_CLEAN = x.COMPONENT_CLEAN
WHERE x.campaigns >= 15
ORDER BY x.MFR_NAME_CLEAN, x.median_lag_first;
