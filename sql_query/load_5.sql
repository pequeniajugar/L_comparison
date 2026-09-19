-- load_5.sql
-- One-time loader for the 10_5 financial benchmark into TimescaleDB.
\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS timescaledb;

DROP TABLE IF EXISTS benchmark_sets;
DROP TABLE IF EXISTS benchmark_params;
DROP TABLE IF EXISTS dividend;
DROP TABLE IF EXISTS split;
DROP TABLE IF EXISTS price;
DROP TABLE IF EXISTS base;


-- ============================================================
-- 1. Base
-- Time dimension: createdate
-- ============================================================

CREATE TABLE base (
    id          text NOT NULL,
    ex          text,
    descr       text,
    sic         text,
    spr         text,
    cu          text,
    createdate  date NOT NULL,

    PRIMARY KEY (id, createdate)
);


-- ============================================================
-- 2. Price
-- Time dimension: tradedate
-- ============================================================

CREATE TABLE price (
    id          text NOT NULL,
    tradedate   date NOT NULL,
    highprice   double precision,
    lowprice    double precision,
    closeprice  double precision,
    openprice   double precision,
    volume      bigint
);


-- ============================================================
-- 3. Split
-- Time dimension: splitdate
-- ============================================================

CREATE TABLE split (
    id          text NOT NULL,
    splitdate   date NOT NULL,
    entrydate   date,
    splitfactor double precision
);


-- ============================================================
-- 4. Dividend
-- Time dimension: announcedate
-- ============================================================

CREATE TABLE dividend (
    id           text NOT NULL,
    xdivdate     date,
    divamt       double precision,
    announcedate date NOT NULL
);


-- ============================================================
-- Load CSV data
-- ============================================================

\copy base FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_5/base.csv' WITH (FORMAT csv, HEADER true);

\copy price FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_5/price.csv' WITH (FORMAT csv, HEADER true);

\copy split FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_5/split.csv' WITH (FORMAT csv, HEADER true);

\copy dividend FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_5/dividend.csv' WITH (FORMAT csv, HEADER true);


-- ============================================================
-- Convert ALL four financial tables into hypertables
-- ============================================================

SELECT create_hypertable(
    'base',
    'createdate',
    migrate_data => TRUE,
    if_not_exists => TRUE
);

SELECT create_hypertable(
    'price',
    'tradedate',
    migrate_data => TRUE,
    if_not_exists => TRUE
);

SELECT create_hypertable(
    'split',
    'splitdate',
    migrate_data => TRUE,
    if_not_exists => TRUE
);

SELECT create_hypertable(
    'dividend',
    'announcedate',
    migrate_data => TRUE,
    if_not_exists => TRUE
);


-- ============================================================
-- Indexes
-- ============================================================

CREATE INDEX IF NOT EXISTS base_id_createdate_idx
    ON base (id, createdate);

CREATE INDEX IF NOT EXISTS price_id_tradedate_idx
    ON price (id, tradedate);

CREATE INDEX IF NOT EXISTS split_id_splitdate_idx
    ON split (id, splitdate);

CREATE INDEX IF NOT EXISTS dividend_id_announcedate_idx
    ON dividend (id, announcedate);


-- ============================================================
-- Benchmark sets
-- Mirrors load_10_5.q:
--   stock10:10#base`Id
--   stock1000:base`Id
--   SP500:base`Id
--   Russell2000:base`Id
-- ============================================================

CREATE TABLE benchmark_sets (
    set_name text NOT NULL,
    id       text NOT NULL,
    PRIMARY KEY (set_name, id)
);

INSERT INTO benchmark_sets (set_name, id)
SELECT 'stock10', id
FROM base
ORDER BY substring(id from 'Security_([0-9]+)')::int
LIMIT 10;

INSERT INTO benchmark_sets (set_name, id)
SELECT 'stock1000', id
FROM base
ORDER BY id;

INSERT INTO benchmark_sets (set_name, id)
SELECT 'SP500', id
FROM base
ORDER BY id;

INSERT INTO benchmark_sets (set_name, id)
SELECT 'Russell2000', id
FROM base
ORDER BY id;


-- ============================================================
-- Benchmark parameters
-- Mirrors src/test/financial/l_query/load_10_5.q.
-- q date offsets are converted to explicit PostgreSQL dates.
-- ============================================================

CREATE TABLE benchmark_params (
    name  text PRIMARY KEY,
    value date NOT NULL
);

INSERT INTO benchmark_params(name, value) VALUES
    ('startYear10',             DATE '2016-08-01'),
    ('endYear10',               DATE '2016-08-01' + 3650),
    ('startYear10Plus2',        DATE '2016-08-01' + 730),

    ('start300Days',            DATE '2016-08-01'),
    ('end300Days',              DATE '2016-08-01' + 300),

    ('startPeriod',             DATE '2016-08-01'),
    ('endPeriod',               DATE '2017-09-04'),

    ('start6Mo',                DATE '2016-08-01'),
    ('end6Mo',                  DATE '2016-08-01' + 186),

    ('maxTradeDateMinus3Years', DATE '2017-01-01');


INSERT INTO benchmark_params(name, value)
SELECT
    'maxTradeDate',
    max(tradedate)
FROM price;


INSERT INTO benchmark_params(name, value)
SELECT
    'maxTradeDateMinusYear',
    max(tradedate) - 365
FROM price;


-- ============================================================
-- Statistics
-- ============================================================

ANALYZE base;
ANALYZE price;
ANALYZE split;
ANALYZE dividend;


-- ============================================================
-- Check loaded row counts
-- ============================================================

SELECT 'base' AS table_name, count(*) AS rows
FROM base

UNION ALL

SELECT 'price', count(*)
FROM price

UNION ALL

SELECT 'split', count(*)
FROM split

UNION ALL

SELECT 'dividend', count(*)
FROM dividend

ORDER BY table_name;


-- ============================================================
-- Check hypertables
-- ============================================================

SELECT
    hypertable_name,
    num_dimensions,
    num_chunks
FROM timescaledb_information.hypertables
ORDER BY hypertable_name;
