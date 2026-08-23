# NHTSA Recall Lag Analysis

## The Question
How long does it take manufacturers to issue a recall after customer complaints spike on a specific vehicle component, and do some manufacturers or components consistently lag behind others?

This measures **time-to-action** (filing → recall), not negligence or fault — an important distinction kept explicit throughout.

## Data Sources
- **Complaints:** [NHTSA FLAT_CMPL](https://www.nhtsa.gov/nhtsa-datasets-and-apis#complaints) — every safety complaint filed since 1995
- **Recalls:** [NHTSA FLAT_RCL](https://www.nhtsa.gov/nhtsa-datasets-and-apis#recalls) — every official recall campaign on record
- Public, bulk-downloadable, no API key required

## Pipeline
1. **Python (pandas, RapidFuzz):** date cleaning, fuzzy-matched thousands of raw manufacturer name strings down to ~40-60 real passenger-vehicle OEMs (`token_set_ratio`), scoped out non-OEM entities (tires, car seats, helmets, trailers) that share NHTSA's regulatory umbrella but aren't car manufacturers
2. **Component crosswalk:** collapsed 730/539 raw colon-delimited component strings (e.g. `AIR BAGS:FRONTAL:SENSOR`) into standardized top-level categories
3. **SQL Server:** ~2M+ rows loaded, indexed, joined on a custom key (manufacturer + component + date window, since no shared row-level ID exists between the two datasets)
4. **Analysis:** window functions (`PERCENTILE_CONT`, `RANK`, rolling averages), multi-stage joins, spike detection

**Final analysis scope:** top 5 manufacturers by complaint volume (GM, Ford, Chrysler, Toyota, Honda) × top 10 components by complaint volume, over a 5-year complaint-to-recall lookback window.

---

## Key Findings

### 0. Overall Lag Distribution (All Manufacturers, All Components)
<img width="747" height="603" alt="Screenshot 2026-08-18 213436" src="https://github.com/user-attachments/assets/95984b09-53ca-4a21-aed0-607091df5599" />

Unscoped baseline across the full 5-year `complaint_recall_pairs_5` table — not limited to the top 5 manufacturers / top 10 components used in the rest of this analysis. Included as a reference point: the scoped Company Lag findings (Section 1) sit close to this overall distribution, confirming the 5-company/10-component scope isn't skewing results in an unusual direction.


### 1. Company Lag — Who Responds Fastest?

| Manufacturer | P25 | P50 (median) | P75 | P90 | Pairs |
|---|---|---|---|---|---|
| Ford | 390 | 818 | 1302 | 1615 | 4,170,822 |
| Chrysler | 392 | 847 | 1325 | 1617 | 4,015,281 |
| GM | 407 | 855 | 1346 | 1629 | 3,351,953 |
| Toyota | 380 | 800 | 1262 | 1580 | 676,935 |
| Honda | 377 | 788 | 1233 | 1571 | 621,375 |

<img width="968" height="684" alt="Screenshot 2026-08-19 130646" src="https://github.com/user-attachments/assets/b8a65642-e33f-4cfa-b9c3-e2c36f57e8f5" />

<img width="899" height="792" alt="Screenshot 2026-08-19 175252" src="https://github.com/user-attachments/assets/cbb29886-0db3-470a-87f7-9fd6f2d0f770" />



Honda is fastest (788 days median), GM slowest (855 days) — a 68-day spread (~4%). Real, but modest: manufacturers differ, not dramatically. Note the sample-size imbalance — Ford/Chrysler/GM rest on 3.3-4.2M pairs vs. Toyota/Honda's ~620-680K, roughly 5-6x fewer.

### 2. Component Lag — Does Defect Type Matter More Than Manufacturer?

<img width="877" height="630" alt="Screenshot 2026-08-19 175434" src="https://github.com/user-attachments/assets/84d8276f-339b-4a4c-bbac-c099a49660ff" />


VEHICLE SPEED CONTROL has the shortest median lag (693 days); STEERING the longest (858 days) — a 165-day gap, more than double the spread seen between companies. **Defect type predicts response time better than manufacturer identity does.** Caveat: VEHICLE SPEED CONTROL's pair count (164,034) is much thinner than components like ELECTRICAL SYSTEM (3.27M pairs).

### 3. Company × Component Cross-Tab

<img width="720" height="830" alt="Screenshot 2026-08-19 232716" src="https://github.com/user-attachments/assets/c40b5bf8-00bb-403f-b64f-082417ded2cb" />

<img width="578" height="204" alt="image" src="https://github.com/user-attachments/assets/b70c0140-e314-422b-9503-6e846e095f99" />



Tests whether slow/fast response is a company-wide trait or specific to certain company+component combinations.

### 4. Complaint Severity by Component

<img width="1141" height="621" alt="Screenshot 2026-08-20 180626" src="https://github.com/user-attachments/assets/f87e037b-e28b-416b-82be-598012dc905e" />


- **AIR BAGS:** highest crash rate by far — 25.92% (40,298 crashes), despite not having the highest complaint volume
- **VEHICLE SPEED CONTROL:** 2nd-highest crash rate (17.01%) — also the fastest-responding component (see Finding 2)
- **ENGINE:** highest death count (367) despite a low crash rate (1.58%) — engine failures (fire, stalling) can be fatal without registering as a "crash"
- **ELECTRICAL SYSTEM:** highest fire rate (7.47%)

### 5. Does Severity Speed Up Response? (Counterintuitive)

| Group | Matched complaints | Median days | Avg days |
|---|---|---|---|
| No crash | 11,974,367 | 832 | 859.5 |
| Crash involved | 861,999 | 854 | 874.9 |

<img width="1134" height="605" alt="Screenshot 2026-08-19 194634" src="https://github.com/user-attachments/assets/d65b7457-092d-4167-b71a-b965262aeaa9" />

<img width="1273" height="453" alt="Screenshot 2026-08-19 194836" src="https://github.com/user-attachments/assets/e0a6622e-25e7-4c63-b554-b5ec6127b761" />


Crash-involved complaints did **not** resolve faster — if anything, marginally slower (~22 days on median). Consistent direction across average and median, with large sample sizes on both sides — unlikely to be pure noise, though the effect size is small. A plausible (non-causal) explanation: severe complaints may route into litigation/insurance processes in parallel with, rather than accelerating, the formal recall pipeline.

### 6. Has Response Time Changed Over the Years?

<img width="477" height="712" alt="Screenshot 2026-08-19 225752" src="https://github.com/user-attachments/assets/d6b50baa-1c8d-470f-af2c-7ed75ad77601" />

<img width="405" height="694" alt="Screenshot 2026-08-19 225929" src="https://github.com/user-attachments/assets/2fe732ad-e163-4b2a-9ba1-0fcd6e4d3559" />



Yearly trend, explicitly excluding 2022+ to avoid right-censoring bias — recent years haven't had enough time to accumulate their true lag distribution, which would otherwise make recent response times look artificially fast.

### 7. Complaint-to-Recall Match Rate

**94.32%** of complaints (1,055,678 / 1,119,288) fall within 5 years of a matching recall for the same manufacturer+component.

<img width="1184" height="597" alt="Screenshot 2026-08-20 181525" src="https://github.com/user-attachments/assets/3cc00845-182c-4c92-811a-9e449cc64561" />


**Important framing:** this measures how often a complaint falls within the "shadow" of a manufacturer's recall activity for that component within a 5-year window — not individual complaint-to-recall causation. Frequently-recalled components (AIR BAGS, ELECTRICAL SYSTEM) have near-continuous coverage, so almost every complaint lands inside some qualifying window.

### 8. Complaint Spike Detection

<img width="928" height="359" alt="image" src="https://github.com/user-attachments/assets/35e043d4-76af-409a-8c29-575f932da515" />


Built a rolling 6-month trailing average of complaint volume per manufacturer+component using SQL window functions, flagging months where volume was ≥2x the trailing average (with a minimum baseline to avoid flagging noise on small counts). Measured what % of recall campaigns were preceded by a detected spike in the 6 months prior.

### 9. AIR BAGS Root-Cause Classification (Text Analysis)



Classified 1,006 distinct AIR BAGS recall campaigns by defect cause using iterative SQL keyword matching, refined through 3 passes and random-sample validation of unclassified rows.

| Category | Campaigns | % |
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

Inflator rupture/explosion — the Takata failure mode, the largest automotive recall in U.S. history — is the single biggest identifiable cause (22%), but **not** a majority: roughly two-thirds of AIR BAGS recalls stem from other causes.

---

## Methodology Notes & Limitations
- Measures **filing-to-recall lag** (complaint received by NHTSA → official recall), not incident-to-recall lag or manufacturer negligence
- Scoped to top 5 manufacturers × top 10 components for computational tractability — not the full ~40-60 OEM × ~50 component universe
- 5-year lookback window chosen after a 12-month window was found to truncate the true lag distribution
- Recall scale (units affected / POTAFF) was scoped out — the field wasn't retained during initial data load; documented as a deliberate limitation, not an oversight
- Full reasoning for every methodology decision is logged in [`decision_log.md`](../decision_log.md
  )

## Tech Stack
**Python** (pandas, RapidFuzz) · **SQL Server** (window functions, CTEs, dynamic views, index design) · **Power BI** (in progress)



