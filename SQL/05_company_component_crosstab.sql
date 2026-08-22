-- ============================================================
-- ANALYSIS 4: Company × Component Cross-Tab
-- Question: is slow/fast response a company-wide trait, or
-- specific to certain company+component combinations? Uses the
-- same scoped complaint_recall_pairs table as the company and
-- component rankings, just grouped on both dimensions at once.
-- ============================================================

SELECT
    MFR_NAME_CLEAN,
    COMPONENT_CLEAN,
    COUNT(*) AS matched_pairs,
    AVG(DAYS_BEFORE_RECALL * 1.0) AS avg_days_to_recall
FROM complaint_recall_pairs
GROUP BY MFR_NAME_CLEAN, COMPONENT_CLEAN
ORDER BY MFR_NAME_CLEAN, avg_days_to_recall;

SELECT DISTINCT
    MFR_NAME_CLEAN,
    COMPONENT_CLEAN,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL)
        OVER (PARTITION BY MFR_NAME_CLEAN, COMPONENT_CLEAN) AS median_days_to_recall,
    COUNT(*) OVER (PARTITION BY MFR_NAME_CLEAN, COMPONENT_CLEAN) AS matched_pairs
FROM complaint_recall_pairs
ORDER BY MFR_NAME_CLEAN, median_days_to_recall;