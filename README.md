# Community-Health-Risk-Radar
County-level public health analytics project that integrates **CDC PLACES (2025 release; 2023 age-adjusted estimates)** with **CDC/ATSDR Social Vulnerability Index (SVI)** to rank U.S. counties by a transparent composite **Equity Need Score** (higher = higher need). The goal is to identify communities with a combination of high chronic disease burden and high social vulnerability for prioritization and targeting.

## What this does
- Loads PLACES county-level health estimates (long format) and SVI county-level vulnerability ranks into **MySQL**
- Builds a reusable SQL metrics layer (views) that:
  - pivots PLACES measures into a county profile
  - computes a composite **Burden Rank** using **PERCENT_RANK()** window functions across selected measures
  - joins SVI and computes a final **Equity Need Score**
- Produces ranked outputs (e.g., top 20 highest-need counties) for reporting or BI tools

## Data sources
- **CDC PLACES: Local Data for Better Health (County Data, 2025 release)**  
  Used: 2023 **age-adjusted prevalence** estimates for selected measures.
- **CDC/ATSDR Social Vulnerability Index (SVI), county level**  
  Used: overall vulnerability rank (**RPL_THEMES**) and theme ranks (**RPL_THEME1–4**).

> Note: PLACES values are modeled small-area estimates (not raw counts). SVI values are relative rankings (0–1) within the chosen reference set.

## Measures included (PLACES)
This repo uses 8 county-level measures to build the Burden Rank:
- DIABETES
- OBESITY
- CSMOKING (cigarette smoking)
- LPA (no leisure-time physical activity)
- BPHIGH (high blood pressure)
- DEPRESSION
- MHLTH (frequent mental distress)
- COPD

## Scoring methodology
### 1) Burden Rank
For each county, compute percent-rank scores across the selected PLACES measures using window functions:

- `pr_measure = PERCENT_RANK() OVER (ORDER BY measure_value)`
- `burden_rank = average(pr_measure_1 ... pr_measure_8)`

This yields a burden score in approximately `[0, 1]` (higher = worse relative burden).

### 2) Equity Need Score
Combine vulnerability and burden:

- `equity_need_score = 0.6 * rpl_themes + 0.4 * burden_rank`

Weights are chosen for transparency and interpretability (SVI emphasized slightly more); they can be tuned if needed.
