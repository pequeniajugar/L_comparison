WITH params AS (
    SELECT
        (SELECT value
         FROM benchmark_params
         WHERE name = 'start6Mo') AS start_date,

        (SELECT value
         FROM benchmark_params
         WHERE name = 'end6Mo') AS end_date
),

pxdata AS (
    SELECT
        p.id,
        p.tradedate,
        p.closeprice
    FROM price AS p
    CROSS JOIN params AS x
    WHERE p.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock1000'
    )
      AND p.tradedate >= x.start_date
      AND p.tradedate < x.end_date
),

splitdata AS (
    SELECT
        s.id,
        s.splitdate,
        s.splitfactor
    FROM split AS s
    CROSS JOIN params AS x
    WHERE s.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock1000'
    )
      AND s.splitdate >= x.start_date
),

splitadj AS (
    SELECT
        p.id,
        p.tradedate,

        p.closeprice
        * EXP(SUM(LN(s.splitfactor))) AS adjusted_closeprice

    FROM pxdata AS p

    JOIN splitdata AS s
      ON p.id = s.id
     AND p.tradedate < s.splitdate

    GROUP BY
        p.id,
        p.tradedate,
        p.closeprice
),

adjusted AS (
    SELECT
        p.id,
        p.tradedate,

        COALESCE(
            s.adjusted_closeprice,
            p.closeprice
        ) AS closeprice

    FROM pxdata AS p

    LEFT JOIN splitadj AS s
      ON p.id = s.id
     AND p.tradedate = s.tradedate
),

avginfo AS (
    SELECT
        id,
        tradedate,
        closeprice,

        AVG(closeprice) OVER (
            PARTITION BY id
            ORDER BY tradedate
            ROWS BETWEEN 20 PRECEDING AND CURRENT ROW
        ) AS m21,

        AVG(closeprice) OVER (
            PARTITION BY id
            ORDER BY tradedate
            ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
        ) AS m5

    FROM adjusted
)

SELECT
    id,
    tradedate,
    closeprice,
    m21,
    m5
FROM avginfo
ORDER BY
    id,
    tradedate;