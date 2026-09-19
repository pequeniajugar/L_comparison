WITH params AS (
    SELECT
        (SELECT value
         FROM benchmark_params
         WHERE name = 'startPeriod') AS start_period
)

SELECT
    AVG(p.closeprice) AS avg_close_price

FROM price AS p
CROSS JOIN params AS x

WHERE p.id IN (
    SELECT id
    FROM benchmark_sets
    WHERE set_name = 'SP500'
)

AND p.tradedate = x.start_period;