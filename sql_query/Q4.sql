SELECT
    AVG(p.closeprice) AS avg_close_price
FROM price AS p
WHERE p.id IN (
    SELECT id
    FROM benchmark_sets
    WHERE set_name = 'Russell2000'
)
AND p.tradedate = (
    SELECT value
    FROM benchmark_params
    WHERE name = 'startPeriod'
);