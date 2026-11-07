/* ============================================================
   08  Do complaint spikes predict recalls?
   ------------------------------------------------------------
   Monthly complaint counts per OEM x component. A month is a spike
   when complaints >= 2x the trailing 6-month average and that
   average is >= 5.

   Method
   - A calendar of every month is filled with zeros, so "ROWS BETWEEN
     6 PRECEDING" always means 6 months, even across quiet months.
   - Every OEM x component series is used, not only those that later
     had a recall, to avoid selection bias.
   - Spike months are compared against ordinary months (lift), and
     spikes caused BY a recall (owners complaining after the
     announcement) are separated from spikes that come before one.
   ============================================================ */
SET NOCOUNT ON;

DECLARE @extract    DATE = (SELECT EXTRACT_DATE FROM v2.params);
DECLARE @first      DATE = (SELECT FIRST_RECALL_DATE FROM v2.params);
DECLARE @last_month DATE = DATEFROMPARTS(YEAR(@extract), MONTH(@extract), 1);

/* ---------- Calendar of months ---------- */
DROP TABLE IF EXISTS v2.calendar_months;
WITH m AS (
    SELECT CAST('1995-01-01' AS DATE) AS MONTH_START
    UNION ALL
    SELECT DATEADD(MONTH, 1, MONTH_START) FROM m WHERE MONTH_START < @last_month
)
SELECT MONTH_START INTO v2.calendar_months FROM m OPTION (MAXRECURSION 0);

/* ---------- Zero-filled monthly series ---------- */
DROP TABLE IF EXISTS v2.monthly_complaints;
WITH counts AS (
    SELECT MFR_NAME_CLEAN, COMPONENT_CLEAN,
           DATEFROMPARTS(YEAR(COMPLAINT_DATE), MONTH(COMPLAINT_DATE), 1) AS MONTH_START,
           COUNT(DISTINCT ODINO) AS COMPLAINTS
    FROM v2.complaints
    WHERE COMPONENT_CLEAN IN (SELECT DISTINCT COMPONENT_CLEAN FROM v2.recalls)
    GROUP BY MFR_NAME_CLEAN, COMPONENT_CLEAN,
             DATEFROMPARTS(YEAR(COMPLAINT_DATE), MONTH(COMPLAINT_DATE), 1)
),
series AS (
    SELECT MFR_NAME_CLEAN, COMPONENT_CLEAN, MIN(MONTH_START) AS FIRST_MONTH
    FROM counts GROUP BY MFR_NAME_CLEAN, COMPONENT_CLEAN
)
SELECT s.MFR_NAME_CLEAN, s.COMPONENT_CLEAN, cm.MONTH_START, ISNULL(c.COMPLAINTS, 0) AS COMPLAINTS
INTO v2.monthly_complaints
FROM series AS s
JOIN v2.calendar_months AS cm ON cm.MONTH_START >= s.FIRST_MONTH
LEFT JOIN counts AS c
    ON c.MFR_NAME_CLEAN = s.MFR_NAME_CLEAN AND c.COMPONENT_CLEAN = s.COMPONENT_CLEAN
   AND c.MONTH_START = cm.MONTH_START;

/* ---------- Recall events per OEM x component ---------- */
DROP TABLE IF EXISTS v2.campaign_components;
SELECT CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN, MIN(RECALL_DATE) AS RECALL_DATE,
       DATEFROMPARTS(YEAR(MIN(RECALL_DATE)), MONTH(MIN(RECALL_DATE)), 1) AS RECALL_MONTH
INTO v2.campaign_components
FROM v2.recalls
GROUP BY CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN;
CREATE CLUSTERED INDEX ix_cc ON v2.campaign_components (MFR_NAME_CLEAN, COMPONENT_CLEAN, RECALL_DATE);

/* ---------- Spike flags + what happened around each month ---------- */
DROP TABLE IF EXISTS v2.monthly_spikes;
WITH trailing AS (
    SELECT *,
           AVG(1.0 * COMPLAINTS) OVER (PARTITION BY MFR_NAME_CLEAN, COMPONENT_CLEAN ORDER BY MONTH_START
                                       ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING) AS TRAILING_6MO_AVG,
           COUNT(*)              OVER (PARTITION BY MFR_NAME_CLEAN, COMPONENT_CLEAN ORDER BY MONTH_START
                                       ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING) AS PRIOR_MONTHS
    FROM v2.monthly_complaints
),
flagged AS (
    SELECT *,
           CASE WHEN PRIOR_MONTHS = 6 AND TRAILING_6MO_AVG >= 5 THEN 1 ELSE 0 END AS IS_ELIGIBLE,
           CASE WHEN PRIOR_MONTHS = 6 AND TRAILING_6MO_AVG >= 5
                 AND COMPLAINTS >= 2.0 * TRAILING_6MO_AVG THEN 1 ELSE 0 END AS IS_SPIKE
    FROM trailing
)
SELECT f.*,
       SUM(f.IS_SPIKE) OVER (PARTITION BY f.MFR_NAME_CLEAN, f.COMPONENT_CLEAN ORDER BY f.MONTH_START
                             ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING) AS SPIKES_PRIOR_6M,
       -- a recall announced in the next 6 months (not this month: that would be the recall causing the spike)
       CASE WHEN EXISTS (SELECT 1 FROM v2.campaign_components AS cc
                         WHERE cc.MFR_NAME_CLEAN = f.MFR_NAME_CLEAN AND cc.COMPONENT_CLEAN = f.COMPONENT_CLEAN
                           AND cc.RECALL_DATE >= DATEADD(MONTH, 1, f.MONTH_START)
                           AND cc.RECALL_DATE <  DATEADD(MONTH, 7, f.MONTH_START)) THEN 1 ELSE 0 END AS RECALL_NEXT_6M,
       -- a recall announced this month or in the previous 2 months
       CASE WHEN EXISTS (SELECT 1 FROM v2.campaign_components AS cc
                         WHERE cc.MFR_NAME_CLEAN = f.MFR_NAME_CLEAN AND cc.COMPONENT_CLEAN = f.COMPONENT_CLEAN
                           AND cc.RECALL_DATE >= DATEADD(MONTH, -2, f.MONTH_START)
                           AND cc.RECALL_DATE <  DATEADD(MONTH,  1, f.MONTH_START)) THEN 1 ELSE 0 END AS RECALL_RECENT
INTO v2.monthly_spikes
FROM flagged AS f;
GO

/* ---------- Views ---------- */
-- Months that can be scored: eligible baseline, and at least 6 months of future data.
CREATE OR ALTER VIEW v2.vw_spike_months AS
SELECT s.*
FROM v2.monthly_spikes AS s
CROSS JOIN v2.params AS p
WHERE s.IS_ELIGIBLE = 1
  AND s.MONTH_START >= p.FIRST_RECALL_DATE
  AND s.MONTH_START <= DATEADD(MONTH, -7, p.EXTRACT_DATE);
GO

-- Forward-looking: does a spike raise the chance of a recall in the next 6 months?
-- "Organic" spikes exclude months right after a recall of that OEM x component.
CREATE OR ALTER VIEW v2.vw_spike_lift AS
SELECT CASE WHEN RECALL_RECENT = 1 THEN 'After a recent recall' ELSE 'Organic (no recent recall)' END AS spike_context,
       CASE WHEN IS_SPIKE = 1 THEN 'Spike month' ELSE 'Normal month' END AS month_type,
       COUNT(*) AS months,
       SUM(RECALL_NEXT_6M) AS months_followed_by_recall,
       CAST(100.0 * AVG(1.0 * RECALL_NEXT_6M) AS DECIMAL(5,2)) AS pct_recall_next_6m
FROM v2.vw_spike_months
GROUP BY CASE WHEN RECALL_RECENT = 1 THEN 'After a recent recall' ELSE 'Organic (no recent recall)' END,
         CASE WHEN IS_SPIKE = 1 THEN 'Spike month' ELSE 'Normal month' END;
GO

-- Reverse direction: do recalls trigger complaint spikes?
CREATE OR ALTER VIEW v2.vw_spike_after_recall AS
SELECT CASE WHEN RECALL_RECENT = 1 THEN 'Recall in this or previous 2 months' ELSE 'No recent recall' END AS context,
       COUNT(*) AS months,
       CAST(100.0 * AVG(1.0 * IS_SPIKE) AS DECIMAL(5,2)) AS pct_spike_months
FROM v2.vw_spike_months
GROUP BY CASE WHEN RECALL_RECENT = 1 THEN 'Recall in this or previous 2 months' ELSE 'No recent recall' END;
GO

-- Share of recall months preceded by >=1 spike in the prior 6 months,
-- vs the same share for every eligible month of the same series.
CREATE OR ALTER VIEW v2.vw_spike_before_recall AS
SELECT 'Months with a recall announcement' AS month_type,
       COUNT(*) AS months,
       CAST(100.0 * AVG(CASE WHEN s.SPIKES_PRIOR_6M > 0 THEN 1.0 ELSE 0 END) AS DECIMAL(5,2)) AS pct_spike_in_prior_6m
FROM (SELECT DISTINCT MFR_NAME_CLEAN, COMPONENT_CLEAN, RECALL_MONTH FROM v2.campaign_components) AS cc
JOIN v2.vw_spike_months AS s
  ON s.MFR_NAME_CLEAN = cc.MFR_NAME_CLEAN AND s.COMPONENT_CLEAN = cc.COMPONENT_CLEAN AND s.MONTH_START = cc.RECALL_MONTH
UNION ALL
SELECT 'All eligible months (baseline)', COUNT(*),
       CAST(100.0 * AVG(CASE WHEN SPIKES_PRIOR_6M > 0 THEN 1.0 ELSE 0 END) AS DECIMAL(5,2))
FROM v2.vw_spike_months;
GO

SELECT * FROM v2.vw_spike_lift ORDER BY spike_context, month_type;
SELECT * FROM v2.vw_spike_after_recall;
SELECT * FROM v2.vw_spike_before_recall;
