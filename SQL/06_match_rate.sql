-- ============================================================
-- ANALYSIS 6: Complaint-to-Recall Match Rate
-- Question: what % of complaints (within the 5-company/10-
-- component scope) ever matched to a recall, vs. never found
-- a match at all? This is a data-quality/coverage finding in
-- its own right, not just a QA check.
-- ============================================================

-- Overall match rate, counting each complaint only once
-- (even if it falls within 5 years of multiple recalls)
SELECT
    COUNT(DISTINCT c.CMPLID) AS total_complaints,
    COUNT(DISTINCT p.CMPLID) AS matched_complaints,
    CAST(COUNT(DISTINCT p.CMPLID) * 100.0 / COUNT(DISTINCT c.CMPLID) AS DECIMAL(5,2)) AS match_rate_pct
FROM complaints_clean AS c
LEFT JOIN complaint_recall_pairs_5 AS p ON p.CMPLID = c.CMPLID
WHERE c.MFR_NAME_CLEAN IN ('GENERAL MOTORS','FORD','CHRYSLER','TOYOTA','HONDA')
AND c.COMPONENT_CLEAN IN ('ENGINE','ELECTRICAL SYSTEM','POWER TRAIN','AIR BAGS','STEERING',
    'SERVICE BRAKES, HYDRAULIC','STRUCTURE','SUSPENSION','VEHICLE SPEED CONTROL','SERVICE BRAKES');


-- Match rate by component, counting each complaint only once per component
SELECT
    c.COMPONENT_CLEAN,
    COUNT(DISTINCT c.CMPLID) AS total_complaints,
    COUNT(DISTINCT p.CMPLID) AS matched_complaints,
    CAST(COUNT(DISTINCT p.CMPLID) * 100.0 / COUNT(DISTINCT c.CMPLID) AS DECIMAL(5,2)) AS match_rate_pct
FROM complaints_clean AS c
LEFT JOIN complaint_recall_pairs_5 AS p ON p.CMPLID = c.CMPLID
WHERE c.MFR_NAME_CLEAN IN ('GENERAL MOTORS','FORD','CHRYSLER','TOYOTA','HONDA')
AND c.COMPONENT_CLEAN IN ('ENGINE','ELECTRICAL SYSTEM','POWER TRAIN','AIR BAGS','STEERING',
    'SERVICE BRAKES, HYDRAULIC','STRUCTURE','SUSPENSION','VEHICLE SPEED CONTROL','SERVICE BRAKES')
GROUP BY c.COMPONENT_CLEAN
ORDER BY match_rate_pct DESC;



-- Check if a units-affected column exists and see sample values
SELECT TOP 10 CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN, *
FROM recalls_clean;