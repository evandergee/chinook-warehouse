/* =============================================================================
   Simulate source changes — so the incremental load has something to do
   -----------------------------------------------------------------------------
   Chinook never changes, so this script edits STAGING only (never dbo) to mimic
   what a nightly extract would pick up:

     1. Customer 1 moves to Berlin, Germany   -> should create a 2nd SCD2 version
     2. One brand-new invoice with 3 lines    -> 3 new FactSales rows

   Idempotent: fixed IDs in a 900000+ range, deleted then re-inserted. Re-running
   the whole pipeline is stable.

   Run:  .\q.ps1 -File sql\06_simulate_changes.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

/* ---- 1. Customer 1 changes address ------------------------------------------- */
UPDATE stg.Customer
SET City    = N'Berlin',
    [State] = NULL,
    Country = N'Germany',
    RowHash = HASHBYTES('SHA2_256', CONCAT_WS(N'|', FirstName, LastName, Email, N'Berlin', NULL, N'Germany'))
WHERE CustomerId = 1;
PRINT CONCAT('Customer 1 address updated in staging (', @@ROWCOUNT, ' row)');
GO

/* ---- 2. A new invoice for customer 5, dated now, with 3 lines --------------- */
DELETE FROM stg.InvoiceLine WHERE InvoiceLineId BETWEEN 900001 AND 900003;
DELETE FROM stg.Invoice     WHERE InvoiceId = 900001;

INSERT stg.Invoice (InvoiceId, CustomerId, InvoiceDate)
VALUES (900001, 5, SYSUTCDATETIME());

INSERT stg.InvoiceLine (InvoiceLineId, InvoiceId, TrackId, UnitPrice, Quantity)
VALUES (900001, 900001,  1, 0.99, 1),
       (900002, 900001,  2, 0.99, 2),
       (900003, 900001,  3, 0.99, 1);
PRINT 'New invoice 900001 (3 lines, $3.96) inserted in staging';
GO

PRINT 'Simulated changes applied.';
GO
