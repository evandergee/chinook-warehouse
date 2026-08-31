/* =============================================================================
   Validate the load — reconcile the warehouse against staging
   -----------------------------------------------------------------------------
   One result set: Check | Expected | Actual | Status. Every row should say PASS.

   Run:  .\q.ps1 -File sql\05_validate.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

;WITH checks AS (

    SELECT 1 AS Seq, 'FactSales row count = InvoiceLine row count' AS [Check],
           (SELECT COUNT(*) FROM stg.InvoiceLine)                  AS Expected,
           (SELECT COUNT(*) FROM dwh.FactSales)                    AS Actual

    UNION ALL
    SELECT 2, 'FactSales revenue = source revenue (cents)',
           (SELECT CAST(ROUND(SUM(UnitPrice * Quantity), 2) * 100 AS bigint) FROM stg.InvoiceLine),
           (SELECT CAST(ROUND(SUM(ExtendedAmount), 2)        * 100 AS bigint) FROM dwh.FactSales)

    UNION ALL
    SELECT 3, 'Fact rows pointing at an Unknown (-1) dimension',
           0,
           (SELECT COUNT(*) FROM dwh.FactSales
            WHERE -1 IN (DateKey, CustomerKey, TrackKey) )       -- EmployeeKey -1 is legit (no support rep)

    UNION ALL
    SELECT 4, 'Customers with more than one current row',
           0,
           (SELECT COUNT(*) FROM (
                SELECT CustomerId FROM dwh.DimCustomer
                WHERE IsCurrent = 1 AND CustomerKey <> -1
                GROUP BY CustomerId HAVING COUNT(*) > 1) x)

    UNION ALL
    SELECT 5, 'SCD2 expired rows with no matching next version (timeline gap)',
           0,
           (SELECT COUNT(*)
            FROM dwh.DimCustomer a
            WHERE a.IsCurrent = 0 AND a.CustomerKey <> -1
              AND NOT EXISTS (SELECT 1 FROM dwh.DimCustomer b
                              WHERE b.CustomerId = a.CustomerId
                                AND b.RowStartDate = a.RowEndDate))

    UNION ALL
    SELECT 6, 'Distinct customers in warehouse = staging',
           (SELECT COUNT(*) FROM stg.Customer),
           (SELECT COUNT(DISTINCT CustomerId) FROM dwh.DimCustomer WHERE CustomerKey <> -1)
)
SELECT
    [Check],
    Expected,
    Actual,
    CASE WHEN ISNULL(Expected, -999) = ISNULL(Actual, -998) THEN 'PASS' ELSE '*** FAIL ***' END AS Status
FROM checks
ORDER BY Seq;
GO
