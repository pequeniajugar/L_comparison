WITH
-- ============================================================
-- 1. Last-year price data for stock10
-- ============================================================
price_max AS (
    SELECT MAX(tradedate) AS max_date
    FROM price
),

pxdata AS (
    SELECT
        p.id,
        p.tradedate,
        p.closeprice
    FROM price AS p
    CROSS JOIN price_max AS m
    WHERE p.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock10'
    )
      AND p.tradedate >= m.max_date - 365
),

-- ============================================================
-- 2. Last-year split data for stock10
-- Note: the original q query uses max(SplitDate) - 365
-- ============================================================
split_max AS (
    SELECT MAX(splitdate) AS max_date
    FROM split
),

splitdata AS (
    SELECT
        s.id,
        s.splitdate,
        s.splitfactor
    FROM split AS s
    CROSS JOIN split_max AS m
    WHERE s.id IN (
        SELECT id
        FROM benchmark_sets
        WHERE set_name = 'stock10'
    )
      AND s.splitdate >= m.max_date - 365
),

-- ============================================================
-- 3. Split-adjust each historical close price
--
-- q logic:
--   TradeDate < SplitDate
--   ClosePrice * prd SplitFactor
-- ============================================================
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

-- If there is no later split, keep original ClosePrice
adjpxdata AS (
    SELECT
        p.id,
        p.tradedate,
        COALESCE(
            a.adjusted_closeprice,
            p.closeprice
        ) AS closeprice
    FROM pxdata AS p
    LEFT JOIN splitadj AS a
      ON p.id = a.id
     AND p.tradedate = a.tradedate
),

-- ============================================================
-- 4. Calculate moving averages
--
-- q:
--   21 mavg ClosePrice
--   160 mavg ClosePrice
-- ============================================================
moving_avgs AS (
    SELECT
        id,
        tradedate,
        closeprice,

        AVG(closeprice) OVER (
            PARTITION BY id
            ORDER BY tradedate
            ROWS BETWEEN 20 PRECEDING AND CURRENT ROW
        ) AS m21day,

        AVG(closeprice) OVER (
            PARTITION BY id
            ORDER BY tradedate
            ROWS BETWEEN 159 PRECEDING AND CURRENT ROW
        ) AS m5month

    FROM adjpxdata
),

-- ============================================================
-- 5. Get previous moving averages
-- ============================================================
with_prev AS (
    SELECT
        id,
        tradedate,
        closeprice,
        m21day,
        m5month,

        LAG(m21day) OVER (
            PARTITION BY id
            ORDER BY tradedate
        ) AS prev_m21day,

        LAG(m5month) OVER (
            PARTITION BY id
            ORDER BY tradedate
        ) AS prev_m5month

    FROM moving_avgs
),

-- ============================================================
-- 6. Keep only crossover events
--
-- Original q:
--
-- prev(m5month) <= prev(m21day)
-- AND m5month > m21day
--
-- OR
--
-- prev(m5month) >= prev(m21day)
-- AND m5month < m21day
-- ============================================================
crossovers AS (
    SELECT
        id,
        tradedate,
        closeprice,
        m21day,
        m5month,

        -- executeStrategy uses:
        -- buySignal = mavgday > mavgmonth
        (m21day > m5month) AS buy_signal

    FROM with_prev

    WHERE
        (
            prev_m5month <= prev_m21day
            AND m5month > m21day
        )
        OR
        (
            prev_m5month >= prev_m21day
            AND m5month < m21day
        )
),

-- ============================================================
-- 7. Mark whether a buy has already occurred
--
-- This reproduces:
--   maxs buySignal
-- ============================================================
strategy_events AS (
    SELECT
        *,

        BOOL_OR(buy_signal) OVER (
            PARTITION BY id
            ORDER BY tradedate
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS has_bought

    FROM crossovers
),

-- ============================================================
-- 8. Execute strategy
--
-- q executeStrategy:
--
-- before first buy:
--     factor = 1
--
-- buy:
--     factor = 1 / price
--
-- sell:
--     factor = price
--
-- result =
--     10000 * product(all factors)
-- ============================================================
strategy_factors AS (
    SELECT
        id,
        tradedate,
        closeprice,
        m21day,
        m5month,
        buy_signal,

        CASE
            WHEN NOT has_bought THEN 1.0

            WHEN buy_signal
                THEN 1.0 / closeprice

            ELSE closeprice
        END AS trade_factor

    FROM strategy_events
),

-- ============================================================
-- 9. Simulated result per stock
--
-- PostgreSQL has no built-in PRODUCT aggregate,
-- therefore:
--
-- product(x) = exp(sum(ln(x)))
-- ============================================================
simulation_result AS (
    SELECT
        id,

        10000.0
        * EXP(
            SUM(LN(trade_factor))
        ) AS result

    FROM strategy_factors

    GROUP BY id
),

-- Determine whether the strategy is still invested
last_signal AS (
    SELECT DISTINCT ON (id)
        id,
        (m21day > m5month) AS still_invested

    FROM crossovers

    ORDER BY
        id,
        tradedate DESC
),

simulated AS (
    SELECT
        r.id,
        r.result,
        l.still_invested

    FROM simulation_result AS r

    JOIN last_signal AS l
      ON r.id = l.id
),

-- ============================================================
-- 10. Latest adjusted prices
--
-- Original q uses rows whose TradeDate equals the GLOBAL
-- maximum TradeDate of adjpxdata.
-- ============================================================
latest_date AS (
    SELECT MAX(tradedate) AS max_date
    FROM adjpxdata
),

latest_pxs AS (
    SELECT
        a.id,
        a.tradedate,
        a.closeprice

    FROM adjpxdata AS a
    CROSS JOIN latest_date AS m

    WHERE a.tradedate = m.max_date
),

-- ============================================================
-- 11. Full outer join latest prices with simulation
-- ============================================================
portfolio AS (
    SELECT
        COALESCE(p.id, s.id) AS id,
        p.closeprice,
        s.result,
        s.still_invested

    FROM latest_pxs AS p

    FULL OUTER JOIN simulated AS s
      ON p.id = s.id
)

-- ============================================================
-- 12. Total stock portfolio value
--
-- q:
--
-- fill 10000;
-- result *
--   if stillInvested
--      then ClosePrice
--      else 1
-- ============================================================
SELECT
    SUM(
        COALESCE(
            result
            *
            CASE
                WHEN still_invested
                    THEN closeprice
                ELSE 1.0
            END,
            10000.0
        )
    ) AS stock_value

FROM portfolio;
