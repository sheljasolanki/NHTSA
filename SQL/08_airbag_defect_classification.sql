-- Confirm the text fields survived cleaning and see what they look like
SELECT TOP 10 CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN, DESC_DEFECT, CONSEQUENCE_DEFECT
FROM recalls_clean
WHERE DESC_DEFECT IS NOT NULL;

-- Distinct campaigns only — one row per actual recall event,
-- not one row per vehicle configuration it covers
SELECT DISTINCT
    CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN, DESC_DEFECT, CONSEQUENCE_DEFECT
FROM recalls_clean
WHERE COMPONENT_CLEAN = 'AIR BAGS'
    AND DESC_DEFECT IS NOT NULL
ORDER BY CAMPNO;


-- Rough categorization of AIR BAGS recalls by failure-mode keyword in the description
SELECT
    CASE
        WHEN DESC_DEFECT LIKE '%rupture%' OR DESC_DEFECT LIKE '%explo%' THEN 'Inflator rupture/explosion'
        WHEN DESC_DEFECT LIKE '%inadvertent%' OR DESC_DEFECT LIKE '%unexpected%' OR DESC_DEFECT LIKE '%unintentional%' THEN 'Inadvertent deployment'
        WHEN DESC_DEFECT LIKE '%not deploy%' OR DESC_DEFECT LIKE '%fail to deploy%' OR DESC_DEFECT LIKE '%non-deploy%' OR DESC_DEFECT LIKE '%deactivat%' THEN 'Deployment failure / non-deployment'
        ELSE 'Other / assembly defect'
    END AS failure_category,
    COUNT(DISTINCT CAMPNO) AS campaign_count
FROM recalls_clean
WHERE COMPONENT_CLEAN = 'AIR BAGS'
    AND DESC_DEFECT IS NOT NULL
GROUP BY CASE
        WHEN DESC_DEFECT LIKE '%rupture%' OR DESC_DEFECT LIKE '%explo%' THEN 'Inflator rupture/explosion'
        WHEN DESC_DEFECT LIKE '%inadvertent%' OR DESC_DEFECT LIKE '%unexpected%' OR DESC_DEFECT LIKE '%unintentional%' THEN 'Inadvertent deployment'
        WHEN DESC_DEFECT LIKE '%not deploy%' OR DESC_DEFECT LIKE '%fail to deploy%' OR DESC_DEFECT LIKE '%non-deploy%' OR DESC_DEFECT LIKE '%deactivat%' THEN 'Deployment failure / non-deployment'
        ELSE 'Other / assembly defect'
    END
ORDER BY campaign_count DESC;



-- Split the "Other" bucket further to see what's actually driving 62% of the data
SELECT
    CASE
        WHEN DESC_DEFECT LIKE '%bolt%' OR DESC_DEFECT LIKE '%weld%' OR DESC_DEFECT LIKE '%fastener%' OR DESC_DEFECT LIKE '%screw%' OR DESC_DEFECT LIKE '%rivet%' THEN 'Assembly/fastener defect'
        WHEN DESC_DEFECT LIKE '%occupant classification%' OR DESC_DEFECT LIKE '%OCS%' OR DESC_DEFECT LIKE '%sensor%' THEN 'Sensor/classification error'
        WHEN DESC_DEFECT LIKE '%wiring%' OR DESC_DEFECT LIKE '%wire harness%' OR DESC_DEFECT LIKE '%connector%' OR DESC_DEFECT LIKE '%corrosion%' THEN 'Wiring/corrosion'
        WHEN DESC_DEFECT LIKE '%software%' THEN 'Software error'
        WHEN DESC_DEFECT LIKE '%tear%' OR DESC_DEFECT LIKE '%torn%' THEN 'Air bag tearing'
        WHEN DESC_DEFECT LIKE '%cover%' OR DESC_DEFECT LIKE '%emblem%' OR DESC_DEFECT LIKE '%score line%' OR DESC_DEFECT LIKE '%shatter%' THEN 'Cover/trim fragment (deployment)'
        ELSE 'Uncategorized'
    END AS sub_category,
    COUNT(DISTINCT CAMPNO) AS campaign_count
FROM recalls_clean
WHERE COMPONENT_CLEAN = 'AIR BAGS'
    AND DESC_DEFECT IS NOT NULL
    AND DESC_DEFECT NOT LIKE '%rupture%' AND DESC_DEFECT NOT LIKE '%explo%'
    AND DESC_DEFECT NOT LIKE '%inadvertent%' AND DESC_DEFECT NOT LIKE '%unexpected%' AND DESC_DEFECT NOT LIKE '%unintentional%'
    AND DESC_DEFECT NOT LIKE '%not deploy%' AND DESC_DEFECT NOT LIKE '%fail to deploy%' AND DESC_DEFECT NOT LIKE '%non-deploy%' AND DESC_DEFECT NOT LIKE '%deactivat%'
GROUP BY
    CASE
        WHEN DESC_DEFECT LIKE '%bolt%' OR DESC_DEFECT LIKE '%weld%' OR DESC_DEFECT LIKE '%fastener%' OR DESC_DEFECT LIKE '%screw%' OR DESC_DEFECT LIKE '%rivet%' THEN 'Assembly/fastener defect'
        WHEN DESC_DEFECT LIKE '%occupant classification%' OR DESC_DEFECT LIKE '%OCS%' OR DESC_DEFECT LIKE '%sensor%' THEN 'Sensor/classification error'
        WHEN DESC_DEFECT LIKE '%wiring%' OR DESC_DEFECT LIKE '%wire harness%' OR DESC_DEFECT LIKE '%connector%' OR DESC_DEFECT LIKE '%corrosion%' THEN 'Wiring/corrosion'
        WHEN DESC_DEFECT LIKE '%software%' THEN 'Software error'
        WHEN DESC_DEFECT LIKE '%tear%' OR DESC_DEFECT LIKE '%torn%' THEN 'Air bag tearing'
        WHEN DESC_DEFECT LIKE '%cover%' OR DESC_DEFECT LIKE '%emblem%' OR DESC_DEFECT LIKE '%score line%' OR DESC_DEFECT LIKE '%shatter%' THEN 'Cover/trim fragment (deployment)'
        ELSE 'Uncategorized'
    END
ORDER BY campaign_count DESC;


-- Random sample of currently-uncategorized descriptions, to see if there's
-- a missed pattern worth one more keyword bucket, or if it's genuinely
-- a long tail with no dominant sub-theme
SELECT TOP 20 CAMPNO, DESC_DEFECT
FROM recalls_clean
WHERE COMPONENT_CLEAN = 'AIR BAGS'
    AND DESC_DEFECT IS NOT NULL
    AND DESC_DEFECT NOT LIKE '%rupture%' AND DESC_DEFECT NOT LIKE '%explo%'
    AND DESC_DEFECT NOT LIKE '%inadvertent%' AND DESC_DEFECT NOT LIKE '%unexpected%' AND DESC_DEFECT NOT LIKE '%unintentional%'
    AND DESC_DEFECT NOT LIKE '%not deploy%' AND DESC_DEFECT NOT LIKE '%fail to deploy%' AND DESC_DEFECT NOT LIKE '%non-deploy%' AND DESC_DEFECT NOT LIKE '%deactivat%'
    AND DESC_DEFECT NOT LIKE '%bolt%' AND DESC_DEFECT NOT LIKE '%weld%' AND DESC_DEFECT NOT LIKE '%fastener%' AND DESC_DEFECT NOT LIKE '%screw%' AND DESC_DEFECT NOT LIKE '%rivet%'
    AND DESC_DEFECT NOT LIKE '%occupant classification%' AND DESC_DEFECT NOT LIKE '%OCS%' AND DESC_DEFECT NOT LIKE '%sensor%'
    AND DESC_DEFECT NOT LIKE '%wiring%' AND DESC_DEFECT NOT LIKE '%wire harness%' AND DESC_DEFECT NOT LIKE '%connector%' AND DESC_DEFECT NOT LIKE '%corrosion%'
    AND DESC_DEFECT NOT LIKE '%software%'
    AND DESC_DEFECT NOT LIKE '%tear%' AND DESC_DEFECT NOT LIKE '%torn%'
ORDER BY NEWID();