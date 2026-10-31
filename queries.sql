-- =====================================================================
-- Rewarded-UA account review: SQL for Hex (dataframe SQL / DuckDB)
-- Tables: daily      = daily_performance.csv
--         targets    = roas_targets.csv
-- Each query is one Hex SQL cell. Read the comments: they explain
-- every new SQL idea the first time it appears.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Q0. Sanity check: what is in the data?
-- NEW: COUNT(*) counts rows; MIN/MAX find the first/last value;
--      COUNT(column) only counts rows where that column is NOT empty.
-- Why it matters: D7 metrics need 7 days to "mature". The newest
-- cohorts have no D7 data yet, so we must exclude them later.
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                         AS total_rows,
    MIN(date)                        AS first_day,
    MAX(date)                        AS last_day,
    COUNT(revenue_d7_eur)            AS rows_with_d7_data,
    MAX(CASE WHEN revenue_d7_eur IS NOT NULL THEN date END) AS last_mature_day
FROM daily;


-- ---------------------------------------------------------------------
-- Q1. Which accounts are load-bearing?
-- NEW: GROUP BY collapses rows into one row per advertiser.
--      SUM(...) OVER () is a "window function": it adds up the whole
--      column without collapsing rows, so we can compute each share.
-- ---------------------------------------------------------------------
SELECT
    advertiser,
    vertical,
    ROUND(SUM(spend_eur))                                        AS spend_eur,
    ROUND(100 * SUM(spend_eur) / SUM(SUM(spend_eur)) OVER (), 1) AS share_of_spend_pct
FROM daily
GROUP BY advertiser, vertical
ORDER BY spend_eur DESC;


-- ---------------------------------------------------------------------
-- Q2. Is each segment hitting the advertiser's ROAS target?
-- NEW: JOIN pulls the target from the second table by matching on
--      advertiser. WHERE ... IS NOT NULL keeps only mature cohorts.
--      CASE WHEN works like an IF statement.
-- D7 ROAS = revenue the users generated in their first 7 days / spend.
-- ---------------------------------------------------------------------
SELECT
    d.advertiser,
    d.geo,
    d.os,
    ROUND(SUM(d.spend_eur))                              AS spend_eur,
    ROUND(SUM(d.revenue_d7_eur) / SUM(d.spend_eur), 3)   AS d7_roas,
    t.roas_target_d7,
    ROUND(SUM(d.revenue_d7_eur) / SUM(d.spend_eur) / t.roas_target_d7 - 1, 3) AS vs_target,
    CASE
        WHEN SUM(d.revenue_d7_eur) / SUM(d.spend_eur) < 0.9 * t.roas_target_d7 THEN 'Below target'
        WHEN SUM(d.revenue_d7_eur) / SUM(d.spend_eur) > 1.2 * t.roas_target_d7 THEN 'Headroom'
        ELSE 'On target'
    END AS status
FROM daily AS d
JOIN targets AS t ON d.advertiser = t.advertiser
WHERE d.revenue_d7_eur IS NOT NULL
GROUP BY d.advertiser, d.geo, d.os, t.roas_target_d7
ORDER BY vs_target;


-- ---------------------------------------------------------------------
-- Q3. Where are caps under-filling, and is there room to bid up?
-- Cap fill = spend / daily cap. A low fill with ROAS ABOVE target means
-- we are leaving the advertiser's budget unspent for no reason.
-- NEW: HAVING filters AFTER grouping (WHERE filters before).
-- ---------------------------------------------------------------------
SELECT
    d.advertiser,
    d.geo,
    d.os,
    ROUND(AVG(d.spend_eur / d.daily_cap_eur), 3)          AS avg_cap_fill,
    ROUND(AVG(d.daily_cap_eur - d.spend_eur))             AS unfilled_eur_per_day,
    ROUND(SUM(d.revenue_d7_eur) / SUM(CASE WHEN d.revenue_d7_eur IS NOT NULL
                                           THEN d.spend_eur END), 3) AS d7_roas,
    t.roas_target_d7
FROM daily AS d
JOIN targets AS t ON d.advertiser = t.advertiser
GROUP BY d.advertiser, d.geo, d.os, t.roas_target_d7
HAVING AVG(d.spend_eur / d.daily_cap_eur) < 0.80
ORDER BY unfilled_eur_per_day DESC;


-- ---------------------------------------------------------------------
-- Q4. Early-warning check, account level: did any account move?
-- Compares the last 14 mature days with the 14 days before.
-- (14-day windows smooth out daily noise and weekend swings.)
-- NEW: WITH ... AS (...) creates a named temporary result (a "CTE")
--      so a long query reads top to bottom in steps.
-- ---------------------------------------------------------------------
WITH mature AS (
    SELECT * FROM daily WHERE revenue_d7_eur IS NOT NULL
),
bounds AS (
    SELECT MAX(date) AS last_day FROM mature
)
SELECT
    m.advertiser,
    ROUND(SUM(CASE WHEN m.date >  b.last_day - INTERVAL 14 DAY THEN m.revenue_d7_eur END)
        / SUM(CASE WHEN m.date <= b.last_day - INTERVAL 14 DAY THEN m.revenue_d7_eur END) - 1, 3) AS revenue_change,
    ROUND(SUM(CASE WHEN m.date >  b.last_day - INTERVAL 14 DAY THEN m.installs END) * 1.0
        / SUM(CASE WHEN m.date <= b.last_day - INTERVAL 14 DAY THEN m.installs END) - 1, 3)       AS installs_change
FROM mature AS m, bounds AS b
WHERE m.date > b.last_day - INTERVAL 28 DAY
GROUP BY m.advertiser
ORDER BY revenue_change;


-- ---------------------------------------------------------------------
-- Q5. Same check per segment: where exactly did it move?
-- ---------------------------------------------------------------------
WITH mature AS (
    SELECT * FROM daily WHERE revenue_d7_eur IS NOT NULL
),
bounds AS (
    SELECT MAX(date) AS last_day FROM mature
),
windows AS (
    SELECT
        m.advertiser, m.geo, m.os,
        CASE WHEN m.date > b.last_day - INTERVAL 14 DAY THEN 'recent' ELSE 'prior' END AS win,
        SUM(m.revenue_d7_eur) AS revenue,
        SUM(m.installs)       AS installs
    FROM mature AS m, bounds AS b
    WHERE m.date > b.last_day - INTERVAL 28 DAY
    GROUP BY 1, 2, 3, 4
)
SELECT
    advertiser, geo, os,
    ROUND(MAX(CASE WHEN win = 'prior' THEN revenue END))  AS rev_prior_14d,
    ROUND(MAX(CASE WHEN win = 'recent' THEN revenue END))  AS rev_recent_14d,
    ROUND(MAX(CASE WHEN win = 'recent' THEN revenue END)
        / MAX(CASE WHEN win = 'prior' THEN revenue END) - 1, 3)  AS revenue_change,
    ROUND(MAX(CASE WHEN win = 'recent' THEN installs END) * 1.0
        / MAX(CASE WHEN win = 'prior' THEN installs END) - 1, 3) AS installs_change
FROM windows
GROUP BY advertiser, geo, os
ORDER BY revenue_change
LIMIT 5;


-- ---------------------------------------------------------------------
-- Q6. Drill-down: what changed in the flagged segment?
-- One row per day for Emberfall Legends US iOS. If installs and
-- retention are steady but revenue per install falls, the users did not
-- get worse: something changed in monetisation or in measurement.
-- ---------------------------------------------------------------------
SELECT
    date,
    installs,
    ROUND(d1_retained_users * 1.0 / installs, 3)  AS d1_retention,
    ROUND(d7_retained_users * 1.0 / installs, 3)  AS d7_retention,
    ROUND(revenue_d7_eur / installs, 3)           AS d7_revenue_per_install,
    ROUND(revenue_d7_eur / spend_eur, 3)          AS d7_roas
FROM daily
WHERE advertiser = 'Emberfall Legends'
  AND geo = 'US' AND os = 'iOS'
  AND revenue_d7_eur IS NOT NULL
ORDER BY date;


-- ---------------------------------------------------------------------
-- Q7. Before vs after the change, in one table (for the write-up).
-- ---------------------------------------------------------------------
SELECT
    CASE WHEN date >= DATE '2026-09-08' THEN 'From 8 Sep' ELSE 'Before 8 Sep' END AS period,
    ROUND(AVG(installs))                                    AS installs_per_day,
    ROUND(SUM(d1_retained_users) * 1.0 / SUM(installs), 3)  AS d1_retention,
    ROUND(SUM(d7_retained_users) * 1.0 / SUM(installs), 3)  AS d7_retention,
    ROUND(SUM(revenue_d7_eur) / SUM(installs), 3)           AS d7_revenue_per_install,
    ROUND(SUM(revenue_d7_eur) / SUM(spend_eur), 3)          AS d7_roas
FROM daily
WHERE advertiser = 'Emberfall Legends' AND geo = 'US' AND os = 'iOS'
  AND revenue_d7_eur IS NOT NULL
GROUP BY period
ORDER BY period;


-- ---------------------------------------------------------------------
-- Q8. What does Almedia actually keep? Margin per segment.
-- The advertiser pays Almedia (spend_eur); Almedia pays its users rewards
-- (reward_cost_eur). The difference is Almedia's gross margin.
-- A segment can look big on spend but earn little for Almedia.
-- ---------------------------------------------------------------------
SELECT
    advertiser,
    geo,
    os,
    ROUND(SUM(spend_eur))                                              AS spend_eur,
    ROUND(SUM(spend_eur - reward_cost_eur))                            AS gross_margin_eur,
    ROUND(1 - SUM(reward_cost_eur) / SUM(spend_eur), 3)                AS margin_pct,
    ROUND(100 * SUM(spend_eur - reward_cost_eur)
              / SUM(SUM(spend_eur - reward_cost_eur)) OVER (), 1)      AS share_of_margin_pct
FROM daily
GROUP BY advertiser, geo, os
ORDER BY gross_margin_eur DESC;


-- ---------------------------------------------------------------------
-- Q9. What is each recommendation worth per month?
-- Uses the last 28 days as the current run rate. Every assumption sits in
-- one place (the "assumptions" step) so you can change it and rerun.
-- NEW: UNION ALL stacks the results of several SELECTs into one table.
-- ---------------------------------------------------------------------
WITH assumptions AS (
    SELECT
        0.90 AS tidepool_target_fill,   -- fill Tidepool DE to 90% of its cap
        0.40 AS coinmoth_fr_cut,        -- cut Coinmoth FR volume by 40% to move ROAS toward target
        30   AS days_per_month
),
run_rate AS (
    SELECT
        advertiser, geo, os,
        AVG(spend_eur)                                   AS spend_per_day,
        AVG(daily_cap_eur)                               AS cap_per_day,
        AVG(spend_eur / daily_cap_eur)                   AS cap_fill,
        1 - SUM(reward_cost_eur) / SUM(spend_eur)        AS margin_pct
    FROM daily
    WHERE date > (SELECT MAX(date) FROM daily) - INTERVAL 28 DAY
    GROUP BY advertiser, geo, os
)
-- 1) Opportunity: fill Tidepool DE Android's cap
SELECT
    'Fill Tidepool DE Android cap' AS action,
    'Upside'                       AS type,
    ROUND((a.tidepool_target_fill - r.cap_fill) * r.cap_per_day * a.days_per_month)              AS spend_eur_per_month,
    ROUND((a.tidepool_target_fill - r.cap_fill) * r.cap_per_day * a.days_per_month * r.margin_pct) AS margin_eur_per_month
FROM run_rate AS r, assumptions AS a
WHERE r.advertiser = 'Tidepool Puzzle' AND r.geo = 'DE' AND r.os = 'Android'

UNION ALL
-- 2) Risk: Emberfall pulls US iOS budget if measured ROAS stays below target
SELECT
    'Resolve Emberfall US iOS drop', 'At risk',
    ROUND(r.spend_per_day * a.days_per_month),
    ROUND(r.spend_per_day * a.days_per_month * r.margin_pct)
FROM run_rate AS r, assumptions AS a
WHERE r.advertiser = 'Emberfall Legends' AND r.geo = 'US' AND r.os = 'iOS'

UNION ALL
-- 3) Cost: cutting Coinmoth FR iOS volume (short-term revenue Almedia gives up)
SELECT
    'Cut Coinmoth FR iOS volume', 'Cost',
    ROUND(-a.coinmoth_fr_cut * r.spend_per_day * a.days_per_month),
    ROUND(-a.coinmoth_fr_cut * r.spend_per_day * a.days_per_month * r.margin_pct)
FROM run_rate AS r, assumptions AS a
WHERE r.advertiser = 'Coinmoth' AND r.geo = 'FR' AND r.os = 'iOS'

UNION ALL
-- 4) What that cut protects: the whole Coinmoth account
SELECT
    'Coinmoth account protected by the cut', 'At risk',
    ROUND(SUM(r.spend_per_day) * MAX(a.days_per_month)),
    ROUND(SUM(r.spend_per_day * r.margin_pct) * MAX(a.days_per_month))
FROM run_rate AS r, assumptions AS a
WHERE r.advertiser = 'Coinmoth';
