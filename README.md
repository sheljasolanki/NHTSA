# NHTSA Recall Lag Analysis

**How long does it take manufacturers to issue a recall after customer complaints spike on a specific vehicle component — and do some manufacturers or components consistently lag behind others?**

This project measures **time-to-action** (complaint filing → official recall), not negligence or fault — an important distinction kept explicit throughout the analysis.

---

## Data

- **Complaints:** [NHTSA FLAT_CMPL](https://static.nhtsa.gov/odi/ffdd/cmpl/FLAT_CMPL.zip) — every safety complaint filed since 1995
- **Recalls:** [NHTSA FLAT_RCL](https://static.nhtsa.gov/odi/ffdd/rcl/FLAT_RCL.zip) — every official recall campaign on record

Both are public, bulk-downloadable flat files from NHTSA, no API key required.

---

## Pipeline

1. **Python (pandas, RapidFuzz)** — cleaned dates, fuzzy-matched thousands of raw manufacturer name strings down to real passenger-vehicle OEMs, built a component crosswalk to reconcile inconsistent category taxonomies between the two datasets
2. **SQL Server** — loaded ~2M+ cleaned rows, indexed for join performance, built a custom join key (manufacturer + component + date window) since no shared row-level ID exists between complaints and recalls
3. **Analysis** — window functions (`PERCENTILE_CONT`, `RANK`, rolling averages), multi-stage joins, and SQL-based text classification to answer the core question and a set of follow-on ones (severity, timing trends, spike detection, match rate)

**Final analysis scope:** top 5 manufacturers by complaint volume (GM, Ford, Chrysler, Toyota, Honda) × top 10 components by complaint volume, over a 5-year complaint-to-recall lookback window. The scoping decision, and every other methodology choice, is documented in the decision log linked below.

---

## Repo Contents

| Folder / File | What's in it |
|---|---|
| [`SQL/`](SQL/) | All queries — cleaning, schema, joins, and each numbered analysis |
| [`Results/`](Results/) | Query outputs with screenshots and interpretation for every finding |
| [`notebook/`](notebook/) | Python cleaning and fuzzy-matching pipeline |
| [`decision_log.md`](decision_log.md) | Full reasoning behind every methodology decision made in the project — why NHTSA, why these date columns, why this scope, why this window, etc. |

---

## Key Findings (summary)

- **Company lag:** Honda fastest (788 days median), GM slowest (855 days) — a modest ~4% spread across manufacturers
- **Component lag:** VEHICLE SPEED CONTROL fastest (693 days), STEERING slowest (858 days) — a wider spread than seen between companies, suggesting defect type matters more than manufacturer identity
- **Severity vs. lag:** crash-involved complaints did **not** resolve faster — a small but consistent effect in the opposite direction of the intuitive hypothesis
- **Match rate:** 94.32% of complaints fall within 5 years of a matching recall for that manufacturer+component (component-level breakdown ranges from 55.57% to 99.64%)
- **AIR BAGS root cause:** inflator rupture/explosion (the Takata failure mode) is the single largest identifiable defect cause (22%) but not a majority — roughly two-thirds of AIR BAGS recalls stem from other causes

Full results, screenshots, and interpretation for all 9 analyses are in [`Results/`](Results/).

---

## Methodology Notes & Limitations

- Measures **filing-to-recall lag** (complaint received by NHTSA → official recall), not incident-to-recall lag or manufacturer negligence
- Scoped to top 5 manufacturers × top 10 components for computational tractability — not the full ~40-60 OEM × ~50 component universe
- 5-year lookback window chosen after a 12-month window was found to truncate the true lag distribution
- Recall scale (units affected / POTAFF) was scoped out — the field wasn't retained during initial data load; documented as a deliberate limitation, not an oversight
- Full reasoning for every methodology decision is logged in [`decision_log.md`](decision_log.md)

---

## Tech Stack

**Python** (pandas, RapidFuzz) · **SQL Server** (window functions, CTEs, dynamic views, index design) · **Power BI** (in progress)
