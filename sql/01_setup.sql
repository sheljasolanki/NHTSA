/* ============================================================
   01  Setup: parameters, indexes, campaign table, scope
   ------------------------------------------------------------
   Run after notebook/01_data_cleaning.ipynb has loaded
   v2.complaints, v2.recalls and v2.recall_text.
   Everything lives in database NHTSA_v2 (files on D:), schema v2.
   Re-runnable: each object is dropped and rebuilt.
   ============================================================ */
SET NOCOUNT ON;

/* Single-threaded queries for this database only. The tables are small enough
   (2M rows) that parallelism gains little, and on a memory-constrained machine
   parallel plans can stall (CXSYNC_PORT waits). Remove on a bigger server. */
ALTER DATABASE SCOPED CONFIGURATION SET MAXDOP = 1;

/* ---------- Analysis parameters ----------
   Kept in one table so no script hard-codes them.
   LOOKBACK_YEARS     how far before a recall a complaint can count toward it
   FIRST_RECALL_DATE  earliest recall analysed for lag. Complaints start in 1995, so
                      recalls before 1995 + LOOKBACK_YEARS would have their lag cut short.
   EXTRACT_DATE       last date in the data (used to avoid right-censoring)
   SIGNAL_COMPLAINTS  the Nth complaint treated as "the warning signal"           */
DROP TABLE IF EXISTS v2.params;
CREATE TABLE v2.params (
    LOOKBACK_YEARS    INT  NOT NULL,
    FIRST_RECALL_DATE DATE NOT NULL,
    EXTRACT_DATE      DATE NOT NULL,
    SIGNAL_COMPLAINTS INT  NOT NULL
);
INSERT INTO v2.params (LOOKBACK_YEARS, FIRST_RECALL_DATE, EXTRACT_DATE, SIGNAL_COMPLAINTS)
SELECT 10,
       '2005-01-01',
       (SELECT MAX(d) FROM (SELECT MAX(COMPLAINT_DATE) AS d FROM v2.complaints
                            UNION ALL SELECT MAX(RECALL_DATE) FROM v2.recalls) AS x),
       3;

/* ---------- Indexes ----------
   The match key is OEM + component + model + model year, then date.
   Clustering both tables on it makes the join a merge of sorted ranges. */
DROP INDEX IF EXISTS ix_complaints_match ON v2.complaints;
DROP INDEX IF EXISTS ix_complaints_odino ON v2.complaints;
CREATE CLUSTERED INDEX ix_complaints_match
    ON v2.complaints (MFR_NAME_CLEAN, COMPONENT_CLEAN, MODEL_NORM, MODEL_YEAR, COMPLAINT_DATE);
CREATE INDEX ix_complaints_odino ON v2.complaints (ODINO) INCLUDE (COMPONENT_CLEAN, COMPLAINT_DATE);

DROP INDEX IF EXISTS ix_recalls_match ON v2.recalls;
DROP INDEX IF EXISTS ix_recalls_campno ON v2.recalls;
CREATE CLUSTERED INDEX ix_recalls_match
    ON v2.recalls (MFR_NAME_CLEAN, COMPONENT_CLEAN, MODEL_NORM, MODEL_YEAR, RECALL_DATE);
CREATE INDEX ix_recalls_campno ON v2.recalls (CAMPNO);

/* ---------- One row per recall campaign ----------
   v2.recalls has one row per campaign x vehicle x component, so any
   campaign-level count must come from here, not from v2.recalls. */
DROP TABLE IF EXISTS v2.campaigns;
WITH component_rank AS (
    SELECT CAMPNO, COMPONENT_CLEAN,
           ROW_NUMBER() OVER (PARTITION BY CAMPNO ORDER BY COUNT(*) DESC, COMPONENT_CLEAN) AS rn
    FROM v2.recalls
    GROUP BY CAMPNO, COMPONENT_CLEAN
)
SELECT r.CAMPNO,
       MIN(r.MFR_NAME_CLEAN)              AS MFR_NAME_CLEAN,
       COUNT(DISTINCT r.MFR_NAME_CLEAN)   AS N_OEMS,
       MIN(r.RECALL_DATE)                 AS RECALL_DATE,
       YEAR(MIN(r.RECALL_DATE))           AS RECALL_YEAR,
       MAX(r.UNITS_AFFECTED)              AS UNITS_AFFECTED,
       MAX(r.INFLUENCED_BY)               AS INFLUENCED_BY,
       CASE WHEN MAX(r.INFLUENCED_BY) = 'MFR' THEN 'Manufacturer-initiated'
            WHEN MAX(r.INFLUENCED_BY) IS NULL THEN 'Unknown'
            ELSE 'NHTSA-influenced' END   AS RECALL_ORIGIN,
       MAX(r.DO_NOT_DRIVE)                AS DO_NOT_DRIVE,
       MAX(r.PARK_OUTSIDE)                AS PARK_OUTSIDE,
       cr.COMPONENT_CLEAN                 AS PRIMARY_COMPONENT,
       COUNT(DISTINCT r.COMPONENT_CLEAN)  AS N_COMPONENTS,
       COUNT(DISTINCT CONCAT(r.MODEL_NORM, '|', r.MODEL_YEAR)) AS N_MODEL_YEARS
INTO v2.campaigns
FROM v2.recalls AS r
JOIN component_rank AS cr ON cr.CAMPNO = r.CAMPNO AND cr.rn = 1
GROUP BY r.CAMPNO, cr.COMPONENT_CLEAN
OPTION (MAXDOP 1);   -- small table; a parallel plan can stall when the server is short on memory

ALTER TABLE v2.campaigns ALTER COLUMN CAMPNO VARCHAR(20) NOT NULL;
GO  -- the NOT NULL change must be committed in its own batch before the primary key can use it
ALTER TABLE v2.campaigns ADD CONSTRAINT pk_campaigns PRIMARY KEY (CAMPNO);

/* ---------- Presentation scope ----------
   All analysis runs on every manufacturer and component. These top-10 lists
   are used only to keep charts readable. Ranked by distinct complaints, not rows. */
DROP TABLE IF EXISTS v2.scope_oems;
SELECT TOP 10 MFR_NAME_CLEAN, COUNT(DISTINCT ODINO) AS COMPLAINTS
INTO v2.scope_oems
FROM v2.complaints
GROUP BY MFR_NAME_CLEAN
ORDER BY COMPLAINTS DESC;

DROP TABLE IF EXISTS v2.scope_components;
SELECT TOP 10 COMPONENT_CLEAN, COUNT(DISTINCT ODINO) AS COMPLAINTS
INTO v2.scope_components
FROM v2.complaints
WHERE COMPONENT_CLEAN NOT IN ('UNKNOWN OR OTHER', 'OTHER', 'FIRERELATED', 'ROLLOVER', 'EQUIPMENT')
GROUP BY COMPONENT_CLEAN
ORDER BY COMPLAINTS DESC;

/* ---------- Sanity output ---------- */
SELECT * FROM v2.params;
SELECT 'complaint rows' AS item, COUNT(*) AS n FROM v2.complaints
UNION ALL SELECT 'distinct complaints (ODINO)', COUNT(DISTINCT ODINO) FROM v2.complaints
UNION ALL SELECT 'recall rows', COUNT(*) FROM v2.recalls
UNION ALL SELECT 'campaigns', COUNT(*) FROM v2.campaigns
UNION ALL SELECT 'campaigns spanning >1 OEM', COUNT(*) FROM v2.campaigns WHERE N_OEMS > 1;
SELECT * FROM v2.scope_oems ORDER BY COMPLAINTS DESC;
SELECT * FROM v2.scope_components ORDER BY COMPLAINTS DESC;
