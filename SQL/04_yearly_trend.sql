-- ============================================================
-- ANALYSIS 3a: Volume Over Time (context-setting, full dataset)
-- Question: are complaint counts and recall counts rising or
-- falling year over year, across the full dataset? Not scoped
-- to the 5-company/10-component set — this is a general
-- shape-of-the-data chart, not a comparison.
-- ============================================================

SELECT
    YEAR(DATEA) AS complaint_year,
    COUNT(*) AS complaint_count
FROM complaints_clean
WHERE DATEA IS NOT NULL
GROUP BY YEAR(DATEA)
ORDER BY complaint_year;

SELECT
    YEAR(RCDATE) AS recall_year,
    COUNT(DISTINCT CAMPNO) AS recall_count
FROM recalls_clean
WHERE RCDATE IS NOT NULL
GROUP BY YEAR(RCDATE)
ORDER BY recall_year;


-- ============================================================
-- ANALYSIS 3b: Has Recall Response Time Changed Over the Years?
-- Question: are recent complaint→recall pairs resolved faster
-- or slower than older ones? Uses the existing scoped
-- complaint_recall_pairs table (5 companies / 10 components).
-- Year is taken from the complaint date, since that's the
-- consistent anchor point used for DAYS_BEFORE_RECALL throughout.
-- ============================================================
-- Average version
-- Trend analysis excluding right-censored recent years
-- (2022 onward excluded — insufficient time has passed for
-- their true lag distribution to be observed)

SELECT
    YEAR(p.COMPLAINT_DATE) AS complaint_year,
    COUNT(*) AS matched_pairs,
    AVG(p.DAYS_BEFORE_RECALL * 1.0) AS avg_days_to_recall
FROM complaint_recall_pairs AS p
WHERE p.COMPLAINT_DATE IS NOT NULL
    AND YEAR(p.COMPLAINT_DATE) <= 2021
GROUP BY YEAR(p.COMPLAINT_DATE)
ORDER BY complaint_year;

-- Median version
SELECT DISTINCT
    YEAR(p.COMPLAINT_DATE) AS complaint_year,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.DAYS_BEFORE_RECALL)
        OVER (PARTITION BY YEAR(p.COMPLAINT_DATE)) AS median_days_to_recall
FROM complaint_recall_pairs AS p
WHERE p.COMPLAINT_DATE IS NOT NULL
    AND YEAR(p.COMPLAINT_DATE) <= 2021
ORDER BY complaint_year;