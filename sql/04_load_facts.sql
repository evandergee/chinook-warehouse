/* =============================================================================
   Load fact:  stg.InvoiceLine  ->  dwh.FactSales
   -----------------------------------------------------------------------------
   Grain: one row per invoice line. Incremental via MERGE on the business key
   (InvoiceLineId) — new lines are inserted, changed lines are corrected, and a
   re-run with no source changes is a no-op.

   Surrogate-key lookups:
     * DimCustomer is an as-of join — the version whose
       [RowStartDate, RowEndDate) window contains the invoice date, so historical
       lines keep pointing at the customer attributes that were true back then.
     * anything that fails to resolve falls back to the -1 Unknown member.

   Run:  .\q.ps1 -File sql\04_load_facts.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

;WITH src AS (
    SELECT
        il.InvoiceLineId,
        il.InvoiceId,
        ISNULL(dd.DateKey,     -1) AS DateKey,
        ISNULL(dc.CustomerKey, -1) AS CustomerKey,
        ISNULL(dt.TrackKey,    -1) AS TrackKey,
        ISNULL(de.EmployeeKey, -1) AS EmployeeKey,
        il.Quantity,
        il.UnitPrice,
        CAST(il.Quantity * il.UnitPrice AS decimal(12,2)) AS ExtendedAmount
    FROM stg.InvoiceLine AS il
    JOIN stg.Invoice AS i
        ON i.InvoiceId = il.InvoiceId
    LEFT JOIN dwh.DimDate AS dd
        ON dd.DateKey = YEAR(i.InvoiceDate) * 10000 + MONTH(i.InvoiceDate) * 100 + DAY(i.InvoiceDate)
    LEFT JOIN dwh.DimCustomer AS dc
        ON dc.CustomerId = i.CustomerId
       AND i.InvoiceDate >= dc.RowStartDate
       AND i.InvoiceDate <  dc.RowEndDate
    LEFT JOIN dwh.DimTrack AS dt
        ON dt.TrackId = il.TrackId
    LEFT JOIN stg.Customer AS sc
        ON sc.CustomerId = i.CustomerId
    LEFT JOIN dwh.DimEmployee AS de
        ON de.EmployeeId = sc.SupportRepId
)
MERGE dwh.FactSales AS tgt
USING src
    ON tgt.InvoiceLineId = src.InvoiceLineId
WHEN MATCHED AND (
        tgt.DateKey        <> src.DateKey
     OR tgt.CustomerKey    <> src.CustomerKey
     OR tgt.TrackKey       <> src.TrackKey
     OR tgt.EmployeeKey    <> src.EmployeeKey
     OR tgt.Quantity       <> src.Quantity
     OR tgt.UnitPrice      <> src.UnitPrice
     OR tgt.ExtendedAmount <> src.ExtendedAmount
) THEN
    UPDATE SET
        tgt.DateKey        = src.DateKey,
        tgt.CustomerKey    = src.CustomerKey,
        tgt.TrackKey       = src.TrackKey,
        tgt.EmployeeKey    = src.EmployeeKey,
        tgt.Quantity       = src.Quantity,
        tgt.UnitPrice      = src.UnitPrice,
        tgt.ExtendedAmount = src.ExtendedAmount,
        tgt.LoadedAt       = SYSUTCDATETIME()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (InvoiceLineId, InvoiceId, DateKey, CustomerKey, TrackKey, EmployeeKey,
            Quantity, UnitPrice, ExtendedAmount, LoadedAt)
    VALUES (src.InvoiceLineId, src.InvoiceId, src.DateKey, src.CustomerKey, src.TrackKey, src.EmployeeKey,
            src.Quantity, src.UnitPrice, src.ExtendedAmount, SYSUTCDATETIME());

PRINT CONCAT('FactSales    : ', @@ROWCOUNT, ' rows inserted/updated this run');
GO

PRINT 'Fact load complete.';
GO
