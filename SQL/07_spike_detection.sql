-- Question: for each manufacturer + component + month, how many
-- complaints were filed? This is the base time series spike
-- detection will run on top of — scoped to the same 5 companies
-- and 10 components as the rest of the analysis, for consistency.

DROP VIEW IF EXISTS v_monthly_complaints;
GO

CREATE VIEW v_monthly_complaints AS
SELECT
    c.MFR_NAME_CLEAN,
    c.COMPONENT_CLEAN,
    DATEFROMPARTS(YEAR(c.DATEA), MONTH(c.DATEA), 1) AS complaint_month,
    COUNT(*) AS complaint_count
FROM complaints_clean AS c
WHERE c.DATEA IS NOT NULL
AND EXISTS (
    SELECT 1
    FROM complaint_recall_pairs AS p
    WHERE p.MFR_NAME_CLEAN = c.MFR_NAME_CLEAN
    AND p.COMPONENT_CLEAN = c.COMPONENT_CLEAN
)
GROUP BY c.MFR_NAME_CLEAN, c.COMPONENT_CLEAN, DATEFROMPARTS(YEAR(c.DATEA), MONTH(c.DATEA), 1);
GO

select * from v_monthly_complaints



--- Logic: for each manufacturer+component, compute a trailing 6-month average of complaint volume (not including the current month), 
--- then flag months where the actual count is at least 2x that trailing average — with a minimum baseline so we don't flag noise on 
---tiny counts (e.g. 1 complaint jumping to 3 isn't a real spike, it's just a small number wobbling).

DROP VIEW IF EXISTS v_monthly_spikes;
GO

CREATE VIEW v_monthly_spikes AS
SELECT
    m.MFR_NAME_CLEAN,
    m.COMPONENT_CLEAN,
    m.complaint_month,
    m.complaint_count,
    AVG(m.complaint_count) OVER (
        PARTITION BY m.MFR_NAME_CLEAN, m.COMPONENT_CLEAN
        ORDER BY m.complaint_month
        ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
    ) AS trailing_6mo_avg,
    CASE
        WHEN AVG(m.complaint_count) OVER (
            PARTITION BY m.MFR_NAME_CLEAN, m.COMPONENT_CLEAN
            ORDER BY m.complaint_month
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) >= 5
        AND m.complaint_count >= 2.0 * AVG(m.complaint_count) OVER (
            PARTITION BY m.MFR_NAME_CLEAN, m.COMPONENT_CLEAN
            ORDER BY m.complaint_month
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        )
        THEN 1 ELSE 0
    END AS is_spike
FROM v_monthly_complaints AS m;
GO

    select * from v_monthly_spikes


-- Question: for each recall, did complaint volume spike in the
-- 6 months leading up to it (for that same manufacturer + component)?
-- This pulls the monthly spike flags from v_monthly_spikes and
-- attaches them to each recall's pre-recall window, so we can
-- check whether spikes tend to precede recalls.

DROP TABLE IF EXISTS spike_before_recall;

SELECT
    r.CAMPNO,
    r.MFR_NAME_CLEAN,
    r.COMPONENT_CLEAN,
    r.RCDATE AS RECALL_DATE,
    s.complaint_month,
    s.complaint_count,
    s.trailing_6mo_avg,
    s.is_spike,
    DATEDIFF(MONTH, s.complaint_month, r.RCDATE) AS MONTHS_BEFORE_RECALL
INTO spike_before_recall
FROM recalls_clean AS r
JOIN v_monthly_spikes AS s
    ON r.MFR_NAME_CLEAN = s.MFR_NAME_CLEAN
    AND r.COMPONENT_CLEAN = s.COMPONENT_CLEAN
    AND s.complaint_month < r.RCDATE
    AND s.complaint_month >= DATEADD(MONTH, -6, r.RCDATE)
WHERE r.MFR_NAME_CLEAN IN ('GENERAL MOTORS', 'FORD', 'CHRYSLER', 'TOYOTA', 'HONDA')
AND r.COMPONENT_CLEAN IN (
    'ENGINE', 'ELECTRICAL SYSTEM', 'POWER TRAIN', 'AIR BAGS', 'STEERING',
    'SERVICE BRAKES, HYDRAULIC', 'STRUCTURE', 'SUSPENSION',
    'VEHICLE SPEED CONTROL', 'SERVICE BRAKES'
);

select * from spike_before_recall

-- Question: how many duplicate rows exist per recall campaign
-- in recalls_clean? If CAMPNO isn't unique, our join fanned out.
SELECT CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN, RCDATE, COUNT(*) AS row_count
FROM recalls_clean
GROUP BY CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN, RCDATE
HAVING COUNT(*) > 1
ORDER BY row_count DESC;

-- Question: same as before (did complaint volume spike in the
-- 6 months before each recall?) but using a deduplicated list of
-- recalls — one row per CAMPNO — so recalls with many affected
-- vehicle rows in recalls_clean don't get counted multiple times.

DROP TABLE IF EXISTS spike_before_recall;

SELECT
    r.CAMPNO,
    r.MFR_NAME_CLEAN,
    r.COMPONENT_CLEAN,
    r.RCDATE AS RECALL_DATE,
    s.complaint_month,
    s.complaint_count,
    s.trailing_6mo_avg,
    s.is_spike,
    DATEDIFF(MONTH, s.complaint_month, r.RCDATE) AS MONTHS_BEFORE_RECALL
INTO spike_before_recall
FROM (
    SELECT DISTINCT CAMPNO, MFR_NAME_CLEAN, COMPONENT_CLEAN, RCDATE
    FROM recalls_clean
) AS r
JOIN v_monthly_spikes AS s
    ON r.MFR_NAME_CLEAN = s.MFR_NAME_CLEAN
    AND r.COMPONENT_CLEAN = s.COMPONENT_CLEAN
    AND s.complaint_month < r.RCDATE
    AND s.complaint_month >= DATEADD(MONTH, -6, r.RCDATE)
WHERE r.MFR_NAME_CLEAN IN ('GENERAL MOTORS', 'FORD', 'CHRYSLER', 'TOYOTA', 'HONDA')
AND r.COMPONENT_CLEAN IN (
    'ENGINE', 'ELECTRICAL SYSTEM', 'POWER TRAIN', 'AIR BAGS', 'STEERING',
    'SERVICE BRAKES, HYDRAULIC', 'STRUCTURE', 'SUSPENSION',
    'VEHICLE SPEED CONTROL', 'SERVICE BRAKES'
);


-- Question: for each recall, did AT LEAST ONE of its 6 pre-recall
-- months show a complaint spike? Then roll that up into an overall
-- % of recalls that had a spike warning beforehand.

SELECT
    COUNT(DISTINCT CAMPNO) AS total_recalls,
    COUNT(DISTINCT CASE WHEN is_spike = 1 THEN CAMPNO END) AS recalls_with_spike,
    CAST(100.0 * COUNT(DISTINCT CASE WHEN is_spike = 1 THEN CAMPNO END)
        / COUNT(DISTINCT CAMPNO) AS DECIMAL(5,2)) AS pct_recalls_with_spike
FROM spike_before_recall;