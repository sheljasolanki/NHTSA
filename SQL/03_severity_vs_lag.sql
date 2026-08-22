-- ============================================================
-- ANALYSIS 2: Does Complaint Severity Affect Recall Response Time?
-- Question: do complaints involving a crash, fire, injury, or
-- death get matched to a recall FASTER than complaints without
-- those outcomes?
-- ============================================================

SELECT
    CASE WHEN c.CRASH = 'Y' THEN 'Crash involved' ELSE 'No crash' END AS crash_flag,
    COUNT(*) AS matched_complaints,
    AVG(p.DAYS_BEFORE_RECALL * 1.0) AS avg_days_to_recall,
    MIN(p.DAYS_BEFORE_RECALL) AS min_days,
    MAX(p.DAYS_BEFORE_RECALL) AS max_days
FROM complaint_recall_pairs AS p
JOIN complaints_clean AS c
    ON p.CMPLID = c.CMPLID
GROUP BY CASE WHEN c.CRASH = 'Y' THEN 'Crash involved' ELSE 'No crash' END;

-- Median version (more consistent with the rest of your analysis,
-- which used medians rather than averages)
SELECT DISTINCT
    CASE WHEN c.CRASH = 'Y' THEN 'Crash involved' ELSE 'No crash' END AS crash_flag,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.DAYS_BEFORE_RECALL)
        OVER (PARTITION BY CASE WHEN c.CRASH = 'Y' THEN 'Crash involved' ELSE 'No crash' END) AS median_days_to_recall
FROM complaint_recall_pairs AS p
JOIN complaints_clean AS c
    ON p.CMPLID = c.CMPLID;