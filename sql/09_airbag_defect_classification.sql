/* ============================================================
   09  Air bag recalls: what actually goes wrong?
   ------------------------------------------------------------
   Classifies each AIR BAGS campaign by failure mode from its defect
   description.

   Method
   - Keywords live in one table (v2.airbag_keywords), so the rules are
     defined once.
   - Word-boundary matching: a plain '%OCS%' would match any word
     containing "ocs", '%cover%' would match "recover" and '%tear%'
     "steering". The text is padded and short keywords need a
     non-letter on each side.
   - First matching category by priority wins, so every campaign
     lands in exactly one category.
   - Counts are distinct campaigns from v2.campaigns (vehicles only).
   ============================================================ */
SET NOCOUNT ON;

DROP TABLE IF EXISTS v2.airbag_keywords;
CREATE TABLE v2.airbag_keywords (
    PRIORITY INT          NOT NULL,
    CATEGORY VARCHAR(60)  NOT NULL,
    PATTERN  VARCHAR(100) NOT NULL   -- LIKE pattern, matched against ' ' + UPPER(text) + ' '
);

INSERT INTO v2.airbag_keywords (PRIORITY, CATEGORY, PATTERN) VALUES
 (1, 'Inflator rupture / metal fragments', '%RUPTUR%'),
 (1, 'Inflator rupture / metal fragments', '%EXPLOD%'),
 (1, 'Inflator rupture / metal fragments', '%EXPLOSION%'),
 (1, 'Inflator rupture / metal fragments', '%METAL FRAGMENT%'),
 (1, 'Inflator rupture / metal fragments', '%SHRAPNEL%'),
 (1, 'Inflator rupture / metal fragments', '%EXCESSIVE INTERNAL PRESSURE%'),
 (2, 'Inadvertent deployment',             '%INADVERTENT%'),
 (2, 'Inadvertent deployment',             '%UNINTENDED%'),
 (2, 'Inadvertent deployment',             '%UNINTENTIONAL%'),
 (2, 'Inadvertent deployment',             '%UNEXPECTED%DEPLOY%'),
 (2, 'Inadvertent deployment',             '%DEPLOY WITHOUT%'),
 (3, 'Occupant classification / sensor',   '%OCCUPANT CLASSIFICATION%'),
 (3, 'Occupant classification / sensor',   '%OCCUPANT DETECTION%'),
 (3, 'Occupant classification / sensor',   '%[^A-Z]OCS[^A-Z]%'),
 (3, 'Occupant classification / sensor',   '%[^A-Z]ODS[^A-Z]%'),
 (3, 'Occupant classification / sensor',   '%SENSOR%'),
 (3, 'Occupant classification / sensor',   '%SEAT WEIGHT%'),
 (4, 'Software / calibration',             '%SOFTWARE%'),
 (4, 'Software / calibration',             '%CALIBRAT%'),
 (4, 'Software / calibration',             '%PROGRAMM%'),
 (5, 'Wiring / connector / clockspring',   '%WIRING%'),
 (5, 'Wiring / connector / clockspring',   '%WIRE HARNESS%'),
 (5, 'Wiring / connector / clockspring',   '%CONNECTOR%'),
 (5, 'Wiring / connector / clockspring',   '%CLOCKSPRING%'),
 (5, 'Wiring / connector / clockspring',   '%CLOCK SPRING%'),
 (5, 'Wiring / connector / clockspring',   '%CORRO%'),
 (5, 'Wiring / connector / clockspring',   '%SHORT CIRCUIT%'),
 (6, 'Will not deploy (other cause)',      '%NOT DEPLOY%'),
 (6, 'Will not deploy (other cause)',      '%FAIL TO DEPLOY%'),
 (6, 'Will not deploy (other cause)',      '%FAIL TO PROPERLY DEPLOY%'),
 (6, 'Will not deploy (other cause)',      '%NON-DEPLOY%'),
 (6, 'Will not deploy (other cause)',      '%NONDEPLOY%'),
 (6, 'Will not deploy (other cause)',      '%DEACTIVAT%'),
 (6, 'Will not deploy (other cause)',      '%NOT INFLATE%'),
 (7, 'Assembly / fastener',                '%[^A-Z]BOLT%'),
 (7, 'Assembly / fastener',                '%[^A-Z]WELD%'),
 (7, 'Assembly / fastener',                '%FASTENER%'),
 (7, 'Assembly / fastener',                '%[^A-Z]SCREW%'),
 (7, 'Assembly / fastener',                '%[^A-Z]RIVET%'),
 (7, 'Assembly / fastener',                '%IMPROPERLY INSTALLED%'),
 (7, 'Assembly / fastener',                '%NOT PROPERLY INSTALLED%'),
 (7, 'Assembly / fastener',                '%IMPROPERLY ASSEMBLED%'),
 (7, 'Assembly / fastener',                '%TORQUE%'),
 (8, 'Cushion tear / fold',                '%[^A-Z]TEAR[^A-Z]%'),
 (8, 'Cushion tear / fold',                '%[^A-Z]TORN[^A-Z]%'),
 (8, 'Cushion tear / fold',                '%CUSHION%'),
 (8, 'Cushion tear / fold',                '%FOLD%'),
 (9, 'Cover / trim / emblem',              '%[^A-Z]COVER%'),
 (9, 'Cover / trim / emblem',              '%EMBLEM%'),
 (9, 'Cover / trim / emblem',              '%SCORE LINE%'),
 (9, 'Cover / trim / emblem',              '%SHATTER%'),
 (9, 'Cover / trim / emblem',              '%[^A-Z]TRIM[^A-Z]%'),
 (10, 'Warning lamp / label / manual',     '%LABEL%'),
 (10, 'Warning lamp / label / manual',     '%WARNING LAMP%'),
 (10, 'Warning lamp / label / manual',     '%WARNING LIGHT%'),
 (10, 'Warning lamp / label / manual',     '%TELLTALE%'),
 (10, 'Warning lamp / label / manual',     '%OWNER''S MANUAL%'),
 (10, 'Warning lamp / label / manual',     '%INDICATOR%');

DROP TABLE IF EXISTS v2.airbag_campaign_category;
WITH airbag AS (
    SELECT DISTINCT CAMPNO
    FROM v2.recalls
    WHERE COMPONENT_CLEAN = 'AIR BAGS'
),
txt AS (
    SELECT a.CAMPNO, ' ' + UPPER(ISNULL(t.DEFECT_DESCRIPTION, '')) + ' ' AS TXT
    FROM airbag AS a
    JOIN v2.recall_text AS t ON t.CAMPNO = a.CAMPNO
),
first_match AS (
    SELECT t.CAMPNO, MIN(k.PRIORITY) AS PRIORITY
    FROM txt AS t
    JOIN v2.airbag_keywords AS k ON t.TXT LIKE k.PATTERN
    GROUP BY t.CAMPNO
)
SELECT t.CAMPNO,
       ISNULL(cat.CATEGORY, 'Uncategorized') AS CATEGORY,
       c.MFR_NAME_CLEAN, c.RECALL_YEAR, c.UNITS_AFFECTED, c.RECALL_ORIGIN
INTO v2.airbag_campaign_category
FROM txt AS t
JOIN v2.campaigns AS c ON c.CAMPNO = t.CAMPNO
LEFT JOIN first_match AS fm ON fm.CAMPNO = t.CAMPNO
LEFT JOIN (SELECT DISTINCT PRIORITY, CATEGORY FROM v2.airbag_keywords) AS cat ON cat.PRIORITY = fm.PRIORITY;
GO

CREATE OR ALTER VIEW v2.vw_airbag_categories AS
SELECT CATEGORY,
       COUNT(*) AS campaigns,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_campaigns,
       SUM(UNITS_AFFECTED) AS units_affected,
       CAST(100.0 * SUM(UNITS_AFFECTED) / SUM(SUM(UNITS_AFFECTED)) OVER () AS DECIMAL(5,1)) AS pct_units
FROM v2.airbag_campaign_category
GROUP BY CATEGORY;
GO

SELECT * FROM v2.vw_airbag_categories ORDER BY campaigns DESC;

/* Validation sample: 3 random campaigns per category, read these to check the rules */
SELECT CATEGORY, CAMPNO, LEFT(DEFECT_DESCRIPTION, 220) AS DEFECT_DESCRIPTION
FROM (
    SELECT a.CATEGORY, a.CAMPNO, t.DEFECT_DESCRIPTION,
           ROW_NUMBER() OVER (PARTITION BY a.CATEGORY ORDER BY CHECKSUM(a.CAMPNO)) AS rn
    FROM v2.airbag_campaign_category AS a
    JOIN v2.recall_text AS t ON t.CAMPNO = a.CAMPNO
) AS x
WHERE rn <= 3
ORDER BY CATEGORY, rn;
