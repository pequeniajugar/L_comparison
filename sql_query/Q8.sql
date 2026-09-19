WITH params AS (
    SELECT
        (SELECT value
         FROM benchmark_params
         WHERE name = 'startPeriod') AS start_period
),

stocks AS (
    SELECT
        p.id,
        p.tradedate,
        p.closeprice,

        ROW_NUMBER() OVER (
            PARTITION BY p.id
            ORDER BY p.tradedate
        ) AS rn

    FROM price AS p
    CROSS JOIN params AS x

    WHERE p.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock10'
    )

      AND p.tradedate >= x.start_period
      AND p.tradedate <= x.start_period + 3
),

pairs AS (
    SELECT
        s1.id AS id1,
        s2.id AS id2,
        s1.closeprice AS closeprice1,
        s2.closeprice AS closeprice2

    FROM stocks AS s1

    JOIN stocks AS s2
      ON s1.rn = s2.rn

    WHERE s1.id <> s2.id
),

corr_stats AS (
    SELECT
        id1,
        id2,
        AVG(closeprice1) AS avg1,
        AVG(closeprice2) AS avg2,
        AVG(closeprice1 * closeprice2) AS avg12,
        AVG(closeprice1 * closeprice1) AS avg11,
        AVG(closeprice2 * closeprice2) AS avg22

    FROM pairs

    GROUP BY
        id1,
        id2
),

corr_table AS (
    SELECT
        id1,
        id2,
        CASE
            WHEN (avg11 - avg1 * avg1) <= 0
              OR (avg22 - avg2 * avg2) <= 0
            THEN NULL
            ELSE
                (avg12 - avg1 * avg2)
                /
                (
                    SQRT(avg11 - avg1 * avg1)
                    * SQRT(avg22 - avg2 * avg2)
                )
        END AS corrcoeff

    FROM corr_stats
)

SELECT
    id1,
    id2,
    corrcoeff

FROM corr_table

ORDER BY
    corrcoeff ASC;
