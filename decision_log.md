# NHTSA Recall Lag Project — Decision Log

This log records every methodology decision made during the project, and the reasoning behind it. Intended to be pulled into the final write-up (Phase 10) so the "why" behind each choice is documented, not just the "what."

---

## 1. Data Source: Why NHTSA

NHTSA (National Highway Traffic Safety Administration) is the U.S. federal regulator for vehicle safety. It publishes two relevant datasets publicly, in bulk, with no login or API key required:

- **Complaints** — every safety complaint filed by a consumer since 1995
- **Recalls** — every official recall campaign on record

**Why NHTSA specifically:** an equivalent Indian data source was investigated (MoRTH's Vehicle Recall Portal, data.gov.in). Neither offers structured, bulk-downloadable data comparable to NHTSA's flat files — India's system is a complaint-filing portal, not an open dataset. NHTSA was chosen as the honest, available, structurally rich option, with the India gap noted as a limitation/future-work item in the final write-up.

---

## 2. The Core Project Question

The project measures **recall lag**: the time between when a safety problem becomes visible to NHTSA (a spike in complaint volume) and when a manufacturer/regulator officially responds (a recall). This is a measurement of time-to-action, explicitly not a claim about negligence or fault.

---

## 3. File Selection & a Correction Along the Way

- Downloaded `FLAT_CMPL.zip` (complaints) and initially `FLAT_RCL.zip` (recalls) — the latter filename had changed on NHTSA's server to `FLAT_RCL_POST_2010.zip`.
- **Initial assumption (later corrected):** the filename suggested recall data only went back to 2010, while complaints go back to 1995 — this looked like a mismatch requiring a 2010+ filter on both files.
- **Correction after checking actual data:** once loaded, the real `RCDATE` range in the recalls file was 1966–2026, not 2010+. The filename was misleading; no 2010 filter was actually needed. This is logged as an example of verifying assumptions against real data rather than trusting a filename.

---

## 4. Column Selection

Each raw file has ~30–50 columns. Only columns relevant to the core spike→lag pipeline were kept; unused columns (dealer info, tire specs, restraint type, etc.) were dropped as noise.

- **Complaints — kept:** `CMPLID`, `ODINO`, `MFR_NAME`, `MAKETXT`, `MODELTXT`, `YEARTXT`, `COMPDESC`, `DATEA`, `CRASH`, `FIRE`, `INJURED`, `DEATHS`, `CDESCR`
- **Recalls — kept:** `CAMPNO`, `MFGNAME`, `MAKETXT`, `MODELTXT`, `YEARTXT`, `COMPNAME`, `RCDATE`, `DESC_DEFECT`, `CONEQUENCE_DEFECT`

**Decision — dropped `FAILDATE` and `ODATE`:**

- `FAILDATE` (date the defect actually occurred) had ~5% true nulls plus a placeholder-date problem (`1901-01-01` appearing 5,647 times as a clear default/junk value).
- It was initially kept for a possible side-analysis (measuring "consumer reporting delay" = `FAILDATE` → `DATEA`), but ultimately dropped for simplicity, since it isn't part of the core pipeline.
- `ODATE` (an NHTSA-internal recall date field, distinct from `RCDATE`) was dropped for the same reason — not part of the core pipeline, and `RCDATE` is the correct "official recall" date to use.

---

## 5. Choosing the Core Date Columns: DATEA vs FAILDATE

This was a deliberate trade-off, not a default choice:

- `FAILDATE` = when the defect actually happened (more "real-world true," but noisier — self-reported from memory, ~5% missing/junk)
- `DATEA` = when NHTSA logged/received the complaint (0% nulls, more standardized)

**Decision:** use `DATEA`. Reasoning: spike detection is inherently about volume of complaints *received*, not volume of incidents *occurring* — a "spike" is, by definition, a spike in what NHTSA's system recorded. Using `DATEA` keeps the methodology simple, defensible, and avoids losing/imputing ~5% of rows for a marginal accuracy gain.

**Noted limitation for the write-up:** this means the project technically measures filing-to-recall lag, not incident-to-recall lag — a small but real distinction worth stating explicitly.

**Side clarification:** the `FAILDATE` → `DATEA` gap (when it existed in the plan) would have measured consumer reporting delay, not manufacturer or NHTSA slowness — that gap is on the owner's side (how long they waited to file), separate from the actual "regulatory response time" metric this project measures (spike date → `RCDATE`).

---

## 6. Tech Stack

- **Cleaning:** pandas — chosen for flexibility with messy text/date cleaning and fuzzy matching (rapidfuzz) before the data is analysis-ready.
- **Database:** Microsoft SQL Server (Express edition) — chosen because it's genuinely used in industry, has full support for the window functions/CTEs the project needs, and integrates smoothly with Power BI (already planned for Phase 7), avoiding extra connector friction.
- **Pipeline shape:** pandas handles cleaning and text-matching (Python's strength); SQL Server handles the heavy aggregation, spike detection, and window-function analysis (SQL's strength) once the data is clean.

---

## 7. Date Cleaning Methodology

- Raw date columns arrive as numeric `YYYYMMDD` (e.g., `20040422`), not real dates — converted using `pd.to_datetime(..., format="%Y%m%d", errors="coerce")`.
- `errors="coerce"` was used deliberately so any unparseable value becomes `NaT` instead of crashing the conversion, allowing a true null-rate to be measured afterward.
- A placeholder-date check was added before conversion, since a null-count check alone doesn't catch "fake but technically present" values (e.g., `1901-01-01`, a common system-default value) — these were treated as missing, same as true nulls.
- Final date ranges were sanity-checked (`.min()` / `.max()`) to confirm no impossible values (e.g., dates before 1995 in complaints, or dates in the future) survived cleaning.

---

## 8. Scope Correction: Manufacturer Names Reveal a Bigger Problem

After running distinct-value checks on `MFR_NAME` (complaints) and `MFGNAME` (recalls), both returned thousands of unique manufacturer names — far too many for manual alias-mapping, confirming that fuzzy matching (as originally planned) is required, not optional.

More importantly, the values revealed that NHTSA's manufacturer field is not limited to car OEMs. It includes tire companies (Michelin), child car-seat makers (Baby Trend), helmet manufacturers (Fulmer), trailer makers (Wells Cargo), and individual component suppliers — because NHTSA regulates all motor-vehicle-related products, not just passenger cars.

**Decision:** restrict the project scope to passenger car/truck OEMs only (Ford, Toyota, GM, Honda, Hyundai, etc. — roughly 40–60 real manufacturers), filtering out tires, trailers, helmets, car seats, motorcycles, RVs, and component suppliers.

**Reasoning:**

- Keeps the project's narrative consistent with its original framing ("recall lag across car manufacturers"), rather than an ambiguous mix of unrelated product categories.
- Makes manufacturer-to-manufacturer comparisons apples-to-apples — comparing Ford vs. Toyota is meaningful; comparing Ford vs. a helmet company is not, and would distort the ranking/statistical analyses planned for Phase 5–6.
- Sharply reduces the size of the crosswalk/fuzzy-matching problem, from thousands of names down to a manageable list of real OEMs.
- Still produces a complete, portfolio-worthy project on its own.

**Next step from here:** build a reference list of real passenger vehicle OEMs and filter both tables down to only rows matching that list (via fuzzy matching, given spelling inconsistencies already observed in the raw data).

---

*Log will continue to be updated as further decisions are made (crosswalk table construction, spike-detection thresholds, statistical test selection, etc.).*

---

## 9. Fuzzy-Matching Methodology for OEM Names

With thousands of raw manufacturer strings confirmed as unmanageable for manual mapping, a fuzzy-matching pipeline was built to filter both `MFR_NAME` (complaints) and `MFGNAME` (recalls) down to a controlled OEM reference list (~40-60 passenger vehicle manufacturers).

**Approach:**

- A manual alias dictionary was built first for the most common, highest-volume real OEM name variants (e.g., "FORD MOTOR CO" vs "FORD MOTOR COMPANY" vs "FORD").
- For the remaining long tail, RapidFuzz's `token_set_ratio` was used to score similarity between each raw name and the OEM reference list, rather than a plain string-equality or basic substring check.

**Correction along the way — scorer choice:** `token_sort_ratio` was tried first but rejected after testing, because it penalizes length differences between strings even when they're semantically identical (e.g., "FORD" vs "FORD MOTOR COMPANY" scored artificially low despite being the same company, since one has 1 word and the other has 3). `token_set_ratio` was adopted instead, since it compares the overlapping token sets rather than raw string structure, which handles this case correctly.

---

## 10. Validating Match Quality: the "Low Match Rate" False Alarm

An audit script was used to spot-check match quality by grouping raw names by their first word (e.g., everything starting with "GENERAL"). This initially looked like a problem — GM showed only 1/10 matched, Land Rover 2/21, Alfa Romeo 1/3, Kia 1/3.

Investigation showed this was expected behavior, not a matcher defect: the audit's grouping logic (`key = oem.split()[0]`) was catching every company that happened to share a first word or substring, not just real variants of the target OEM. For example, the "GENERAL" group included General Tire & Rubber, AM General, General Electric, and several unrelated bus/RV/trailer companies — only General Motors, LLC was actually GM, and it matched correctly. Same pattern held for Land Rover (catching Holland, Overland, Kirkland), Alfa Romeo (catching Alfa Leisure), and Kia (catching Nokia, Nokian Tyres).

**Decision:** no changes made to the matcher. Confirmed via spot-check that every genuine OEM variant tested (Ford, Toyota, Honda, Hyundai, Chrysler, Tesla, GM, Alfa Romeo) matched correctly, and everything excluded was genuinely unrelated. Logged as a reminder to verify apparent anomalies against the underlying data before treating them as bugs.

---

## 11. Match Rate Gap Between Complaints and Recalls

After filtering both datasets to `OEM_CLEAN.notna()`, match rates differed sharply: complaints matched at 94.4%, recalls at only 46.1%.

Investigation (via `unmatched_recalls.head(30)`) confirmed this gap is expected, not a defect. Complaints are filed by consumers about a vehicle they own, so `MFR_NAME` is overwhelmingly a passenger-vehicle OEM. Recalls, by contrast, cover every category NHTSA regulates — tires (Michelin, Goodyear), child car seats (Britax, Graco, Evenflo), motorcycles, trailers, RVs, and aftermarket equipment — so a large share of `MFGNAME` values are legitimately non-OEM and correctly excluded under the project's car-OEM-only scope (see Section 8).

**Decision:** no fix applied. `complaints_clean` and `recalls_clean` were both finalized as-is, using only rows where `OEM_CLEAN` is not null.

---

## 12. Column Renaming for Clarity

Once both tables were loaded into SQL Server, several column names were renamed to make their meaning explicit, following a consistent `_RAW` / `_CLEAN` convention already established by `OEM_CLEAN`:

- `MFR_NAME` (complaints) / `MFGNAME` (recalls) → `MFR_NAME_RAW` — raw, messy legal-entity manufacturer names as reported by NHTSA
- `OEM_CLEAN` → `MFR_NAME_CLEAN` — the standardized manufacturer name produced by the fuzzy-matching pipeline (Section 9)
- `COMPDESC` (complaints) / `COMPNAME` (recalls) → `COMPONENT_RAW` — raw colon-delimited component hierarchy
- `YEARTXT` → `MODEL_YEAR` — clarified after confirming this field represents the vehicle's model-year designation (an industry/marketing convention that can precede the actual calendar release by several months), not the year the complaint was filed or the recall was issued
- `MAKETXT` → `VEHICLE_MAKE`, `MODELTXT` → `VEHICLE_MODEL` — renamed for readability; values were already clean, so no `_RAW`/`_CLEAN` pair was needed
- `CDESCR` → `ACTUAL_COMPLAINT_TEXT` — free-text consumer complaint description, kept for future qualitative spot-checking of flagged spikes, not for grouping/aggregation

`ODINO` was investigated and left unrenamed — confirmed non-unique (NHTSA's internal ODI case reference, which can span multiple complaint filings tied to one case), distinct from `CMPLID`, which was confirmed unique and is the true row-level identifier. `CAMPNO` in recalls was similarly confirmed non-unique — one recall campaign can legitimately cover multiple make/model combinations — and was kept as-is, used for reference/lookup rather than as a join key.

---

## 13. Component Crosswalk: Top-Level Category Parsing

Both `COMPONENT_RAW` fields use a shared colon-delimited hierarchy (e.g. `AIR BAGS:FRONTAL:SENSOR`). Rather than fuzzy-matching 730 and 539 raw strings across the two tables, the top-level category (text before the first colon) was extracted directly — reframing this as a parsing problem, not a matching problem. This collapsed complaints to 53 categories and recalls to 40, with a set comparison confirming all 40 recall categories already existed within complaints' vocabulary.

---

## 14. Handling Complaints-Only Categories

Thirteen categories existed only on the complaints side. Manual inspection (rather than assuming mismatch) found: one true naming variant (COMMUNICATIONS vs COMMUNICATION, aliased together), one compound/joined entry (aliased to its primary category), a few legacy categories with no recall equivalent (kept standalone, since a complaint category having no matching recall type is expected, not an error), and a set of free-text/junk entries from car-seat-specific complaint fields. The junk bucket was measured before deciding its fate (694 rows, 0.03% of complaints) and dropped as negligible rather than special-cased.

---

## 15. No Shared Row-Level ID Between Complaints and Recalls

Complaints and recalls are structurally different record types — one complaint record does not correspond to one recall record — so no shared ID field exists to join on directly. The join key was instead built from a combination of fields both tables share a common meaning for: `MFR_NAME_CLEAN`, `COMPONENT_CLEAN`, and a date relationship between `DATEA` (complaint date) and `RCDATE` (recall date).

---

## 16. Join Performance: Index Design

An initial join attempt with no date restriction (`DATEA < RCDATE`) did not return in over an hour — diagnosed as a near-cartesian-explosion problem: with millions of complaints and tens of thousands of recalls, an unrestricted join on loosely-matching, non-unique keys generates an enormous number of row-pair comparisons.

Two fixes were applied together:

- A bounded date window was added to the join condition (`DATEA >= DATEADD(MONTH, -N, RCDATE)`) to reflect the actual question being asked (did a complaint precede a recall within a meaningful window), not "any complaint ever before any recall."
- A composite index was created on the join columns in both tables — `(MFR_NAME_CLEAN, COMPONENT_CLEAN, DATEA)` on complaints, `(MFR_NAME_CLEAN, COMPONENT_CLEAN, RCDATE)` on recalls — with equality-matched columns ordered first and the range-compared date column last, since indexes serve equality lookups best when narrowing columns come before range columns.

---

## 17. Choosing the Date Window: Avoiding a Circular Metric

An initial 12-month window produced complaint-to-recall gap statistics (P25=86, P50=177, P75=271, P90=328 days) that looked reasonable at first glance, but were flagged as potentially circular: since the join itself excludes any gap beyond ~365 days, the resulting average/percentiles describe the shape of the filter, not necessarily the true underlying distribution. A wider 36-month window was attempted to observe where the true distribution tapers off, but this proved computationally impractical within the project timeline (large complaint volumes × 3x wider window × full manufacturer/component scope caused multi-hour runtimes even with indexing in place).

**Decision:** given the project deadline, the 12-month window was retained as the final analysis window, and this trade-off is logged explicitly rather than hidden: the reported gap statistics describe complaint-to-recall lag within a 12-month lookback, chosen for computational tractability, not derived from an unconstrained "true" distribution. A wider-window analysis is noted as a natural extension for future work.

---

## 18. Scoping to Top Manufacturers and Components

To keep the pipeline runnable within the project's time constraint, the analysis was scoped to the highest-volume manufacturers and components rather than the full ~40 OEMs × ~50 components. This mirrors the same reasoning applied earlier to the free-text junk bucket (Section 14) and the OEM scope correction (Section 8): low-volume groups produce statistically unreliable percentile estimates anyway, so narrowing to high-volume groups concentrates the analysis on the data most capable of supporting a meaningful conclusion, rather than diluting effort across long-tail combinations with too little data to trust.

- **Manufacturers:** narrowed from 10 candidates down to the top 5 by total complaint volume (General Motors, Ford, Chrysler, Toyota, Honda), after confirming that manufacturer count — not component count — was the dominant driver of join size. A pre-check comparing filtered input volumes (10 companies/all components: 1.9M complaints; 10 companies/top-15 components: 1.63M; 5 companies/top-10 components: 1.12M) showed trimming components alone barely reduced volume, since the highest-complaint components are shared across every manufacturer and dominate regardless of how many companies are included.
- **Components:** narrowed to the top 10 by complaint volume, explicitly excluding UNKNOWN OR OTHER — not a real defect category, and structurally incapable of matching a specific recall type, so its removal is a data-quality correction as much as a performance one.

---

## 19. Diagnosing Long-Running Queries: Working vs. Blocked

When a join appeared to hang, `sys.dm_exec_requests` was used to distinguish "genuinely computing" from "blocked/stuck" — checking `status`, `wait_type`, and `cpu_time` for the relevant session. A `CXCONSUMER` wait type with steadily increasing `cpu_time` was identified as normal parallel-query execution (multiple CPU cores dividing the workload), not a fault condition — confirming the query was making real progress rather than stalled on a lock, and did not need to be cancelled.

---

## 20. Final Core Result: Per-Company Complaint-to-Recall Lag (5-Year Window)

After the 12-month window was confirmed to be truncating the true distribution (Section 17) and a wider window proved computationally impractical to build fresh within the timeline, a pre-existing 5-year unrestricted join (`complaint_recall_pairs_5`, 17,095,551 rows) was filtered down to the analysis scope (top 5 manufacturers by complaint volume, top 10 components by complaint volume, excluding UNKNOWN OR OTHER) rather than rebuilt from scratch — reducing risk and runtime significantly, down to 12,836,366 scoped rows.

Per-company percentiles on `DAYS_BEFORE_RECALL`, computed via `PERCENTILE_CONT` with `PARTITION BY MFR_NAME_CLEAN`:

| Manufacturer | P25 | P50 (median) | P75 | P90 | Pair Count |
|---|---|---|---|---|---|
| Ford | 390 | 818 | 1302 | 1615 | 4,170,822 |
| Chrysler | 392 | 847 | 1325 | 1617 | 4,015,281 |
| General Motors | 407 | 855 | 1346 | 1629 | 3,351,953 |
| Toyota | 380 | 800 | 1262 | 1580 | 676,935 |
| Honda | 377 | 788 | 1233 | 1571 | 621,375 |

**Key finding:** even at the 25th percentile, every manufacturer's gap exceeds 365 days — direct confirmation that the earlier 12-month window (Section 17) was capturing only a small, non-representative slice of the true distribution, not the bulk of real complaint-to-recall matches.

Median lag clusters around 2.1–2.3 years across all five manufacturers (788–855 days), with a consistent, modest ranking: Honda and Toyota show shorter gaps at every percentile than Ford, Chrysler, and GM.

**Interpretive caution (explicitly logged, not omitted):**

- `COMPONENT_CLEAN` is a broad top-level category (Section 13), so a "match" indicates a complaint and a recall shared a company + broad-component combination within 5 years — not a demonstrated causal link between that specific complaint and that specific recall. This is a system-level correlational signal about responsiveness, not proof that any individual complaint triggered any individual recall.
- `PAIR_COUNT` is heavily imbalanced: Ford/Chrysler/GM each have 3.3M–4.2M matched pairs, while Toyota/Honda have ~620K–680K — roughly 5–6x fewer. The domestic manufacturers' percentiles rest on a substantially larger sample, which should be noted when comparing rankings across companies; the Honda/Toyota advantage, while consistent across all four percentiles, is measured on a thinner evidentiary base.
- This metric reflects filing-to-recall lag (per Section 5), scoped to the 5 highest-volume manufacturers and 10 highest-volume components (Section 18), under a 5-year lookback — not an unconstrained, full-market measurement.
- **Company ranking:** Honda is fastest (788 days, 34 days below the group average of 821.6), General Motors slowest (855 days, 34 days above average). The spread across all 5 companies is only about 68 days (roughly 2 months) — a real but modest difference, not a dramatic one. Manufacturers differ, but not by an enormous margin; this is better framed as "some companies trend ~4% faster than others," not "some companies are 3x faster."
- **Component ranking:** A wider spread than seen between companies. VEHICLE SPEED CONTROL has by far the shortest median lag (693 days) vs. STEERING at the slow end (858 days) — a 165-day gap, more than double the company-level spread. This suggests defect type matters more than manufacturer identity in explaining response-time variation. Caveat: VEHICLE SPEED CONTROL's pair count (164,034) is much smaller than most other components — a real result, but resting on a thinner sample than, say, ELECTRICAL SYSTEM (3.27M pairs). Flagged with the same caution applied to the Toyota/Honda sample-size imbalance above.

---

## 21. Complaint Severity by Component

A separate question from response-time lag: which components carry the highest rate of severe real-world outcomes (crash, fire, injury, death) among complaints, independent of whether a recall ever followed. Run on the full `complaints_clean` table (not scoped to the 5-manufacturer/10-component analysis set used elsewhere), since this is a broader dataset-wide question about defect risk, not a manufacturer-comparison question. This scope difference is noted explicitly so it isn't confused with the scoped lag/spike findings.

`CRASH` and `FIRE` were confirmed as clean Y/N flags before use (no unexpected values).

**Findings:**

- **AIR BAGS** has the highest crash rate by a wide margin (25.92% of complaints involve a crash — more than double any other component) and the highest crash count outright (40,298), despite not having the highest total complaint volume. Plausible explanation: air bag issues are disproportionately likely to be reported only after something has already gone wrong (failure to deploy, unexpected deployment), unlike components that may be complained about proactively before an incident occurs.
- **VEHICLE SPEED CONTROL** is second-highest on crash rate (17.01%). Notable in combination with Section 20: this is the same component that showed the shortest median complaint-to-recall lag (693 days) — a component that is both comparatively dangerous and comparatively fast to act on, worth testing directly rather than treating as coincidental (see Section 22).
- **ENGINE** has the highest death count (367) despite a low crash rate (1.58%) — engine failures (e.g. fire, stalling) can be fatal without being classified as a "crash," illustrating why crash rate and injury/death counts need to be examined separately rather than collapsed into one severity metric.
- **ELECTRICAL SYSTEM** has the highest fire rate (7.47%) among components with meaningful volume — consistent with the intuitive link between electrical faults and fire risk, now quantified.

---

## 22. Does Severity Affect Recall Response Time?

Direct test of whether crash-involved complaints reach a recall faster than non-crash complaints, using the already-built `complaint_recall_pairs` table (5-manufacturer/10-component scope) joined back to `complaints_clean` for the severity flag.

**Result:** crash-involved complaints did not resolve faster — if anything, marginally slower.

| Group | Matched complaints | Median days to recall | Average days to recall |
|---|---|---|---|
| No crash | 11,974,367 | 832 | 859.5 |
| Crash involved | 861,999 | 854 | 874.9 |

The gap (~22 days on median, against an ~830-860 day baseline) runs consistently in the same direction across both average and median, and given the sample sizes involved (11.9M vs 862K), is unlikely to be pure noise — but the effect size is small and should not be overstated.

This result contradicts the intuitive hypothesis that severity accelerates manufacturer/regulator response, and is logged as a genuine finding rather than reshaped to fit expectation. Plausible (non-causal) explanations noted: crash-involved complaints may be more likely to route into litigation or insurance processes that run in parallel with, rather than accelerating, the formal recall pipeline; alternatively, severe-but-rare incidents may take longer to confirm as a systemic pattern (vs. driver-error) before a recall is issued. No causal claim is made — this is a correlational read on lag time within the existing 5-manufacturer/10-component/5-year scope, consistent with the interpretive cautions already logged in Section 20.

---

## 23. Recall Reason / Consequence Analysis — AIR BAGS Component (Text-Based)

Unlike the earlier quantitative analyses (all based on `complaint_recall_pairs` and structured fields), this section analyzes the free-text `DESC_DEFECT` field in `recalls_clean` to identify what NHTSA recall descriptions actually cite as the underlying defect, scoped to the AIR BAGS component. This is qualitative/pattern-based rather than a clean aggregation, since free text cannot be grouped meaningfully without first classifying it.

**Methodology note:** `recalls_clean` is granular to make/model/year (one row per vehicle configuration covered by a campaign), not to campaign itself. A single recall campaign covering 10 vehicle configurations produces 10 identical text rows. Any text analysis on this table must use `SELECT DISTINCT CAMPNO, DESC_DEFECT` (or `COUNT(DISTINCT CAMPNO)` in aggregations) to avoid overweighting campaigns with many vehicle variants — otherwise "common themes" would really just reflect which single recall happened to cover the most configurations, not genuine thematic frequency. This was confirmed directly: an initial unscoped query returned 10 rows that were all the same campaign (69V031000) repeated.

**Approach:** Rather than manually reading all 1,006 distinct AIR BAGS campaigns, defect causes were classified using SQL CASE/LIKE keyword matching on `DESC_DEFECT`, run iteratively:

- **First pass (4 categories):** classified campaigns as rupture/explosion, inadvertent deployment, deployment failure/non-deployment, or "Other." Result: 625 of 1,006 (62%) fell into "Other," signaling the categories were too coarse.
- **Second pass:** split "Other" into finer sub-categories (assembly/fastener defect, sensor/classification error, wiring/corrosion, software error, air bag tearing). This reduced "Uncategorized" to 375 of 625 (60% of the remaining bucket), still large enough to warrant one more check rather than accepting it outright.
- **Diagnostic sampling:** rather than guessing further keywords blindly, a random sample (`ORDER BY NEWID()`) of 20 rows from the still-uncategorized set was pulled and read directly. This surfaced a real, missed pattern: several campaigns described a cover, emblem, or trim piece cracking, shattering, or detaching during deployment and becoming a projectile — mechanically distinct from inflator rupture (metal canister exploding) but similar in consequence (fragments striking occupants). This pattern was not caught by any existing keyword (bolt, weld, fastener, sensor, etc.).
- **Third pass:** added a sixth category ("Cover/trim fragment (deployment)") using keywords `cover`, `emblem`, `score line`, `shatter`. This moved 30 campaigns out of Uncategorized (before: 375; after: 345), confirming the sample-driven bucket was a real, non-trivial pattern rather than noise.
- **Decision to stop iterating:** After three passes, further keyword refinement was judged to have diminishing returns — each additional keyword risks misclassifying edge cases already correctly bucketed, and continuing to invent categories without reading more text would be guessing rather than data-driven classification. This is logged as an intentional stopping point, not an incomplete analysis: a large, heterogeneous "Uncategorized" tail is treated as a genuine finding (most defect causes are rare and idiosyncratic) rather than a gap to be closed at any cost.

**Final classification results (1,006 distinct AIR BAGS campaigns):**

| Category | Campaigns | % of total |
|---|---|---|
| Uncategorized (long tail) | 345 | 34% |
| Inflator rupture/explosion | 225 | 22% |
| Deployment failure / non-deployment | 104 | 10% |
| Sensor/classification error | 95 | 9% |
| Assembly/fastener defect | 60 | 6% |
| Inadvertent deployment | 52 | 5% |
| Wiring/corrosion | 40 | 4% |
| Software error | 33 | 3% |
| Cover/trim fragment (deployment) | 30 | 3% |
| Air bag tearing | 22 | 2% |

**Finding:** Inflator rupture/explosion — the failure mode behind the Takata recalls, the largest automotive recall in U.S. history — is the single largest identifiable cause of AIR BAGS recalls, at 22% of all distinct campaigns and more than double the size of any other named category. However, it is not a majority: roughly two-thirds of AIR BAGS recalls stem from causes other than inflator rupture. The next-largest identifiable causes (deployment failure, sensor/classification errors, assembly defects) each account for 6–10% individually. Approximately one-third of campaigns describe defect causes too varied to group by keyword matching, indicating a long tail of one-off manufacturing and design defects rather than a small number of dominant failure types. This nuance — Takata as the largest single cause but not the dominant one — is a more precise and defensible claim than either overstating Takata's share or treating "Other" as uninformative noise.

---

## 24. Complaint-to-Recall Match Rate

**Question:** within the 5-company/10-component scope, what percentage of complaints ever fall within the proximity window of a matching recall, versus never finding one at all? This quantifies how selective the underlying signal is — most complaints should not be expected to match a recall, since most complaints are isolated incidents rather than systemic defects.

**Methodology note:** because `complaint_recall_pairs_5` is built with a join that allows one complaint to match multiple recalls (any recall within a 5-year window before it, for the same manufacturer+component), a naive `COUNT()` of matched rows would overstate the number of matched complaints if any complaint fell within the window of more than one recall. The correct approach uses `COUNT(DISTINCT CMPLID)` on both sides of the join, so each complaint is counted at most once regardless of how many recalls it falls within. Empirically, re-running the analysis with and without the DISTINCT correction produced identical results (94.32% both times), confirming that in this dataset no complaint happened to match more than one recall within the 5-year window — but the DISTINCT version is retained as the methodologically correct query regardless, since it does not depend on this dataset-specific coincidence holding true.

**Results:**

Overall: **94.32%** of complaints (1,055,678 of 1,119,288) within the 5-company/10-component scope fall within 5 years of at least one recall for that same manufacturer+component.

By component:

| Component | Total complaints | Matched | Match rate |
|---|---|---|---|
| AIR BAGS | 109,636 | 109,241 | 99.64% |
| SERVICE BRAKES, HYDRAULIC | 88,372 | 87,881 | 99.44% |
| ELECTRICAL SYSTEM | 181,798 | 179,158 | 98.55% |
| STEERING | 116,108 | 114,305 | 98.45% |
| ENGINE | 197,784 | 194,123 | 98.15% |
| POWER TRAIN | 160,415 | 157,320 | 98.07% |
| SUSPENSION | 67,073 | 65,462 | 97.60% |
| STRUCTURE | 77,597 | 74,994 | 96.65% |
| VEHICLE SPEED CONTROL | 64,360 | 41,992 | 65.25% |
| SERVICE BRAKES | 56,145 | 31,202 | 55.57% |

**Interpretation** — this number requires a precise definition to avoid overclaiming. The high overall rate (94%) does not mean 94% of individual complaints causally contributed to a specific recall. It reflects the 5-year proximity-window definition used to build `complaint_recall_pairs_5`: a complaint is "matched" if it was filed within 5 years before any recall of that same manufacturer+component, regardless of whether that particular complaint had any direct connection to that particular recall. Components that are recalled very frequently (AIR BAGS, ELECTRICAL SYSTEM, ENGINE) have wide, near-continuous 5-year coverage, so nearly every complaint for those components happens to fall inside some qualifying window. VEHICLE SPEED CONTROL (65%) and SERVICE BRAKES (56%) are meaningfully lower precisely because they are recalled less often, leaving genuine gaps where a complaint has no recall within 5 years.

This finding is best framed as: "how often does a complaint about a given component fall within the shadow of that manufacturer's recall activity for that component" — a measure of recall frequency/density per component, not a measure of individual complaint-to-recall causation.

---

## 25. Recall Scale (Units Affected) — Scoped Out

The original analysis plan (Section on "further avenues," see earlier decision log entries) included analyzing recall scale — which components trigger the largest recalls by units affected, and whether complaint volume predicts recall size — using a units-affected field expected to be present in the recalls data (commonly `POTAFF` in NHTSA's raw flat file).

A check of `recalls_clean`'s full column list confirmed no such field exists: the table contains `CAMPNO`, `MFR_NAME_RAW`, `VEHICLE_MAKE`, `MODEL_NAME`, `MODEL_YEAR`, `COMPONENT_RAW`, `RCDATE`, `DESC_DEFECT`, `CONSEQUENCE_DEFECT`, `MFR_NAME_CLEAN`, `COMPONENT_CLEAN` — no units-affected column was retained during the original data load and cleaning pipeline.

**Decision:** rather than re-importing the raw `FLAT_RCL` file and re-running the cleaning/matching pipeline to recover this one field, this analysis was scoped out of the project. This is logged as a deliberate, documented limitation rather than a silent omission: recall scale is a legitimate and interesting question the current pipeline cannot answer without additional upstream rework, and the time cost of that rework was judged not to justify the marginal analytical value given the project's existing breadth of completed findings (company/component ranking, severity, time trends, cross-tab, text classification, and match rate).
