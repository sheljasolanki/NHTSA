# NHTSA Recall Lag Project: Decision Log

This log records the methodology decisions made in the project and the reasoning behind each one, so the "why" is documented alongside the "what". Findings themselves are in [Results/results.md](Results/results.md).

---

## 1. Data Source: Why NHTSA

NHTSA (National Highway Traffic Safety Administration) is the U.S. federal regulator for vehicle safety. It publishes two relevant datasets publicly, in bulk, with no login or API key required:

- **Complaints:** every safety complaint filed by a consumer since 1995
- **Recalls:** every official recall campaign on record

**Why NHTSA specifically:** an equivalent Indian data source was investigated (MoRTH's Vehicle Recall Portal, data.gov.in). Neither offers structured, bulk-downloadable data comparable to NHTSA's flat files; India's system is a complaint-filing portal, not an open dataset. NHTSA was chosen as the available, structurally rich option, with the India gap noted as future work.

---

## 2. The Core Question

The project measures **recall lag**: the time between when owners start complaining to NHTSA about a vehicle component and when that vehicle is recalled for it. This is a measurement of time-to-action, explicitly not a claim about negligence or fault.

Lag is measured per recall campaign, from the **first** matching complaint to the recall date, and also from the **third** matching complaint (the "signal" lag, see Section 16).

---

## 3. File Selection: Verify Against the Data, Not the Filename

- Downloaded `FLAT_CMPL` (complaints) and the recall files `FLAT_RCL_PRE_2010` and `FLAT_RCL_POST_2010`.
- The recall filenames suggest a 2010 split in coverage. Checking the actual `RCDATE` range showed recalls from 1966 to 2026 across the two files; the split is only how NHTSA stores history, and the schema is identical. Both files are loaded and concatenated.
- Complaint dates run from 1995-01-03 to 2026-08-12, which sets the data extract date used throughout.

---

## 4. Column Selection

Each raw file has 29–51 columns. Only columns the analysis uses are read, all as text first so nothing is silently converted (e.g. model year `1987` becoming `1987.0`).

- **Complaints:** `CMPLID`, `ODINO`, `MFR_NAME`, `MAKETXT`, `MODELTXT`, `YEARTXT`, `COMPDESC`, `DATEA`, `FAILDATE`, `CRASH`, `FIRE`, `INJURED`, `DEATHS`, `PROD_TYPE`
- **Recalls:** `RECORD_ID`, `CAMPNO`, `MFGNAME`, `MAKETXT`, `MODELTXT`, `YEARTXT`, `COMPNAME`, `RCDATE`, `RCLTYPECD`, `POTAFF`, `INFLUENCED_BY`, `DO_NOT_DRIVE`, `PARK_OUTSIDE`, `DESC_DEFECT`, `CONEQUENCE_DEFECT`

**Kept deliberately:**
- `POTAFF` (units affected), so recall size can be analysed.
- `INFLUENCED_BY` (manufacturer vs NHTSA-influenced), which drives Finding 12.
- `DO_NOT_DRIVE` / `PARK_OUTSIDE` advisories, as a severity marker on the recall side.

**Optional:** complaint narratives (`CDESCR`, about 1.5 GB) are not needed for this analysis. A flag in the notebook loads them into a separate table for future text analysis.

---

## 5. Choosing the Core Date Column: DATEA vs FAILDATE

- `FAILDATE` = when the owner says the failure happened (closer to reality, but self-reported and noisy: a `19010101` placeholder and dates after the complaint was filed)
- `DATEA` = when NHTSA received the complaint (complete, set by NHTSA)

**Decision:** use `DATEA` as the complaint date. Spike detection and lag are about complaints *received*, so `DATEA` matches the question and needs no imputation. `FAILDATE` is kept as an optional field, with 6,391 placeholder or impossible values set to missing.

**Limitation:** the project measures filing-to-recall lag, not incident-to-recall lag.

---

## 6. Tech Stack

- **Cleaning:** pandas with Arrow-backed strings, which use a fraction of the memory of Python objects. This matters on an 8 GB machine with SQL Server running alongside.
- **Database:** Microsoft SQL Server 2022. Window functions, `PERCENTILE_CONT`, clustered index design and views handle the joins and aggregation.
- **Statistics and charts:** SciPy and matplotlib in a second notebook, for what SQL doesn't do well (bootstrap confidence intervals, significance tests).
- **Pipeline shape:** Python cleans and loads; SQL builds the matched tables and analysis views; Python reads the views for statistics and charts. A PowerShell script runs every SQL script in order and saves each output.

---

## 7. Date Cleaning

- Raw dates arrive as `YYYYMMDD` text and are converted with `pd.to_datetime(..., format="%Y%m%d", errors="coerce")`, so unparseable values become missing instead of crashing, and the null rate can be measured.
- Placeholder values (`1901-01-01`) are caught explicitly, since a null check alone misses "fake but present" dates.
- Ranges are sanity-checked: no complaint or recall dates in the future.
- Model year `9999` is NHTSA's "unknown"; anything outside 1949 to (extract year + 2) is treated as missing (0.69% of complaints, 0.20% of recalls).

---

## 8. Scope: Vehicle Records Only

NHTSA regulates every motor-vehicle-related product, so both files mix vehicles with tires, child seats and aftermarket equipment.

**Decision:** keep vehicle records only, using NHTSA's own type fields: `PROD_TYPE = 'V'` for complaints (71,982 rows removed) and `RCLTYPECD = 'V'` for recalls (41,095 rows removed). This is more reliable than filtering on manufacturer names, because a tire or child-seat complaint can name a car manufacturer.

---

## 9. Manufacturer: Vehicle Make → Parent OEM

The legal-entity name fields (`MFR_NAME`, `MFGNAME`) have thousands of spellings and include merged companies (`DAIMLERCHRYSLER` covers both Chrysler and Mercedes vehicles), so they don't group reliably.

**Decision:** map the **make** field (`CHEVROLET`, `LEXUS`, `JEEP`), which is short and clean, to its parent manufacturer with an explicit lookup table (e.g. `LEXUS` → Toyota, `JEEP` → Chrysler, `MINI` → BMW).

**Reasoning:**
- Every mapping is visible and auditable, with no similarity threshold to tune.
- Makes are normalised (uppercase, letters and digits only), so `Mercedes Benz` and `MERCEDES-BENZ` map the same way.
- Volvo heavy trucks share the `VOLVO` make, so they're removed by model pattern (`VNL`, `VHD`, ...).
- Every make that doesn't map is written to `Results/cleaning/unmapped_makes.csv` and reviewed. That audit is how smaller brands were added; what's left is motorcycles, RVs, trucks, buses and trailers, which are out of scope.
- `CHRYSLER` is used as the parent label for Dodge, Jeep, Ram and Fiat.

---

## 10. Model Name Normalisation

The join needs to match the same vehicle in both files, but model names are typed differently (`F-150` vs `F150`, `MX-5 MIATA` vs `MX5 MIATA`).

**Decision:** `MODEL_NORM` keeps letters and digits only; placeholder values (`UNKNOWN`, `NA`, `OTHER`) become missing. The raw name is kept in `MODEL_NAME`. Check: 98.65% of complaint make + model pairs also appear in the recall data.

---

## 11. Column Naming

Final column names are set once in the cleaning notebook, and the SQL scripts use them as-is:

- `MFR_NAME` / `MFGNAME` → `MFR_NAME_RAW`; the mapped parent OEM is `MFR_NAME_CLEAN`
- `COMPDESC` / `COMPNAME` → `COMPONENT_RAW`; the top-level category is `COMPONENT_CLEAN`
- `YEARTXT` → `MODEL_YEAR` (the vehicle's model-year designation, not the year of the complaint or recall)
- `DATEA` → `COMPLAINT_DATE`, `RCDATE` → `RECALL_DATE`, `FAILDATE` → `FAIL_DATE`
- `POTAFF` → `UNITS_AFFECTED`
- `CONEQUENCE_DEFECT` → `CONSEQUENCE_DESCRIPTION` (fixing NHTSA's typo)

`CMPLID` was confirmed unique (the row-level ID). `ODINO` is not unique: one complaint appears on one row per component line it names, so `ODINO` is the true "one complaint" key (Section 13). `CAMPNO` is not unique in the recall file either, since one campaign covers many vehicles.

---

## 12. Component Crosswalk: Parsing, Not Matching

Both component fields use a colon-delimited hierarchy (`AIR BAGS:FRONTAL:SENSOR`). Rather than fuzzy-matching hundreds of raw strings, the top-level category (text before the first colon) is extracted directly, which turns a matching problem into a parsing problem. A set comparison confirmed every recall category exists in the complaint vocabulary.

Complaint-only categories were inspected by hand rather than assumed to be errors:
- True naming variants were aliased (`COMMUNICATIONS` → `COMMUNICATION`, `ENGINE AND ENGINE COOLING` → `ENGINE`).
- Legacy categories with no recall equivalent (`FIRERELATED`, `ROLLOVER`) were kept, since they still count for severity.
- Free-text entries from car-seat complaint forms were measured first (556 rows, 0.03% of complaints) and then dropped as negligible.

---

## 13. One Complaint, Many Rows

A complaint (`ODINO`) gets one row per component line it names, and several lines can collapse to the same top-level component (`AIR BAGS:FRONTAL` and `AIR BAGS:SIDE` both become `AIR BAGS`). Summing deaths or counting rows over the raw file would count the same complaint several times.

**Decision:** collapse to one row per complaint × vehicle × component, and count complaints with `COUNT(DISTINCT ODINO)` in SQL. Result: 1,550,612 distinct complaints. Recalls are de-duplicated the same way (one row per campaign × vehicle × component), and campaign-level counts come from a separate one-row-per-campaign table.

---

## 14. Joining Complaints to Recalls

No shared row-level ID exists between complaints and recalls; they are different kinds of record.

**Decision:** match a complaint to a recall only when the recall covers the **same vehicle and the same component**:

- same parent manufacturer (`MFR_NAME_CLEAN`)
- same top-level component (`COMPONENT_CLEAN`)
- same model (`MODEL_NORM`) and model year (`MODEL_YEAR`)
- complaint filed before the recall, within the lookback window (Section 15)

**Reasoning:** matching on manufacturer + component alone would pair a Ford F-150 engine complaint with every Ford engine recall, most of them for unrelated vehicles. With model and model year in the key, each matched complaint pairs with 1.7 recalls on average, and the full join is 397,145 pairs across all manufacturers and components.

**Index design:** both tables are clustered on the match key, equality columns first and the date last: `(MFR_NAME_CLEAN, COMPONENT_CLEAN, MODEL_NORM, MODEL_YEAR, date)`. That makes the join a merge of sorted ranges, and it runs in about 25 seconds.

**Query diagnosis:** when a query looked stuck, `sys.dm_exec_requests` (`status`, `wait_type`, `cpu_time`) was used to tell a working query from a blocked one. Parallel plans stalled on this memory-constrained machine (`CXSYNC_PORT` waits), so the database is set to `MAXDOP = 1`; at this table size parallelism gains little.

---

## 15. The Lookback Window

A short window caps the lag by construction: with a 12-month window, no lag above 365 days can exist, so the statistics describe the filter rather than the data.

**Decision:** a 10-year lookback, and lag measured only for recalls from 2005 onward. Complaints start in 1995, so a recall before 2005 couldn't "see" a full 10 years of complaints and its lag would be cut short (left truncation).

**Sensitivity check:** on the same campaigns, the median lag is 302 days with a 1-year cap, 526 with 2 years, 730 with 5 and 766 with 10. The answer stabilises between 5 and 10 years, which supports the 10-year choice. Parameters live in one `v2.params` table, so no script hard-codes them.

---

## 16. Unit of Analysis: The Recall Campaign

If lag were measured per complaint–recall pair, components with many complaints would be counted thousands of times and dominate every median.

**Decision:** one observation per recall campaign: days from the first matching complaint to the recall. Two refinements:
- **Signal lag:** days from the 3rd matching complaint, because a single stray early complaint can make the first-complaint lag look very long. 192 campaigns sit at the 10-year cap, which is where this matters.
- Campaigns with no matching complaint are kept and counted. They show that half of recalls are not preceded by any complaint (Finding 1).

---

## 17. Full Data; Scope Only for Charts

The join is small enough to run on every manufacturer and component, so **all analysis uses the full data**. The top 10 manufacturers and top 10 components by distinct complaints (`v2.scope_oems`, `v2.scope_components`) are used only to keep charts readable. `UNKNOWN OR OTHER` is excluded from the component scope, since it can't match a specific recall type.

Groups with too few campaigns to rank are reported with their sample size or left out of rankings with a note (e.g. non-hydraulic service brakes, 14 campaigns).

---

## 18. Severity by Component

Which components carry the most severe real-world outcomes (crash, fire, injury, death), independent of whether a recall followed.

- Each complaint is counted once per component (Section 13).
- Both **totals** and **rates per 1,000 complaints** are reported. Totals mostly track complaint volume (engine has many complaints, so many deaths in total, but a low rate); rates show risk per complaint (tires and seat belts are highest).
- Only components with at least 1,000 complaints are ranked by rate.
- `CRASH` and `FIRE` were confirmed as clean `Y`/`N` flags before use.

---

## 19. Does Severity Affect Recall Response?

Tested per complaint, not per pair, so each complaint counts once.

- **Recall rate by severity tier** (fatal, injury, crash, fire, none): share of complaints followed by a recall of the same vehicle and component within 2 years. Only complaints filed at least 2 years before the extract are counted, so recent complaints don't look "never recalled" just because there hasn't been time (right-censoring). Tested with chi-square.
- **Days to recall, crash vs no crash**, among complaints that were recalled: Mann-Whitney test, with rank-biserial correlation reported as the effect size so a significant-but-small difference isn't overstated.

The result (severe complaints are slightly *less* likely to be followed by a recall) is reported as found, not reshaped to fit the intuitive hypothesis. Possible explanations are noted as untested.

---

## 20. How Often Does a Complaint Lead to a Recall?

"Did a complaint fall inside some recall window for that manufacturer + component" is almost always true for busy components, so it measures recall density, not follow-through.

**Decision:** ask two specific questions instead:
- **Complaint side:** of complaints filed at least 5 years before the extract, what share saw the same vehicle recalled for the same component within 1, 2 and 5 years?
- **Recall side:** what share of recall campaigns had at least one matching complaint beforehand?

---

## 21. Spike Detection

A month is a spike when complaints for a manufacturer + component reach at least 2× the trailing 6-month average, with that average at least 5.

- **Calendar spine:** a recursive CTE builds every month and zero-fills months with no complaints, so "6 preceding rows" always means 6 months.
- **Every series** is included, not only those that later had a recall, to avoid selection bias.
- **Baseline:** spike months are compared with normal months (lift), and tested with Fisher's exact test. Without a baseline, "15% of recalls had a spike beforehand" looks like a signal; it matches the 15% baseline for all months.
- **Reverse causation:** spikes in the 2 months after a recall (owners complaining once a recall is announced) are separated from spikes that come before one.

---

## 22. Air Bag Recalls: Classifying Defect Text

The free-text defect description is classified into failure modes with keyword rules, one category per campaign.

**Method:**
- Text is analysed once per campaign (`recall_text` has one row per `CAMPNO`); the recall file repeats the same text on every vehicle row, which would overweight campaigns covering many vehicles.
- Keywords live in one table (`v2.airbag_keywords`) with a priority; the first matching category wins, so every campaign lands in exactly one category.
- **Word-boundary matching:** a plain `'%OCS%'` matches any word containing "ocs", `'%cover%'` matches "recover" and `'%tear%'` matches "steering". The text is padded and short keywords need a non-letter on each side.
- **Validation:** random samples (`ORDER BY NEWID()`) from each category and from the uncategorized set were read by hand. Reading the uncategorized sample surfaced real missed patterns, such as covers or emblems breaking off during deployment, which became their own category.
- **Stopping point:** 26% of campaigns remain uncategorized. Further keywords risk misclassifying campaigns already placed correctly, so the long tail is reported as a finding (many defect causes are rare and idiosyncratic); text classification on the full descriptions is the next step.
- Vehicles affected (`UNITS_AFFECTED`) are summed per campaign, which shows inflator ruptures are 22% of campaigns but 49% of vehicles.

---

## 23. Recall Origin and Size

`INFLUENCED_BY` records whether NHTSA's Office of Defects Investigation influenced a recall (`ODI`, `OVSC`, `ISSUE_INVGSTN`) or the manufacturer started it (`MFR`). Recalls are grouped into manufacturer-initiated and NHTSA-influenced, and compared on lag, prior complaints, vehicles affected and "do not drive" advisories (Mann-Whitney tests).

**Interpretive caution:** this is an association. NHTSA tends to step in on cases that are already dragging, so a longer lag does not mean NHTSA involvement causes delay.

---

## 24. Statistical Methods

- **Medians, not means:** lag is heavily right-skewed.
- **95% confidence intervals** on medians by bootstrap, so overlapping intervals are visible when comparing manufacturers and components.
- **Kruskal-Wallis** across manufacturers and across components, and **eta-squared on log lag** to compare how much variation each explains (component about 5%, manufacturer about 1%).
- **Spearman correlation** for the trend in median lag by recall year. Lag is grouped by recall year, not complaint year, so every year's campaigns are complete and recent years don't need to be cut off.

---

## 25. Validation and Reproducibility

- Every filtering step in the cleaning notebook logs rows in and out, saved to `Results/cleaning/cleaning_lineage.csv`.
- Validation checks fail loudly instead of printing numbers to eyeball: unique keys, no missing or future dates, every manufacturer mapped, every recall component present in the complaint vocabulary, one text row per campaign.
- Notebook, SQL scripts and analysis notebook are all re-runnable; every number in the results is saved to `Results/key_numbers.json`, `Results/tables/` or `Results/sql_output/`.

---

## 26. Known Limitations

- **Model names:** trims coded differently (`F-250 SD` vs `F-250`) won't match, so some real matches are missed.
- **Component coding** can differ between a complaint and a recall for the same defect (e.g. an air bag warning light filed under electrical).
- A complaint naming two components counts under both in per-component tables.
- **Filing-to-recall**, not incident-to-recall (Section 5).
- **Associations, not causes:** none of the results show why a particular recall was slow.
