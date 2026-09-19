WITH params AS (
    SELECT
        (SELECT value
         FROM benchmark_params
         WHERE name = 'start300Days') AS start_date,

        (SELECT value
         FROM benchmark_params
         WHERE name = 'end300Days') AS end_date
),

pxdata AS (
    SELECT
        p.id,
        p.tradedate,
        p.highprice,
        p.lowprice,
        p.closeprice,
        p.openprice,
        p.volume
    FROM price AS p
    CROSS JOIN params AS x
    WHERE p.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock1000'
    )
      AND p.tradedate >= x.start_date
      AND p.tradedate <= x.end_date
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

adjdata AS (
    SELECT
        p.id,
        p.tradedate,
        EXP(SUM(LN(s.splitfactor))) AS adjfactor
    FROM pxdata AS p
    JOIN splitdata AS s
      ON p.id = s.id
     AND p.tradedate < s.splitdate
    GROUP BY
        p.id,
        p.tradedate
)

SELECT
    p.id,
    p.tradedate,

    p.highprice  * COALESCE(a.adjfactor, 1.0) AS highprice,
    p.lowprice   * COALESCE(a.adjfactor, 1.0) AS lowprice,
    p.closeprice * COALESCE(a.adjfactor, 1.0) AS closeprice,
    p.openprice  * COALESCE(a.adjfactor, 1.0) AS openprice,

    p.volume / COALESCE(a.adjfactor, 1.0) AS volume

FROM pxdata AS p
LEFT JOIN adjdata AS a
  ON p.id = a.id
 AND p.tradedate = a.tradedate

ORDER BY
    p.id,
    p.tradedate;