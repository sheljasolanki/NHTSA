# NHTSA Complaint → Recall Lag Analysis

After owners start complaining to NHTSA about a vehicle component, how long until that vehicle is recalled for it? Which manufacturers and components lag, and what predicts a slow recall? The project runs the full pipeline: 2 GB of raw NHTSA flat files → Python cleaning → SQL Server analysis → statistics and charts.

**Findings: [Results/results.md](Results/results.md)**

## Headline findings
- **Half of all recalls had no prior owner complaint** about that vehicle and component (50.6% of 6,418 campaigns since 2005 did).
- When complaints came first, the **median lag from first complaint to recall is 766 days** (95% CI 711–831), and it hasn't improved in 20 years.
- **The component matters about 6× more than the manufacturer** in explaining lag. Air bags are the slowest (median 1,710 days); steering is the fastest (518).
- **Recalls NHTSA pushed for came 3× later** (1,772 vs 568 days) **after 8× more complaints** (51 vs 6), and covered 41% of recalled vehicles while making up only 14% of campaigns.
- **Monthly complaint spikes don't predict recalls** once compared with a baseline (lift 0.9×).
- Only **12% of complaints** see the same vehicle recalled for the same component within 5 years.

## How to run

| Step | What | Output |
|---|---|---|
| 1 | Put the three NHTSA flat files in `datasets/` (not committed, ~2 GB) | `FLAT_CMPL.txt`, `FLAT_RCL_PRE_2010.txt`, `FLAT_RCL_POST_2010.txt` |
| 2 | Run [notebook/01_data_cleaning.ipynb](notebook/01_data_cleaning.ipynb) (conda env `data_analysis`) | Database `NHTSA_v2` on `D:\SQLData` with tables `v2.complaints`, `v2.recalls`, `v2.recall_text`; cleaning audit in `Results/cleaning/` |
| 3 | `powershell -ExecutionPolicy Bypass -File sql\run_all.ps1` (about 2 minutes), or open each script in SSMS in order | Tables and views `v2.*`; each script's output in `Results/sql_output/` |
| 4 | Run [notebook/02_analysis.ipynb](notebook/02_analysis.ipynb) | Charts in `Results/charts/`, tables in `Results/tables/`, `Results/key_numbers.json` |

Settings (server, database, data folder) are at the top of each notebook and in the `v2.params` table.

## Folder layout

```
datasets/          raw NHTSA flat files (git-ignored)
notebook/
  01_data_cleaning.ipynb    raw files -> cleaned tables -> SQL Server
  02_analysis.ipynb         statistics, charts, key numbers
sql/
  01_setup.sql                         params, indexes, campaign table, scope
  02_complaint_recall_pairs.sql        complaint <-> recall matching, campaign lag, complaint outcomes
  03_severity.sql                      severity by component, de-duplicated, per 1,000 complaints
  04_lag_by_oem_and_component.sql      lag by manufacturer, component, cross-tab
  05_severity_vs_recall.sql            are severe complaints recalled more often / sooner?
  06_yearly_trend.sql                  volume and lag by year
  07_match_rate.sql                    complaint -> recall rate; recalls preceded by complaints
  08_spike_detection.sql               complaint spikes with a calendar spine and a baseline
  09_airbag_defect_classification.sql  air bag failure modes from defect text
  10_recall_origin.sql                 manufacturer-initiated vs NHTSA-influenced recalls
  run_all.ps1                          runs 01-10 in order
Results/
  results.md        findings
  charts/  tables/  sql_output/  cleaning/  key_numbers.json
```

## Key design decisions

| Challenge | Approach | Where |
|---|---|---|
| Matching complaints to the right recall | Match on manufacturer + component + **model + model year**, complaint before recall: 397K pairs, built in about 25 seconds. Matching on manufacturer + component alone would pair each complaint with many unrelated recalls | `sql/02` |
| Busy components dominating the lag statistics | Lag measured **once per recall campaign**: first complaint → recall, and 3rd complaint → recall | `sql/02`, `sql/04` |
| Choosing the lookback window | 10-year lookback, recalls from 2005 on (complaints start 1995), plus a sensitivity check at 1, 2 and 5 years | `sql/01`, notebook 02 §2 |
| One complaint appears on many rows (one per component line) | Each complaint (`ODINO`) counted once per component; deaths and injuries also reported per 1,000 complaints | notebook 01 §9, `sql/03` |
| Manufacturer names have thousands of spellings | Vehicle make → parent OEM lookup (`LEXUS` → Toyota, `JEEP` → Chrysler), with an audit file of what's excluded | notebook 01 §6 |
| Tires, child seats and equipment mixed into the files | Vehicle records only on both sides | notebook 01 §3 |
| Consistent column names across Python and SQL | Final names set once in the cleaning notebook; SQL uses them as-is | notebook 01 §10, §12 |
| Measuring how often complaints lead to recalls | Share of complaints followed by a recall of the **same vehicle** within 1, 2, 5 years, with right-censoring handled | `sql/07` |
| Spike detection without false signals | Zero-filled monthly calendar, every series included, lift vs normal months, recall-caused spikes separated | `sql/08` |
| Classifying air bag defects from free text | One keyword table, word-boundary matching, first match by priority | `sql/09` |
| Separating real differences from noise | Bootstrap CIs, Kruskal-Wallis, Mann-Whitney, chi-square, Fisher's exact | notebook 02 |
| Who started the recall | `INFLUENCED_BY` (manufacturer vs NHTSA-influenced) and units affected kept and analysed | `sql/10` |
| Parameters repeated across scripts | One `v2.params` table and `v2.scope_*` tables; full data analysed, scope used only for charts | `sql/01` |

## Tech stack
**Python** (pandas with Arrow strings, SciPy, matplotlib) · **SQL Server 2022** (window functions, `PERCENTILE_CONT`, recursive CTE calendar, views, clustered index design)
