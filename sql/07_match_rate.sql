/* ============================================================
   07  How often do complaints lead to a recall, and how often
            are recalls preceded by complaints?
   ------------------------------------------------------------
   "Did a complaint fall inside some recall window for that manufacturer
   + component" is almost always true for busy components, so it says
   little. Instead this script asks two specific questions:

   a) Complaint side: of complaints filed at least 5 years before the
      data extract, what share saw the SAME vehicle (model + year)
      recalled for the SAME component within 1, 2 and 5 years?
   b) Recall side: what share of recall campaigns had at least one
      matching owner complaint before the recall? Low shares mean
      recalls found by the manufacturer's own testing / field data.
   ============================================================ */
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW v2.vw_complaint_recall_rate AS
SELECT o.*,
       CASE WHEN o.DAYS_TO_NEXT_RECALL <=  365 THEN 1 ELSE 0 END AS RECALLED_1Y,
       CASE WHEN o.DAYS_TO_NEXT_RECALL <=  730 THEN 1 ELSE 0 END AS RECALLED_2Y,
       CASE WHEN o.DAYS_TO_NEXT_RECALL <= 1826 THEN 1 ELSE 0 END AS RECALLED_5Y
FROM v2.complaint_outcomes AS o
CROSS JOIN v2.params AS p
WHERE o.COMPLAINT_DATE >= '2000-01-01'
  AND o.COMPLAINT_DATE <= DATEADD(YEAR, -5, p.EXTRACT_DATE)
  AND o.COMPONENT_CLEAN NOT IN ('UNKNOWN OR OTHER', 'OTHER', 'FIRERELATED', 'ROLLOVER');
GO

CREATE OR ALTER VIEW v2.vw_recall_rate_by_component AS
SELECT COMPONENT_CLEAN,
       COUNT(*) AS complaints,
       CAST(100.0 * AVG(1.0 * RECALLED_1Y) AS DECIMAL(5,2)) AS pct_recalled_1y,
       CAST(100.0 * AVG(1.0 * RECALLED_2Y) AS DECIMAL(5,2)) AS pct_recalled_2y,
       CAST(100.0 * AVG(1.0 * RECALLED_5Y) AS DECIMAL(5,2)) AS pct_recalled_5y
FROM v2.vw_complaint_recall_rate
GROUP BY COMPONENT_CLEAN;
GO

CREATE OR ALTER VIEW v2.vw_recall_rate_by_oem AS
SELECT MFR_NAME_CLEAN,
       COUNT(*) AS complaints,
       CAST(100.0 * AVG(1.0 * RECALLED_1Y) AS DECIMAL(5,2)) AS pct_recalled_1y,
       CAST(100.0 * AVG(1.0 * RECALLED_2Y) AS DECIMAL(5,2)) AS pct_recalled_2y,
       CAST(100.0 * AVG(1.0 * RECALLED_5Y) AS DECIMAL(5,2)) AS pct_recalled_5y
FROM v2.vw_complaint_recall_rate
GROUP BY MFR_NAME_CLEAN;
GO

/* a) Overall complaint-side rate */
SELECT COUNT(*) AS complaints,
       CAST(100.0 * AVG(1.0 * RECALLED_1Y) AS DECIMAL(5,2)) AS pct_recalled_1y,
       CAST(100.0 * AVG(1.0 * RECALLED_2Y) AS DECIMAL(5,2)) AS pct_recalled_2y,
       CAST(100.0 * AVG(1.0 * RECALLED_5Y) AS DECIMAL(5,2)) AS pct_recalled_5y
FROM v2.vw_complaint_recall_rate;

SELECT c.* FROM v2.vw_recall_rate_by_component AS c
JOIN v2.scope_components AS s ON s.COMPONENT_CLEAN = c.COMPONENT_CLEAN
ORDER BY pct_recalled_5y DESC;

SELECT o.* FROM v2.vw_recall_rate_by_oem AS o
JOIN v2.scope_oems AS s ON s.MFR_NAME_CLEAN = o.MFR_NAME_CLEAN
ORDER BY pct_recalled_5y DESC;

/* b) Recall side: campaigns preceded by complaints (lag window only) */
SELECT COUNT(*) AS campaigns,
       SUM(CASE WHEN PRIOR_COMPLAINTS > 0 THEN 1 ELSE 0 END) AS with_prior_complaint,
       CAST(100.0 * AVG(CASE WHEN PRIOR_COMPLAINTS > 0 THEN 1.0 ELSE 0 END) AS DECIMAL(5,2)) AS pct_with_prior_complaint,
       CAST(100.0 * AVG(CASE WHEN PRIOR_COMPLAINTS >= 10 THEN 1.0 ELSE 0 END) AS DECIMAL(5,2)) AS pct_with_10plus
FROM v2.campaign_lag
WHERE IN_LAG_WINDOW = 1;
