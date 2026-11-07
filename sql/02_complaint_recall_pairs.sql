/* ============================================================
   02  Complaint -> recall matching
   ------------------------------------------------------------
   A complaint is matched to a recall only when the SAME vehicle
   was recalled for the SAME component:
       OEM + component + model + model year,
       complaint filed before the recall, within LOOKBACK_YEARS.
   Matching on manufacturer + component alone would pair, say, a Ford
   F-150 engine complaint with every Ford engine recall, most of them
   for unrelated vehicles.

   Outputs
     v2.complaint_recall_pairs  one row per complaint x component x campaign
     v2.campaign_lag            one row per campaign: prior complaints and lag
     v2.complaint_outcomes      one row per complaint x component: next recall, if any
   ============================================================ */
SET NOCOUNT ON;

DECLARE @lookback INT = (SELECT LOOKBACK_YEARS FROM v2.params);
DECLARE @signal   INT = (SELECT SIGNAL_COMPLAINTS FROM v2.params);
DECLARE @first    DATE = (SELECT FIRST_RECALL_DATE FROM v2.params);

/* ---------- Pairs ---------- */
DROP TABLE IF EXISTS v2.complaint_recall_pairs;

SELECT c.ODINO,
       c.COMPONENT_CLEAN,
       r.CAMPNO,
       MIN(c.MFR_NAME_CLEAN)                                   AS MFR_NAME_CLEAN,
       MIN(c.COMPLAINT_DATE)                                   AS COMPLAINT_DATE,
       MIN(r.RECALL_DATE)                                      AS RECALL_DATE,
       DATEDIFF(DAY, MIN(c.COMPLAINT_DATE), MIN(r.RECALL_DATE)) AS DAYS_BEFORE_RECALL,
       MAX(c.CRASH)    AS CRASH,
       MAX(c.FIRE)     AS FIRE,
       MAX(c.INJURED)  AS INJURED,
       MAX(c.DEATHS)   AS DEATHS
INTO v2.complaint_recall_pairs
FROM v2.complaints AS c
JOIN v2.recalls    AS r
    ON  c.MFR_NAME_CLEAN  = r.MFR_NAME_CLEAN
    AND c.COMPONENT_CLEAN = r.COMPONENT_CLEAN
    AND c.MODEL_NORM      = r.MODEL_NORM
    AND c.MODEL_YEAR      = r.MODEL_YEAR
    AND c.COMPLAINT_DATE  <  r.RECALL_DATE
    AND c.COMPLAINT_DATE  >= DATEADD(YEAR, -@lookback, r.RECALL_DATE)
GROUP BY c.ODINO, c.COMPONENT_CLEAN, r.CAMPNO;   -- a complaint counts once per campaign

CREATE CLUSTERED INDEX ix_pairs_campaign ON v2.complaint_recall_pairs (CAMPNO, COMPLAINT_DATE);
CREATE INDEX ix_pairs_complaint ON v2.complaint_recall_pairs (ODINO, COMPONENT_CLEAN) INCLUDE (RECALL_DATE);

/* ---------- Campaign-level lag ----------
   The recall responds to the FIRST warning signs, so lag is measured once per
   campaign, not once per complaint:
     LAG_FIRST_DAYS   first matching complaint -> recall
     LAG_SIGNAL_DAYS  Nth matching complaint (SIGNAL_COMPLAINTS, default 3) -> recall;
                      less sensitive to one stray early complaint
   Campaigns with no matching complaint are kept (PRIOR_COMPLAINTS = 0): they are
   recalls that were not preceded by any owner complaint about that vehicle. */
DROP TABLE IF EXISTS v2.campaign_lag;

WITH per_campaign_complaint AS (      -- a complaint naming two components counts once per campaign
    SELECT CAMPNO, ODINO,
           MIN(COMPLAINT_DATE) AS COMPLAINT_DATE,
           MAX(CRASH) AS CRASH, MAX(FIRE) AS FIRE, MAX(INJURED) AS INJURED, MAX(DEATHS) AS DEATHS
    FROM v2.complaint_recall_pairs
    GROUP BY CAMPNO, ODINO
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY CAMPNO ORDER BY COMPLAINT_DATE, ODINO) AS rn
    FROM per_campaign_complaint
),
agg AS (
    SELECT CAMPNO,
           COUNT(*)                                          AS PRIOR_COMPLAINTS,
           MIN(COMPLAINT_DATE)                               AS FIRST_COMPLAINT_DATE,
           MAX(CASE WHEN rn = @signal THEN COMPLAINT_DATE END) AS SIGNAL_COMPLAINT_DATE,
           SUM(CRASH)                                        AS PRIOR_CRASH_COMPLAINTS,
           SUM(FIRE)                                         AS PRIOR_FIRE_COMPLAINTS,
           SUM(CASE WHEN INJURED > 0 OR DEATHS > 0 THEN 1 ELSE 0 END) AS PRIOR_INJURY_OR_DEATH_COMPLAINTS,
           SUM(DEATHS)                                       AS PRIOR_DEATHS
    FROM ranked
    GROUP BY CAMPNO
)
SELECT k.*,
       ISNULL(a.PRIOR_COMPLAINTS, 0)                        AS PRIOR_COMPLAINTS,
       a.FIRST_COMPLAINT_DATE,
       a.SIGNAL_COMPLAINT_DATE,
       DATEDIFF(DAY, a.FIRST_COMPLAINT_DATE,  k.RECALL_DATE) AS LAG_FIRST_DAYS,
       DATEDIFF(DAY, a.SIGNAL_COMPLAINT_DATE, k.RECALL_DATE) AS LAG_SIGNAL_DAYS,
       ISNULL(a.PRIOR_CRASH_COMPLAINTS, 0)                  AS PRIOR_CRASH_COMPLAINTS,
       ISNULL(a.PRIOR_FIRE_COMPLAINTS, 0)                   AS PRIOR_FIRE_COMPLAINTS,
       ISNULL(a.PRIOR_INJURY_OR_DEATH_COMPLAINTS, 0)        AS PRIOR_INJURY_OR_DEATH_COMPLAINTS,
       ISNULL(a.PRIOR_DEATHS, 0)                            AS PRIOR_DEATHS,
       CASE WHEN k.RECALL_DATE >= @first THEN 1 ELSE 0 END  AS IN_LAG_WINDOW
INTO v2.campaign_lag
FROM v2.campaigns AS k
LEFT JOIN agg AS a ON a.CAMPNO = k.CAMPNO;

ALTER TABLE v2.campaign_lag ADD CONSTRAINT pk_campaign_lag PRIMARY KEY (CAMPNO);

/* ---------- Complaint-level outcome ----------
   For each complaint x component: the first later recall of the same vehicle and
   component, if one happened. Lets us ask "what share of complaints were followed
   by a recall within N years?" without counting a complaint more than once. */
DROP TABLE IF EXISTS v2.complaint_outcomes;

WITH per_complaint AS (
    SELECT ODINO, COMPONENT_CLEAN,
           MIN(MFR_NAME_CLEAN) AS MFR_NAME_CLEAN,
           MIN(COMPLAINT_DATE) AS COMPLAINT_DATE,
           MAX(CRASH) AS CRASH, MAX(FIRE) AS FIRE, MAX(INJURED) AS INJURED, MAX(DEATHS) AS DEATHS
    FROM v2.complaints
    GROUP BY ODINO, COMPONENT_CLEAN
),
next_recall AS (
    SELECT ODINO, COMPONENT_CLEAN, MIN(RECALL_DATE) AS NEXT_RECALL_DATE, COUNT(DISTINCT CAMPNO) AS N_MATCHED_CAMPAIGNS
    FROM v2.complaint_recall_pairs
    GROUP BY ODINO, COMPONENT_CLEAN
)
SELECT pc.*,
       nr.NEXT_RECALL_DATE,
       ISNULL(nr.N_MATCHED_CAMPAIGNS, 0)                         AS N_MATCHED_CAMPAIGNS,
       DATEDIFF(DAY, pc.COMPLAINT_DATE, nr.NEXT_RECALL_DATE)    AS DAYS_TO_NEXT_RECALL,
       YEAR(pc.COMPLAINT_DATE)                                  AS COMPLAINT_YEAR
INTO v2.complaint_outcomes
FROM per_complaint AS pc
LEFT JOIN next_recall AS nr ON nr.ODINO = pc.ODINO AND nr.COMPONENT_CLEAN = pc.COMPONENT_CLEAN;

CREATE CLUSTERED INDEX ix_outcomes ON v2.complaint_outcomes (ODINO, COMPONENT_CLEAN);

/* ---------- Size of the match ---------- */
SELECT 'pairs (all OEMs, all components)' AS item, COUNT_BIG(*) AS n FROM v2.complaint_recall_pairs
UNION ALL SELECT 'distinct complaints matched', COUNT(DISTINCT ODINO) FROM v2.complaint_recall_pairs
UNION ALL SELECT 'campaigns with >=1 prior complaint', COUNT(*) FROM v2.campaign_lag WHERE PRIOR_COMPLAINTS > 0
UNION ALL SELECT 'campaigns in lag window (recall >= FIRST_RECALL_DATE)', COUNT(*) FROM v2.campaign_lag WHERE IN_LAG_WINDOW = 1;

SELECT AVG(1.0 * N_MATCHED_CAMPAIGNS) AS avg_campaigns_per_matched_complaint
FROM v2.complaint_outcomes WHERE N_MATCHED_CAMPAIGNS > 0;
