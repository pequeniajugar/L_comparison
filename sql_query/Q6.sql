WITH params AS (
    SELECT
        (SELECT value
         FROM benchmark_params
         WHERE name = 'start6Mo') AS start_date,

        (SELECT value
         FROM benchmark_params
         WHERE name = 'end6Mo') AS end_date
),

-- Price data in the 6*31-day period
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

-- Splits after start6Mo
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

-- Adjust close price using all future split factors
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

-- If no future split exists, keep the original close price
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

-- Calculate 21-row and 5-row moving averages
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
),

-- Obtain the previous m5 and m21 for each stock
signals AS (
    SELECT
        id,
        tradedate,
        closeprice,
        m21,
        m5,

        LAG(m21) OVER (
            PARTITION BY id
            ORDER BY tradedate
        ) AS prev_m21,

        LAG(m5) OVER (
            PARTITION BY id
            ORDER BY tradedate
        ) AS prev_m5

    FROM avginfo
)

SELECT
    id,
    tradedate AS crossdate,
    closeprice

FROM signals

WHERE
       (
           prev_m5 <= prev_m21
           AND m5 > m21
       )
    OR (
           prev_m5 >= prev_m21
           AND m5 < m21
       )

ORDER BY
    id,
    crossdate;
