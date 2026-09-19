WITH params AS (
    SELECT
        (
            SELECT value
            FROM benchmark_params
            WHERE name = 'maxTradeDateMinus3Years'
        ) AS start_date
),

split_ids AS (
    SELECT DISTINCT
        s.id
    FROM split AS s
    CROSS JOIN params AS p
    WHERE s.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'Russell2000'
    )
      AND EXTRACT(YEAR FROM s.splitdate)
          >= EXTRACT(YEAR FROM p.start_date)
),

nosplit_avgpx AS (
    SELECT
        p.id,
        EXTRACT(YEAR FROM p.tradedate)::int AS year,
        AVG(p.closeprice)::double precision AS avg_px
    FROM price AS p
    CROSS JOIN params AS x
    WHERE p.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'Russell2000'
    )
      AND p.tradedate >= x.start_date
      AND p.id NOT IN (
          SELECT id
          FROM split_ids
      )
    GROUP BY
        p.id,
        EXTRACT(YEAR FROM p.tradedate)
),

divdata AS (
    SELECT
        d.id,
        EXTRACT(YEAR FROM d.announcedate)::int AS year,
        SUM(d.divamt)::double precision AS total_divs
    FROM dividend AS d
    CROSS JOIN params AS x
    WHERE d.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'Russell2000'
    )
      AND EXTRACT(YEAR FROM d.announcedate)
          >= EXTRACT(YEAR FROM x.start_date)
      AND d.id NOT IN (
          SELECT id
          FROM split_ids
      )
    GROUP BY
        d.id,
        EXTRACT(YEAR FROM d.announcedate)
)

SELECT
    p.id,
    p.year,
    p.avg_px,
    d.total_divs,
    d.total_divs / p.avg_px AS yield
FROM nosplit_avgpx AS p
JOIN divdata AS d
  ON p.id = d.id
 AND p.year = d.year
ORDER BY
    p.id,
    p.year;