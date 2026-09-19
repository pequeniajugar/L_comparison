-- Q0.sql
-- TimescaleDB implementation of financial benchmark Q0

WITH params AS (
    SELECT
        (SELECT value
         FROM benchmark_params
         WHERE name = 'startYear10') AS start_date,

        (SELECT value
         FROM benchmark_params
         WHERE name = 'endYear10') AS end_date
),

target AS (
    SELECT
        p.id,
        p.tradedate,
        p.closeprice
    FROM price AS p
    CROSS JOIN params AS x
    WHERE p.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock10'
    )
      AND p.tradedate >= x.start_date
      AND p.tradedate <= x.end_date
),

weekly AS (
    SELECT
        id,
        (
            1 + FLOOR(
                (
                    tradedate
                    - date_trunc(
                        'month',
                        date_trunc('month', tradedate)::date
                        - (
                            (EXTRACT(MONTH FROM tradedate)::int - 1)
                            * INTERVAL '30 days'
                        )
                    )::date
                )::numeric / 7
            )
        )::int AS bucket,

        'weekly'::text AS name,

        MIN(closeprice) AS low,
        MAX(closeprice) AS high,
        AVG(closeprice) AS mean

    FROM target

    GROUP BY
        id,
        bucket
),

monthly AS (
    SELECT
        id,
        (
            EXTRACT(MONTH FROM tradedate)::int
        )::int AS bucket,

        'monthly'::text AS name,

        MIN(closeprice) AS low,
        MAX(closeprice) AS high,
        AVG(closeprice) AS mean

    FROM target

    GROUP BY
        id,
        bucket
),

yearly AS (
    SELECT
        id,
        EXTRACT(YEAR FROM tradedate)::int AS bucket,

        'yearly'::text AS name,

        MIN(closeprice) AS low,
        MAX(closeprice) AS high,
        AVG(closeprice) AS mean

    FROM target

    GROUP BY
        id,
        bucket
)

SELECT
    id,
    bucket,
    name,
    low,
    high,
    mean
FROM weekly

UNION ALL

SELECT
    id,
    bucket,
    name,
    low,
    high,
    mean
FROM monthly

UNION ALL

SELECT
    id,
    bucket,
    name,
    low,
    high,
    mean
FROM yearly

ORDER BY
    id,
    name,
    bucket;
