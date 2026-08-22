select * from dbo.complaints_clean;
select * from dbo.recalls_clean;

select count(distinct(CMPLID)) from dbo.complaints_clean;
select count(distinct(odino)) from dbo.complaints_clean;

exec sp_rename 'complaints_clean.MFR_NAME','MFR_NAME_RAW';

exec sp_rename 'complaints_clean.OEM_CLEAN','MFR_NAME_CLEAN';

exec sp_rename 'complaints_clean.YEARTXT','MODEL_YEAR';

exec sp_rename 'complaints_clean.COMPDESC','COMPONENT_RAW';

exec sp_rename 'complaints_clean.CDESCR','ACTUAL_COMPLAINT_TEXT';

exec sp_rename 'complaints_clean.MODELTXT','MODEL_NAME';

exec sp_rename 'complaints_clean.MAKETXT','VEHICLE_MAKE';

exec sp_rename 'recalls_clean.OEM_CLEAN','MFR_NAME_CLEAN';

exec sp_rename 'recalls_clean.MFGNAME','MFR_NAME_RAW';

exec sp_rename 'recalls_clean.YEARTXT','MODEL_YEAR';

exec sp_rename 'recalls_clean.COMPNAME','COMPONENT_RAW';

exec sp_rename 'recalls_clean.MAKETXT','VEHICLE_MAKE';

exec sp_rename 'recalls_clean.MODELTXT','MODEL_NAME';

exec sp_rename 'recalls_clean.CONEQUENCE_DEFECT','CONSEQUENCE_DEFECT';

select count(*) from recalls_clean 
where model_year='9999';

select distinct(model_year) from complaints_clean
order by model_year;

select count(distinct(CAMPNO)) from dbo.recalls_clean;

CREATE INDEX Complaints_Mfr_Component_Date_index
ON complaints_clean (
    MFR_NAME_CLEAN,
    COMPONENT_CLEAN,
    DATEA
);

CREATE INDEX Recalls_Mfr_Component_Date_index
ON recalls_clean (
    MFR_NAME_CLEAN,
    COMPONENT_CLEAN,
    RCDATE
);

SELECT DISTINCT
    c.CMPLID,
    c.MFR_NAME_CLEAN,
    c.COMPONENT_CLEAN,
    c.DATEA AS COMPLAINT_DATE,
    r.CAMPNO,
    r.RCDATE AS RECALL_DATE
FROM complaints_clean AS c
JOIN recalls_clean AS r
    ON c.MFR_NAME_CLEAN = r.MFR_NAME_CLEAN
    AND c.COMPONENT_CLEAN = r.COMPONENT_CLEAN
    AND c.DATEA < r.RCDATE
    AND c.DATEA >= DATEADD(MONTH, -12, r.RCDATE);


SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'complaints_clean'
ORDER BY ORDINAL_POSITION;

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'recalls_clean'
ORDER BY ORDINAL_POSITION;

SELECT
    MAX(LEN(MFR_NAME_RAW)) AS MFR_NAME_RAW_MAX,
    MAX(LEN(VEHICLE_MAKE)) AS VEHICLE_MAKE_MAX,
    MAX(LEN(MODEL_NAME)) AS MODEL_NAME_MAX,
    MAX(LEN(COMPONENT_RAW)) AS COMPONENT_RAW_MAX,
    MAX(LEN(ACTUAL_COMPLAINT_TEXT)) AS COMPLAINT_TEXT_MAX,
    MAX(LEN(MFR_NAME_CLEAN)) AS MFR_NAME_CLEAN_MAX,
    MAX(LEN(COMPONENT_CLEAN)) AS COMPONENT_CLEAN_MAX
FROM complaints_clean;

SELECT
    MAX(LEN(MFR_NAME_RAW)) AS MFR_NAME_RAW_MAX,
    MAX(LEN(VEHICLE_MAKE)) AS VEHICLE_MAKE_MAX,
    MAX(LEN(MODEL_NAME)) AS MODEL_NAME_MAX,
    MAX(LEN(COMPONENT_RAW)) AS COMPONENT_RAW_MAX,
    MAX(LEN(DESC_DEFECT)) AS DESC_DEFECT_MAX,
    MAX(LEN(CONSEQUENCE_DEFECT)) AS CONSEQUENCE_DEFECT_MAX,
    MAX(LEN(MFR_NAME_CLEAN)) AS MFR_NAME_CLEAN_MAX,
    MAX(LEN(COMPONENT_CLEAN)) AS COMPONENT_CLEAN_MAX
FROM recalls_clean;

ALTER TABLE complaints_clean
ALTER COLUMN MFR_NAME_RAW VARCHAR(100) NULL;

ALTER TABLE complaints_clean
ALTER COLUMN VEHICLE_MAKE VARCHAR(50) NULL;

ALTER TABLE complaints_clean
ALTER COLUMN MODEL_NAME VARCHAR(100) NULL;

ALTER TABLE complaints_clean
ALTER COLUMN MODEL_YEAR INT NULL;

ALTER TABLE complaints_clean
ALTER COLUMN COMPONENT_RAW VARCHAR(150) NULL;

ALTER TABLE complaints_clean
ALTER COLUMN MFR_NAME_CLEAN VARCHAR(50) NULL;

ALTER TABLE complaints_clean
ALTER COLUMN COMPONENT_CLEAN VARCHAR(100) NULL;




ALTER TABLE recalls_clean
ALTER COLUMN MFR_NAME_RAW VARCHAR(100) NULL;

ALTER TABLE recalls_clean
ALTER COLUMN VEHICLE_MAKE VARCHAR(50) NULL;

ALTER TABLE recalls_clean
ALTER COLUMN MODEL_NAME VARCHAR(100) NULL;

ALTER TABLE recalls_clean
ALTER COLUMN MODEL_YEAR INT NULL;

ALTER TABLE recalls_clean
ALTER COLUMN COMPONENT_RAW VARCHAR(150) NULL;

ALTER TABLE recalls_clean
ALTER COLUMN MFR_NAME_CLEAN VARCHAR(50) NULL;

ALTER TABLE recalls_clean
ALTER COLUMN COMPONENT_CLEAN VARCHAR(100) NULL;


UPDATE complaints_clean
SET MODEL_YEAR = NULL
WHERE MODEL_YEAR = 9999;

UPDATE recalls_clean
SET MODEL_YEAR = NULL
WHERE MODEL_YEAR = 9999;




SELECT DISTINCT
    c.CMPLID,
    c.MFR_NAME_CLEAN,
    c.COMPONENT_CLEAN,
    c.DATEA AS COMPLAINT_DATE,
    r.CAMPNO,
    r.RCDATE AS RECALL_DATE,
    DATEDIFF(DAY, c.DATEA, r.RCDATE) AS DAYS_BEFORE_RECALL
INTO complaint_recall_pairs
FROM complaints_clean AS c
JOIN recalls_clean AS r
    ON c.MFR_NAME_CLEAN = r.MFR_NAME_CLEAN
    AND c.COMPONENT_CLEAN = r.COMPONENT_CLEAN
    AND c.DATEA < r.RCDATE
    AND c.DATEA >= DATEADD(MONTH, -12, r.RCDATE);   

select * from complaint_recall_pairs

SELECT DISTINCT
    c.CMPLID,
    c.MFR_NAME_CLEAN,
    c.COMPONENT_CLEAN,
    c.DATEA AS COMPLAINT_DATE,
    r.CAMPNO,
    r.RCDATE AS RECALL_DATE,
    DATEDIFF(DAY, c.DATEA, r.RCDATE) AS DAYS_BEFORE_RECALL
INTO complaint_recall_pairs_5
FROM complaints_clean AS c
JOIN recalls_clean AS r
    ON c.MFR_NAME_CLEAN = r.MFR_NAME_CLEAN
    AND c.COMPONENT_CLEAN = r.COMPONENT_CLEAN
    AND c.DATEA < r.RCDATE
    AND c.DATEA >= DATEADD(MONTH, -60, r.RCDATE);   

select * from complaint_recall_pairs_5

SELECT
    COUNT(*) AS TOTAL_COMPLAINT_RECALL_PAIRS,
    COUNT(DISTINCT CMPLID) AS UNIQUE_COMPLAINTS,
    COUNT(DISTINCT CAMPNO) AS UNIQUE_RECALL_CAMPAIGNS,
    AVG(DAYS_BEFORE_RECALL * 1.0) AS AVG_DAYS,
    MIN(DAYS_BEFORE_RECALL) AS MIN_DAYS,
    MAX(DAYS_BEFORE_RECALL) AS MAX_DAYS
FROM complaint_recall_pairs;

-- how many recall does one complain match to 

select count(*) as matched_recall_count from complaint_recall_pairs group by component_clean

-- by components
SELECT
    COMPONENT_CLEAN,
    COUNT(*) AS TOTAL_PAIRS,
    COUNT(DISTINCT CMPLID) AS UNIQUE_COMPLAINTS,
    COUNT(DISTINCT CAMPNO) AS UNIQUE_RECALL_CAMPAIGNS,
    AVG(DAYS_BEFORE_RECALL * 1.0) AS AVG_DAYS,
    MIN(DAYS_BEFORE_RECALL) AS MIN_DAYS,
    MAX(DAYS_BEFORE_RECALL) AS MAX_DAYS
FROM complaint_recall_pairs
GROUP BY COMPONENT_CLEAN
ORDER BY TOTAL_PAIRS DESC;

SELECT TOP 1
    PERCENTILE_CONT(0.25)
        WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL)
        OVER () AS P25_DAYS,

    PERCENTILE_CONT(0.50)
        WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL)
        OVER () AS P50_MEDIAN_DAYS,

    PERCENTILE_CONT(0.75)
        WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL)
        OVER () AS P75_DAYS,

    PERCENTILE_CONT(0.90)
        WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL)
        OVER () AS P90_DAYS
FROM complaint_recall_pairs_5;


-- Quick, cheap query: which companies have the most complaints overall?
-- This tells us who to focus on before running the expensive join,
-- so we don't waste time processing companies we won't analyze anyway.
SELECT TOP 10
    MFR_NAME_CLEAN,
    COUNT(*) AS COMPLAINT_COUNT
FROM complaints_clean
GROUP BY MFR_NAME_CLEAN
ORDER BY COMPLAINT_COUNT DESC;





-- Quick, cheap check: which components have the most complaints?
-- Same logic as the top-10-companies query — find where the real
-- volume/signal is before running the expensive join.
SELECT TOP 16
    COMPONENT_CLEAN,
    COUNT(*) AS COMPLAINT_COUNT
FROM complaints_clean
GROUP BY COMPONENT_CLEAN
ORDER BY COMPLAINT_COUNT DESC;

-- Quick pre-check: how many complaint rows and recall rows match
-- our filters, BEFORE running the expensive join. This tells us
-- the "input size" so we can sanity-check scale, even though the
-- exact output row count depends on how dates line up.

SELECT COUNT(*) AS FILTERED_COMPLAINTS
FROM complaints_clean
WHERE MFR_NAME_CLEAN IN ('GENERAL MOTORS', 'FORD', 'CHRYSLER', 'TOYOTA', 'HONDA')
AND COMPONENT_CLEAN IN (
    'ENGINE', 'ELECTRICAL SYSTEM', 'POWER TRAIN', 'AIR BAGS', 'STEERING',
    'SERVICE BRAKES, HYDRAULIC', 'STRUCTURE', 'SUSPENSION',
    'VEHICLE SPEED CONTROL', 'SERVICE BRAKES'
);

SELECT COUNT(*) AS FILTERED_RECALLS
FROM recalls_clean
WHERE MFR_NAME_CLEAN IN ('GENERAL MOTORS', 'FORD', 'CHRYSLER', 'TOYOTA', 'HONDA')
AND COMPONENT_CLEAN IN (
    'ENGINE', 'ELECTRICAL SYSTEM', 'POWER TRAIN', 'AIR BAGS', 'STEERING',
    'SERVICE BRAKES, HYDRAULIC', 'STRUCTURE', 'SUSPENSION',
    'VEHICLE SPEED CONTROL', 'SERVICE BRAKES'
);


DROP TABLE IF EXISTS complaint_recall_pairs;

SELECT
    c.CMPLID,
    c.MFR_NAME_CLEAN,
    c.COMPONENT_CLEAN,
    c.DATEA AS COMPLAINT_DATE,
    r.CAMPNO,
    r.RCDATE AS RECALL_DATE,
    DATEDIFF(DAY, c.DATEA, r.RCDATE) AS DAYS_BEFORE_RECALL
INTO complaint_recall_pairs
FROM complaints_clean AS c
JOIN recalls_clean AS r
    ON c.MFR_NAME_CLEAN = r.MFR_NAME_CLEAN
    AND c.COMPONENT_CLEAN = r.COMPONENT_CLEAN
    AND c.DATEA < r.RCDATE
    AND c.DATEA >= DATEADD(MONTH, -12, r.RCDATE)
WHERE c.MFR_NAME_CLEAN IN ('GENERAL MOTORS', 'FORD', 'CHRYSLER', 'TOYOTA', 'HONDA')
AND c.COMPONENT_CLEAN IN (
    'ENGINE', 'ELECTRICAL SYSTEM', 'POWER TRAIN', 'AIR BAGS', 'STEERING',
    'SERVICE BRAKES, HYDRAULIC', 'STRUCTURE', 'SUSPENSION',
    'VEHICLE SPEED CONTROL', 'SERVICE BRAKES'
);
    





-- Check if complaint_recall_pairs still exists, and if so, how many rows it has
SELECT COUNT(*) AS row_count FROM complaint_recall_pairs;

SELECT COUNT(*) AS row_count FROM complaint_recall_pairs_5;

-- Filter the already-completed 5-year join down to our analysis scope
-- (top 5 manufacturers, top 10 components) instead of re-running the
-- expensive join from scratch — this table already exists on disk.
DROP TABLE IF EXISTS complaint_recall_pairs;

SELECT *
INTO complaint_recall_pairs
FROM complaint_recall_pairs_5
WHERE MFR_NAME_CLEAN IN ('GENERAL MOTORS', 'FORD', 'CHRYSLER', 'TOYOTA', 'HONDA')
AND COMPONENT_CLEAN IN (
    'ENGINE', 'ELECTRICAL SYSTEM', 'POWER TRAIN', 'AIR BAGS', 'STEERING',
    'SERVICE BRAKES, HYDRAULIC', 'STRUCTURE', 'SUSPENSION',
    'VEHICLE SPEED CONTROL', 'SERVICE BRAKES'
);

SELECT *
INTO complaint_recall_pairs_top10
FROM complaint_recall_pairs_5
WHERE MFR_NAME_CLEAN IN ('GENERAL MOTORS', 'FORD', 'CHRYSler', 'TOYOTA', 'HONDA', 'NISSAN', 'HYUNDAI', 'VOLKSWAGEN', 'KIA', 'BMW')
AND COMPONENT_CLEAN IN (
    'ENGINE', 'ELECTRICAL SYSTEM', 'POWER TRAIN', 'AIR BAGS', 'STEERING',
    'SERVICE BRAKES, HYDRAULIC', 'STRUCTURE', 'SUSPENSION',
    'VEHICLE SPEED CONTROL', 'SERVICE BRAKES'
);

-- Same percentile logic as before, but now computed separately per
-- company (MFR_NAME_CLEAN) instead of blending all OEMs together.
-- PARTITION BY tells SQL Server: "treat each company's rows as
-- its own independent group when computing these percentiles" —
-- this is exactly the mechanism that lets us keep one table but
-- still get per-company answers, like we discussed.

SELECT DISTINCT
    MFR_NAME_CLEAN,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL) 
        OVER (PARTITION BY MFR_NAME_CLEAN) AS P25_DAYS,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL) 
        OVER (PARTITION BY MFR_NAME_CLEAN) AS P50_MEDIAN_DAYS,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL) 
        OVER (PARTITION BY MFR_NAME_CLEAN) AS P75_DAYS,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY DAYS_BEFORE_RECALL) 
        OVER (PARTITION BY MFR_NAME_CLEAN) AS P90_DAYS,
    COUNT(*) OVER (PARTITION BY MFR_NAME_CLEAN) AS PAIR_COUNT
FROM complaint_recall_pairs
ORDER BY PAIR_COUNT DESC;

