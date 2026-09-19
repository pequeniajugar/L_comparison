-- load_8_fast.sql
-- Bulk loader for the 10_8 financial benchmark into TimescaleDB.
--
-- This avoids the expensive "load into a plain table, then migrate_data"
-- path used by load.sql. For 10^8 scale data, create empty hypertables first,
-- copy data into them, and build secondary indexes after loading.
\set ON_ERROR_STOP on

SET synchronous_commit = off;
SET maintenance_work_mem = '2GB';
SET work_mem = '256MB';

CREATE EXTENSION IF NOT EXISTS timescaledb;

DROP TABLE IF EXISTS benchmark_sets;
DROP TABLE IF EXISTS benchmark_params;
DROP TABLE IF EXISTS dividend;
DROP TABLE IF EXISTS split;
DROP TABLE IF EXISTS price;
DROP TABLE IF EXISTS base;


-- ============================================================
-- Tables
-- ============================================================

CREATE TABLE base (
    id          text NOT NULL,
    ex          text,
    descr       text,
    sic         text,
    spr         text,
    cu          text,
    createdate  date NOT NULL
);

CREATE TABLE price (
    id          text NOT NULL,
    tradedate   date NOT NULL,
    highprice   double precision,
    lowprice    double precision,
    closeprice  double precision,
    openprice   double precision,
    volume      bigint
);

CREATE TABLE split (
    id          text NOT NULL,
    splitdate   date NOT NULL,
    entrydate   date,
    splitfactor double precision
);

CREATE TABLE dividend (
    id           text NOT NULL,
    xdivdate     date,
    divamt       double precision,
    announcedate date NOT NULL
);


-- ============================================================
-- Convert empty tables to hypertables before loading data
-- ============================================================

SELECT create_hypertable(
    'base',
    'createdate',
    chunk_time_interval => INTERVAL '10 years',
    if_not_exists => TRUE
);

SELECT create_hypertable(
    'price',
    'tradedate',
    chunk_time_interval => INTERVAL '30 days',
    if_not_exists => TRUE
);

SELECT create_hypertable(
    'split',
    'splitdate',
    chunk_time_interval => INTERVAL '10 years',
    if_not_exists => TRUE
);

SELECT create_hypertable(
    'dividend',
    'announcedate',
    chunk_time_interval => INTERVAL '30 days',
    if_not_exists => TRUE
);


-- ============================================================
-- Load CSV data
-- ============================================================

\copy base FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_8/base.csv' WITH (FORMAT csv, HEADER true);

\copy price FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_8/price.csv' WITH (FORMAT csv, HEADER true);

\copy split FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_8/split.csv' WITH (FORMAT csv, HEADER true);

\copy dividend FROM '/Users/tianxin/projects/nyu/ms2/independent_study/data/financial/10_8/dividend.csv' WITH (FORMAT csv, HEADER true);


-- ============================================================
-- Indexes
-- ============================================================

CREATE INDEX price_id_tradedate_idx
    ON price (id, tradedate);

CREATE INDEX split_id_splitdate_idx
    ON split (id, splitdate);

CREATE INDEX dividend_id_announcedate_idx
    ON dividend (id, announcedate);

CREATE INDEX base_id_createdate_idx
    ON base (id, createdate);


-- ============================================================
-- Benchmark sets
-- Mirrors load.q/load_10_7.q for the 10_8 data range.
-- stock10 uses numeric Security_N order, matching 10#base`Id.
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
ORDER BY substring(id from 'Security_([0-9]+)')::int;

INSERT INTO benchmark_sets (set_name, id)
SELECT 'SP500', id
FROM base
ORDER BY substring(id from 'Security_([0-9]+)')::int;

INSERT INTO benchmark_sets (set_name, id)
SELECT 'Russell2000', id
FROM base
ORDER BY substring(id from 'Security_([0-9]+)')::int;


-- ============================================================
-- Benchmark parameters
-- Mirrors src/test/financial/l_query/load.q for 10_8.
-- ============================================================

CREATE TABLE benchmark_params (
    name  text PRIMARY KEY,
    value date NOT NULL
);

INSERT INTO benchmark_params(name, value) VALUES
    ('startYear10',             DATE '3101-01-01'),
    ('endYear10',               DATE '3101-01-01' + 3650),
    ('startYear10Plus2',        DATE '3101-01-01' + 730),

    ('start300Days',            DATE '3110-01-01'),
    ('end300Days',              DATE '3110-01-01' + 300),

    ('startPeriod',             DATE '3111-01-01'),
    ('endPeriod',               DATE '3111-09-30'),

    ('start6Mo',                DATE '3111-01-01'),
    ('end6Mo',                  DATE '3111-01-01' + 186),

    ('maxTradeDateMinus3Years', DATE '3111-01-01');

INSERT INTO benchmark_params(name, value)
SELECT 'maxTradeDate', max(tradedate)
FROM price;

INSERT INTO benchmark_params(name, value)
SELECT 'maxTradeDateMinusYear', max(tradedate) - 365
FROM price;


-- ============================================================
-- Statistics and checks
-- ============================================================

ANALYZE base;
ANALYZE price;
ANALYZE split;
ANALYZE dividend;

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

SELECT
    hypertable_name,
    num_dimensions,
    num_chunks
FROM timescaledb_information.hypertables
ORDER BY hypertable_name;
