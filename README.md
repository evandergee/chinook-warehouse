# Chinook data warehouse — dimensional model + ETL

> Built by Evan Gilb, with Claude as an AI coding partner.

A star schema built on top of the [Chinook sample database](https://github.com/lerocha/chinook-database),
with an **incremental, idempotent ETL pipeline** that loads it — the kind of build an
analytics/BI engineer owns end to end.

```powershell
.\run_pipeline.ps1
```

That one script runs the whole thing: create schemas → extract → load → validate →
**simulate a day of source changes** → re-run the load incrementally → validate again →
show the payoff queries. Takes a few seconds. Needs SQL Server (Express is fine) with the
Chinook database and `sqlcmd`.

---

## The model

```
                         DimDate
                            |
   DimCustomer  ------  FactSales  ------  DimTrack
      (SCD 2)               |               (SCD 1)
                       DimEmployee
                        (SCD 1)
```

| Object | Type | Notes |
|---|---|---|
| `dwh.FactSales` | fact | grain = one invoice line; additive measures `Quantity`, `ExtendedAmount`; `InvoiceId` kept as a degenerate dimension |
| `dwh.DimCustomer` | **SCD Type 2** | address changes are versioned — `RowStartDate` / `RowEndDate` / `IsCurrent` |
| `dwh.DimTrack` | SCD Type 1 | catalog attributes (album, artist, genre, media type) flattened; corrections overwrite |
| `dwh.DimEmployee` | SCD Type 1 | the sales support rep |
| `dwh.DimDate` | static | generated calendar, one row per day |

Every dimension has a surrogate key (`IDENTITY`) and a `-1` **Unknown member** so the fact
never carries a NULL foreign key. `FactSales` has real foreign keys to all four dimensions.

## The pipeline

| Step | Script | What it does |
|---|---|---|
| 1 | [`01_create_schemas.sql`](sql/01_create_schemas.sql) | `stg` + `dwh` schemas, all tables, Unknown members. Drop-and-recreate — safe to re-run. |
| 2 | [`02_extract_to_staging.sql`](sql/02_extract_to_staging.sql) | Full extract `dbo → stg`. Denormalises Track. Computes a **SHA-256 `RowHash`** per row for change detection. |
| 3 | [`03_load_dimensions.sql`](sql/03_load_dimensions.sql) | `MERGE` each dimension from staging. SCD1 = overwrite on hash change; SCD2 = expire the current row + insert a new version (`MERGE … OUTPUT … INTO`, then a second `INSERT`). |
| 4 | [`04_load_facts.sql`](sql/04_load_facts.sql) | `MERGE` `FactSales` on `InvoiceLineId`. Surrogate-key lookups, including an **as-of join** to `DimCustomer` (`InvoiceDate` between `RowStartDate` and `RowEndDate`) so historical rows keep the attributes that were true then. |
| 5 | [`05_validate.sql`](sql/05_validate.sql) | Six reconciliation checks (row counts, revenue to the cent, no orphan keys, exactly one current row per customer, no SCD2 timeline gaps). One result set, every row `PASS`. |
| 6 | [`06_simulate_changes.sql`](sql/06_simulate_changes.sql) | Edits **staging only** (never `dbo`): moves customer 1 to Berlin, adds one new invoice — so step 3–4 re-run has real work to do. |
| 7 | [`07_demo_star_queries.sql`](sql/07_demo_star_queries.sql) | Plain star joins: revenue by year, top genres, sales-rep leaderboard, and customer 1's SCD2 history. |

Steps 3 and 4 are **idempotent** — re-run them with no source changes and they report `0`
rows touched.

## What the incremental run proves

After `06` moves customer 1 and adds an invoice, the second pass of `03`/`04` reports:

```
DimCustomer  : +0 new customers, 1 new versions from changed rows
FactSales    : 3 rows inserted/updated this run
```

and `DimCustomer` now holds both versions, with a gap-free timeline:

```
CustomerKey | CustomerId | City                 | Country | RowStartDate        | RowEndDate           | IsCurrent
----------- | ---------- | -------------------- | ------- | ------------------- | -------------------- | ---------
1           | 1          | São José dos Campos  | Brazil  | 1900-01-01 00:00:00 | 2026-08-31 21:55:00  | 0
60          | 1          | Berlin               | Germany | 2026-08-31 21:55:00 | 9999-12-31 00:00:00  | 1
```

Every one of customer 1's historical invoices still points at `CustomerKey 1` (Brazil);
only new activity would attach to `CustomerKey 60`.

## Skills demonstrated

- Kimball dimensional modelling — grain, conformed dimensions, surrogate keys, degenerate dimensions, Unknown members
- Slowly Changing Dimensions, Type 1 **and** Type 2, implemented with `MERGE`
- Hash-based change data capture (`HASHBYTES`, `CONCAT_WS`)
- Idempotent, incremental ETL with a staging layer
- As-of / point-in-time dimension joins
- Automated load validation / data-reconciliation checks
- Set-based T-SQL, `GENERATE_SERIES`, `MERGE … OUTPUT … INTO`

## Repo contents

```
run_pipeline.ps1     one-command end-to-end build
q.ps1                thin sqlcmd wrapper (edit the server/db at the top if needed)
sql/01..07           the pipeline, in order
```
