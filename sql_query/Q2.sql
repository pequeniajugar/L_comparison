-- Q?.sql

WITH params AS (
    SELECT
        (SELECT value
         FROM benchmark_params
         WHERE name = 'startPeriod') AS start_period,

        (SELECT value
         FROM benchmark_params
         WHERE name = 'endPeriod') AS end_period
),

pxdata AS (
    SELECT
        p.id,
        p.tradedate,
        p.highprice,
        p.lowprice
    FROM price AS p
    CROSS JOIN params AS x
    WHERE p.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock1000'
    )
      AND p.tradedate BETWEEN x.start_period AND x.end_period
),

splitdata AS (
    SELECT
        s.id,
        s.splitdate AS tradedate,
        s.splitfactor
    FROM split AS s
    CROSS JOIN params AS x
    WHERE s.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock1000'
    )
      AND s.splitdate BETWEEN x.start_period AND x.end_period
)

SELECT
    p.id,
    p.tradedate,
    p.highprice - p.lowprice AS maxdiff
FROM pxdata AS p
JOIN splitdata AS s
  ON p.id = s.id
 AND p.tradedate = s.tradedate
ORDER BY
    p.id,
    p.tradedate;