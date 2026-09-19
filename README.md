## q schema

The L & kdb benchmark loads the financial data directly from q binary table files into in-memory q/L tables.  The loader then assigns the benchmark column names with `xcol`.

| Table | Column | q/L type | Notes |
|---|---|---:|---|
| `base` | `Id` | symbol | Security identifier |
| `base` | `Ex` | symbol/text | Exchange |
| `base` | `Descr` | symbol/text | Description |
| `base` | `SIC` | symbol/text | SIC code |
| `base` | `SPR` | symbol/text | S&P flag/category |
| `base` | `Cu` | symbol/text | Currency |
| `base` | `CreateDate` | date | Security creation date |
| `price` | `Id` | symbol | Security identifier |
| `price` | `TradeDate` | date | Trading date |
| `price` | `HighPrice` | float | Daily high |
| `price` | `LowPrice` | float | Daily low |
| `price` | `ClosePrice` | float | Daily close |
| `price` | `OpenPrice` | float | Daily open |
| `price` | `Volume` | long/int | Daily volume |
| `split` | `Id` | symbol | Security identifier |
| `split` | `SplitDate` | date | Split date |
| `split` | `EntryDate` | date | Split entry date |
| `split` | `SplitFactor` | float | Split adjustment factor |
| `dividend` | `Id` | symbol | Security identifier |
| `dividend` | `XdivDate` | date | Ex-dividend date |
| `dividend` | `DivAmt` | float | Dividend amount |
| `dividend` | `AnnounceDate` | date | Announcement date |

The following in-memory objects mirror the named sets, date constants, and helper functions used by the L queries.

| Object | q/L form | Purpose |
|---|---|---|
| `stock10` | `10#base\`Id` | First ten securities |
| `stock1000` | `base\`Id` | Full benchmark security set in these datasets |
| `SP500` | `base\`Id` | Benchmark set used by Q3 |
| `Russell2000` | `base\`Id` | Benchmark set used by Q4 and Q9 |
| Date variables | `date$integer` offsets | Stores dataset-specific dates such as `startYear10`, `startPeriod`, `endPeriod`, and `start6Mo` |
| Date helpers | `getMonth`, `getYear`, `getWeek` | Reproduces the date bucketing logic used by the queries |

The L setup does not create persistent indexes or helper tables; queries reference the in-memory tables and variables directly.

## PostgreSQL schema

The PostgreSQL benchmark uses the same financial inputs as the q/L loaders, but stores them in relational tables.  The four financial tables are also TimescaleDB hypertables on their date columns.

| Table | Column | PostgreSQL type | Notes |
|---|---|---:|---|
| `base` | `id` | `text` | Security identifier |
| `base` | `ex` | `text` | Exchange |
| `base` | `descr` | `text` | Description |
| `base` | `sic` | `text` | SIC code |
| `base` | `spr` | `text` | S&P flag/category |
| `base` | `cu` | `text` | Currency |
| `base` | `createdate` | `date` | Hypertable time column |
| `price` | `id` | `text` | Security identifier |
| `price` | `tradedate` | `date` | Hypertable time column |
| `price` | `highprice` | `double precision` | Daily high |
| `price` | `lowprice` | `double precision` | Daily low |
| `price` | `closeprice` | `double precision` | Daily close |
| `price` | `openprice` | `double precision` | Daily open |
| `price` | `volume` | `bigint` | Daily volume |
| `split` | `id` | `text` | Security identifier |
| `split` | `splitdate` | `date` | Hypertable time column |
| `split` | `entrydate` | `date` | Split entry date |
| `split` | `splitfactor` | `double precision` | Split adjustment factor |
| `dividend` | `id` | `text` | Security identifier |
| `dividend` | `xdivdate` | `date` | Ex-dividend date |
| `dividend` | `divamt` | `double precision` | Dividend amount |
| `dividend` | `announcedate` | `date` | Hypertable time column |

PostgreSQL does not have L-style global variables for query scripts, so the benchmark stores named security sets and date constants in helper tables.  The indexes below provide the main access paths used by the SQL queries.

| Object | Definition | Purpose |
|---|---|---|
| `base_id_createdate_idx` | `base(id, createdate)` | Main lookup path for `base` |
| `price_id_tradedate_idx` | `price(id, tradedate)` | Main lookup path for price queries |
| `split_id_splitdate_idx` | `split(id, splitdate)` | Main lookup path for split-adjustment queries |
| `dividend_id_announcedate_idx` | `dividend(id, announcedate)` | Main lookup path for dividend queries |
| `benchmark_sets` | `set_name text`, `id text` | Materializes `stock10`, `stock1000`, `SP500`, and `Russell2000` |
| `benchmark_params` | `name text`, `value date` | Stores dataset-specific dates such as `startYear10`, `startPeriod`, `endPeriod`, and `start6Mo` |

## Benchmark runner scripts

The comparison directory includes local copies of the benchmark runners together with the query files they execute.

| Script | Location | Purpose |
|---|---|---|
| `base_kdb.sh` | `q_query/` | Runs the q/kdb versions of `Q0.q` through `Q9.q` after loading one of the q data loaders, such as `load_10_7.q` or `load_8.q`. |
| `base_l_query.sh` | `q_query/` | Runs the same q query files with the L engine.  The copied script resolves paths relative to `q_query`, so the local `load*.q` and `Qn.q` files are used. |
| `base_postgre.sh` | `sql_query/` | Runs the PostgreSQL versions of `Q0.sql` through `Q9.sql` against the selected database, such as `financial_7` or `financial_8`.  The copied script resolves paths relative to `sql_query`. |

The runners support the same timing options used for the reported results, including `ITERATIONS`, `PURGE_CACHE`, `PURGE_CMD`, and `POST_PURGE_SLEEP`.

### Runner examples

Run KDB on the 10^7 data set:

```bash
cd /path/to/L_comparison/q_query
ITERATIONS=10 Q_BIN=/Users/path/q/m64/q USE_SCRIPT=0 LOAD_SCRIPT=load_10_7.q \
  PURGE_CACHE=1 PURGE_CMD="sudo /usr/sbin/purge" POST_PURGE_SLEEP=2 \
  bash base_kdb.sh Q0.q:Q0 Q1.q:Q1 Q2.q:Q2 Q3.q:Q3 Q4.q:Q4 Q5.q:Q5 Q6.q:Q6 Q7.q:Q7 Q8.q:Q8 Q9.q:Q9
```

Run L on the 10^8 data set:

```bash
cd /path/to/L_comparison/q_query
ITERATIONS=10 LOAD_SCRIPT=load_8.q \
  PURGE_CACHE=1 PURGE_CMD="sudo /usr/sbin/purge" POST_PURGE_SLEEP=2 \
  bash base_l_query.sh Q0.q:Q0 Q1.q:Q1 Q2.q:Q2 Q3.q:Q3 Q4.q:Q4 Q5.q:Q5 Q6.q:Q6 Q7.q:Q7 Q8.q:Q8 Q9.q:Q9
```

Run PostgreSQL on the 10^8 database:

```bash
cd /path/to/L_comparison/sql_query
PG_DB=financial_8 ITERATIONS=10 \
  PURGE_CACHE=1 PURGE_CMD="sudo /usr/sbin/purge" POST_PURGE_SLEEP=2 \
  bash base_postgre.sh Q0.sql:Q0 Q1.sql:Q1 Q2.sql:Q2 Q3.sql:Q3 Q4.sql:Q4 Q5.sql:Q5 Q6.sql:Q6 Q7.sql:Q7 Q8.sql:Q8 Q9.sql:Q9
```

For 10^7 runs, use `LOAD_SCRIPT=load_10_7.q` for AQuery/L and `PG_DB=financial_7` for PostgreSQL.

## Financial query descriptions

The descriptions below use the 10^7 benchmark ranges from `load_10_7.q`.  In
that data set, `stock10` is the first 10 securities, while `stock1000`, `SP500`,
and `Russell2000` are benchmark set names backed by the available generated
security universe.

| Variable | 10^7 value | Used by |
|---|---:|---|
| `startYear10` | `2116-01-01` | Q0 |
| `startYear10 + 3650` | `2125-12-29` | Q0 |
| `start300Days` | `2125-01-01` | Q1 |
| `start300Days + 300` | `2125-10-28` | Q1 |
| `startPeriod` | `2126-01-01` | Q2, Q3, Q4, Q8 |
| `endPeriod` | `2126-02-05` | Q2 |
| `start6Mo` | `2125-08-01` | Q5, Q6 |
| `start6Mo + 186` | `2126-02-03` | Q5, Q6 |
| `maxTradeDateMinus3Years` | `2125-01-01` | Q9 |

```text
********* QUERY 0 ****************
For the 10 selected stocks in `stock10`, read close prices from `startYear10`
through `startYear10 + 3650` (2116-01-01 to 2125-12-29 in the 10^7 data set).
Group those prices into weekly, monthly, and yearly buckets, then compute the
low, high, and average close price for each stock and bucket. The output is
sorted by security id, aggregate name, and time bucket.

********* QUERY 1 ****************
For the `stock1000` sample, read price rows from `start300Days` through
`start300Days + 300` (2125-01-01 to 2125-10-28) and split rows from
`start300Days` onward. Adjust prices and volumes by the cumulative future split
factor: prices are multiplied by the factor and volumes are divided by the
factor. The result contains split-adjusted high, low, close, open, and volume
values for the selected 300-day period.

********* QUERY 2 ****************
For the `stock1000` sample, read price rows and split rows from `startPeriod`
through `endPeriod` (2126-01-01 to 2126-02-05). Join price rows to split events
on `(Id, TradeDate)`, then return the high-minus-low price difference on split
days.

********* QUERY 3 ****************
For the `SP500` sample, read unadjusted close prices on `startPeriod`
(2126-01-01) and return their average. This is the simple benchmark index value
for that date.

********* QUERY 4 ****************
For the `Russell2000` sample, read unadjusted close prices on `startPeriod`
(2126-01-01) and return their average. This is the simple benchmark index value
for that date.

********* QUERY 5 ****************
For the `stock1000` sample, read close prices from `start6Mo` up to but not
including `start6Mo + 186` (2125-08-01 to 2126-02-03) and split rows from
`start6Mo` onward. Build split-adjusted close prices, then compute the 21-row
and 5-row moving averages for each stock.

********* QUERY 6 ****************
For the `stock1000` sample, use the same adjusted-price input as Q5: prices from
`start6Mo` up to `start6Mo + 186` and split rows from `start6Mo` onward. Compute
21-row and 5-row moving averages, then return dates where the 5-row average
crosses above or below the 21-row average.

********* QUERY 7 ****************
For the 10 selected stocks in `stock10`, read price rows from the latest global
`TradeDate` minus 365 days onward and split rows from the latest global
`SplitDate` minus 365 days onward. Build split-adjusted prices, compute 21-row
and 160-row moving averages, identify crossover events, and simulate the trading
strategy from an initial allocation of 10000 per stock.

********* QUERY 8 ****************
For the 10 selected stocks in `stock10`, read close prices from `startPeriod`
through `startPeriod + 3` (2126-01-01 to 2126-01-04). Build all stock pairs,
align their close-price series by trade date, compute pairwise correlation
coefficients, and sort by correlation value.

********* QUERY 9 ****************
For the `Russell2000` sample, use `maxTradeDateMinus3Years` as the lookback
start date (2125-01-01). Find securities that did not split in or after that
lookback year, compute yearly average close price and yearly total dividends for
those no-split securities, and return annual dividend yield as total dividends
divided by average close price.
```

## response time

### Benchmark environment

The benchmarks were run locally on a Mac laptop with an Apple M4 Pro chip and
48 GB of memory.

The reported response time is end-to-end wall-clock time measured by the benchmark runner scripts.  It includes process startup, data loading or database access, query execution, and writing the query output to a temporary file.

For L and kdb/AQuery, each run loads the q binary data into memory and then executes the query.  For PostgreSQL, the data has already been loaded into the database; each run starts a `psql` client, connects to the selected database, executes the SQL query, and materializes the output.

The measurements were taken with cold-cache settings: `PURGE_CACHE=1` and a 2-second post-purge sleep before each iteration.  On macOS this purges the file system cache, but it does not guarantee that every PostgreSQL internal buffer or OS-level effect is fully reset.

The results of Q6 and Q7 may differ slightly across systems because their moving-average crossover logic is sensitive to floating-point rounding.

### 10^8-row dataset

| Query | PostgreSQL 10^8 (s) | L 10^8 (s) | KDB 10^8 (s) |
|---|---:|---:|---:|
| Q0 | 1.6441 ± 0.0277 | 5.5960 ± 0.1003 | 5.5138 ± 0.3715 |
| Q1 | 2.3576 ± 0.0527 | 5.6831 ± 0.0588 | 5.5974 ± 0.3912 |
| Q2 | 1.9332 ± 0.0154 | 5.6319 ± 0.0343 | 5.5126 ± 0.4100 |
| Q3 | 2.0139 ± 0.0497 | 5.5718 ± 0.0312 | 5.5774 ± 0.3200 |
| Q4 | 2.0057 ± 0.0158 | 5.5474 ± 0.0490 | 5.5566 ± 0.4290 |
| Q5 | 2.0607 ± 0.0433 | 5.6614 ± 0.0773 | 5.5949 ± 0.4308 |
| Q6 | 1.9154 ± 0.0170 | 5.6157 ± 0.0664 | 5.6848 ± 0.3679 |
| Q7 | 5.8711 ± 0.0221 | 5.5629 ± 0.0427 | 5.5719 ± 0.3323 |
| Q8 | 2.1626 ± 0.0168 | 5.6352 ± 0.0641 | 5.4621 ± 0.3456 |
| Q9 | 11.4099 ± 0.0645 | 5.9720 ± 0.0547 | 6.5350 ± 0.3550 |

### 10^7-row dataset

| Query | PostgreSQL 10^7 (s) | L 10^7 (s) | KDB 10^7 (s) |
|---|---:|---:|---:|
| Q0 | 0.7747 ± 0.0150 | 0.9956 ± 0.0616 | 1.2348 ± 0.3612 |
| Q1 | 1.9150 ± 0.0328 | 1.0260 ± 0.0482 | 1.2462 ± 0.3520 |
| Q2 | 1.5676 ± 0.0310 | 0.9685 ± 0.0843 | 1.3253 ± 0.4212 |
| Q3 | 0.8554 ± 0.0260 | 0.9792 ± 0.0673 | 1.3184 ± 0.2513 |
| Q4 | 0.8530 ± 0.0168 | 0.9786 ± 0.0698 | 1.2887 ± 0.3585 |
| Q5 | 1.6750 ± 0.0207 | 0.9861 ± 0.0801 | 1.3864 ± 0.4150 |
| Q6 | 1.5842 ± 0.0097 | 0.9464 ± 0.0387 | 1.3348 ± 0.3433 |
| Q7 | 2.2140 ± 0.0106 | 0.9821 ± 0.0649 | 1.2469 ± 0.3829 |
| Q8 | 0.6594 ± 0.0058 | 0.9999 ± 0.0598 | 1.2538 ± 0.2711 |
| Q9 | 2.7029 ± 0.0223 | 1.0482 ± 0.0249 | 1.5427 ± 0.4026 |
