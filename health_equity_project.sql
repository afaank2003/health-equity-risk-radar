CREATE DATABASE IF NOT EXISTS health_equity;
USE health_equity;
CREATE TABLE IF NOT EXISTS places_long (
  Year INT,
  state_abbr VARCHAR(2),
  state_name VARCHAR(64),
  county_name VARCHAR(128),
  fips5 CHAR(5),
  fips_int INT,
  Category VARCHAR(64),
  MeasureId VARCHAR(32),
  Measure VARCHAR(255),
  unit VARCHAR(32),
  value_type VARCHAR(64),
  value DECIMAL(6,2),
  ci_low DECIMAL(6,2),
  ci_high DECIMAL(6,2),
  TotalPopulation INT,
  TotalPop18plus INT,
  lon DECIMAL(10,6),
  lat DECIMAL(10,6),
  INDEX idx_fips_year (fips5, Year),
  INDEX idx_measure (MeasureId)
);

USE health_equity;

SELECT COUNT(*) AS rows_total FROM places_long;

SELECT Year, COUNT(*) AS row_count
FROM places_long
GROUP BY Year
ORDER BY Year;

SELECT COUNT(DISTINCT fips5) AS counties_2023
FROM places_long
WHERE Year = 2023;

SELECT fips5, state_abbr, county_name, MeasureId, value
FROM places_long
WHERE Year = 2023
LIMIT 10;

CREATE OR REPLACE VIEW vw_county_places_profile_2023 AS
SELECT
  fips5,
  state_abbr,
  county_name,
  MAX(TotalPopulation) AS total_population,
  MAX(lon) AS lon,
  MAX(lat) AS lat,

  MAX(CASE WHEN MeasureId = 'DIABETES' THEN value END)  AS diabetes_pct,
  MAX(CASE WHEN MeasureId = 'OBESITY'  THEN value END)  AS obesity_pct,
  MAX(CASE WHEN MeasureId = 'CSMOKING' THEN value END)  AS cig_smoking_pct,
  MAX(CASE WHEN MeasureId = 'LPA'      THEN value END)  AS no_leisure_pa_pct,
  MAX(CASE WHEN MeasureId = 'BPHIGH'   THEN value END)  AS bphigh_pct,
  MAX(CASE WHEN MeasureId = 'DEPRESSION' THEN value END) AS depression_pct,
  MAX(CASE WHEN MeasureId = 'MHLTH'    THEN value END)  AS frequent_mental_distress_pct,
  MAX(CASE WHEN MeasureId = 'COPD'     THEN value END)  AS copd_pct
FROM places_long
WHERE Year = 2023
GROUP BY fips5, state_abbr, county_name;

SELECT * FROM vw_county_places_profile_2023 LIMIT 10;

SELECT VERSION();

CREATE OR REPLACE VIEW vw_county_burden_rank_2023 AS
SELECT
  t.*,
  (t.pr_diabetes + t.pr_obesity + t.pr_smoking + t.pr_lpa +
   t.pr_bphigh + t.pr_depression + t.pr_mhlth + t.pr_copd) / 8.0 AS burden_rank
FROM (
  SELECT
    p.*,
    PERCENT_RANK() OVER (ORDER BY diabetes_pct)  AS pr_diabetes,
    PERCENT_RANK() OVER (ORDER BY obesity_pct)   AS pr_obesity,
    PERCENT_RANK() OVER (ORDER BY cig_smoking_pct) AS pr_smoking,
    PERCENT_RANK() OVER (ORDER BY no_leisure_pa_pct) AS pr_lpa,
    PERCENT_RANK() OVER (ORDER BY bphigh_pct)    AS pr_bphigh,
    PERCENT_RANK() OVER (ORDER BY depression_pct) AS pr_depression,
    PERCENT_RANK() OVER (ORDER BY frequent_mental_distress_pct) AS pr_mhlth,
    PERCENT_RANK() OVER (ORDER BY copd_pct)      AS pr_copd
  FROM vw_county_places_profile_2023 p
) t;

SELECT state_abbr, county_name, burden_rank
FROM vw_county_burden_rank_2023
ORDER BY burden_rank DESC
LIMIT 20;

CREATE OR REPLACE VIEW vw_positive_deviants_places_only AS
SELECT *
FROM (
  SELECT
    p.*,
    PERCENT_RANK() OVER (PARTITION BY state_abbr ORDER BY burden_rank) AS burden_rank_within_state
  FROM vw_county_burden_rank_2023 p
) x
WHERE burden_rank_within_state <= 0.10;

SELECT COUNT(*) AS rows_total FROM places_long;

SELECT COUNT(DISTINCT fips5) AS counties_2023
FROM places_long
WHERE Year = 2023;

CREATE TABLE IF NOT EXISTS svi_county (
  fips5 CHAR(5) PRIMARY KEY,
  rpl_themes DECIMAL(6,4),
  rpl_theme1 DECIMAL(6,4),
  rpl_theme2 DECIMAL(6,4),
  rpl_theme3 DECIMAL(6,4),
  rpl_theme4 DECIMAL(6,4),
  INDEX idx_rpl (rpl_themes)
);

SELECT COUNT(*) FROM svi_county;

SELECT * FROM svi_county LIMIT 10;

USE health_equity;

SELECT COUNT(*) AS svi_rows FROM svi_county;

SELECT MIN(fips5) AS min_fips, MAX(fips5) AS max_fips
FROM svi_county;

SELECT MIN(rpl_themes) AS min_rpl, MAX(rpl_themes) AS max_rpl
FROM svi_county;

CREATE OR REPLACE VIEW vw_equity_need_2023 AS
SELECT
  p.fips5,
  p.state_abbr,
  p.county_name,
  p.total_population,
  p.lon,
  p.lat,

  p.diabetes_pct,
  p.obesity_pct,
  p.cig_smoking_pct,
  p.no_leisure_pa_pct,
  p.bphigh_pct,
  p.depression_pct,
  p.frequent_mental_distress_pct,
  p.copd_pct,

  p.burden_rank,

  s.rpl_themes,
  s.rpl_theme1,
  s.rpl_theme2,
  s.rpl_theme3,
  s.rpl_theme4,

  0.6 * s.rpl_themes + 0.4 * p.burden_rank AS equity_need_score
FROM vw_county_burden_rank_2023 p
JOIN svi_county s
  ON s.fips5 = p.fips5;

SELECT COUNT(*) AS joined_rows
FROM vw_equity_need_2023;

SELECT COUNT(*) AS places_missing_svi
FROM vw_county_burden_rank_2023 p
LEFT JOIN svi_county s ON s.fips5 = p.fips5
WHERE s.fips5 IS NULL;

SELECT state_abbr, county_name, equity_need_score, rpl_themes, burden_rank, total_population
FROM vw_equity_need_2023
ORDER BY equity_need_score DESC
LIMIT 20;

CREATE OR REPLACE VIEW vw_equity_need_2023_labeled AS
SELECT
  e.*,
  CASE
    WHEN e.rpl_themes >= 0.75 AND e.burden_rank >= 0.75 THEN 'High vuln / High burden'
    WHEN e.rpl_themes >= 0.75 AND e.burden_rank <  0.75 THEN 'High vuln / Lower burden'
    WHEN e.rpl_themes <  0.75 AND e.burden_rank >= 0.75 THEN 'Lower vuln / High burden'
    ELSE 'Lower vuln / Lower burden'
  END AS quadrant
FROM vw_equity_need_2023 e;






