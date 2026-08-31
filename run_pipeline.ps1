<#
    run_pipeline.ps1 — build the warehouse end to end and prove the incremental
    load works.

      1. create schemas            (sql\01)
      2. extract dbo -> stg        (sql\02)
      3. initial load  dims + fact (sql\03, sql\04)
      4. validate                  (sql\05)
      5. simulate source changes   (sql\06)
      6. incremental load          (sql\03, sql\04)   <- same scripts, re-run
      7. validate + demo           (sql\05, sql\07)

    Needs SQL Server with the Chinook database and sqlcmd. Takes a few seconds.
    Run:  .\run_pipeline.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
function Sql($rel) { & "$root\q.ps1" -File (Join-Path $root $rel) | Write-Host }
function Head($n)  { Write-Host "`n### $n" -ForegroundColor Cyan }

Head '1. create schemas';                 Sql 'sql\01_create_schemas.sql'
Head '2. extract  dbo -> stg';             Sql 'sql\02_extract_to_staging.sql'
Head '3. initial load: dimensions';        Sql 'sql\03_load_dimensions.sql'
Head '3. initial load: fact';              Sql 'sql\04_load_facts.sql'
Head '4. validate (initial load)';         Sql 'sql\05_validate.sql'

Head '5. simulate source changes';         Sql 'sql\06_simulate_changes.sql'

Head '6. incremental load: dimensions';    Sql 'sql\03_load_dimensions.sql'
Head '6. incremental load: fact';          Sql 'sql\04_load_facts.sql'

Head '7. validate (after incremental)';    Sql 'sql\05_validate.sql'
Head '7. star-schema demo queries';        Sql 'sql\07_demo_star_queries.sql'

Write-Host "`nDone. Every validation check above should read PASS." -ForegroundColor Green
Write-Host "The load scripts (03, 04) are idempotent: run them again with no source" -ForegroundColor Green
Write-Host "changes and they report 0 rows touched." -ForegroundColor Green
