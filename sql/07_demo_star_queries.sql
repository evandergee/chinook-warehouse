/* =============================================================================
   The payoff — what the star schema makes easy
   -----------------------------------------------------------------------------
   Every query below is a simple star join: FactSales + a dimension + GROUP BY.
   No window functions, no CTEs, no knowledge of the source schema required.

   Run:  .\q.ps1 -File sql\07_demo_star_queries.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

PRINT '========== warehouse contents ==========';
SELECT 'DimDate' AS [Table], COUNT(*) AS Rows FROM dwh.DimDate
UNION ALL SELECT 'DimCustomer',  COUNT(*) FROM dwh.DimCustomer
UNION ALL SELECT 'DimTrack',     COUNT(*) FROM dwh.DimTrack
UNION ALL SELECT 'DimEmployee',  COUNT(*) FROM dwh.DimEmployee
UNION ALL SELECT 'FactSales',    COUNT(*) FROM dwh.FactSales;

PRINT '========== 1. SCD Type 2 history for customer 1 ==========';
PRINT 'after the simulated move there should be 2 rows: an expired one and a current one';
SELECT CustomerKey, CustomerId, FirstName, LastName, City, Country,
       RowStartDate, RowEndDate, IsCurrent
FROM dwh.DimCustomer
WHERE CustomerId = 1
ORDER BY RowStartDate;

PRINT '========== 2. revenue by year ==========';
SELECT d.[Year],
       COUNT(DISTINCT f.InvoiceId) AS Invoices,
       CAST(SUM(f.ExtendedAmount) AS decimal(12,2)) AS Revenue
FROM dwh.FactSales AS f
JOIN dwh.DimDate   AS d ON d.DateKey = f.DateKey
GROUP BY d.[Year]
ORDER BY d.[Year];

PRINT '========== 3. top 10 genres by revenue ==========';
SELECT TOP 10
       t.Genre,
       CAST(SUM(f.ExtendedAmount) AS decimal(12,2)) AS Revenue,
       SUM(f.Quantity)                              AS UnitsSold
FROM dwh.FactSales AS f
JOIN dwh.DimTrack  AS t ON t.TrackKey = f.TrackKey
GROUP BY t.Genre
ORDER BY Revenue DESC;

PRINT '========== 4. sales-rep leaderboard ==========';
SELECT e.FullName AS SalesRep,
       COUNT(DISTINCT f.CustomerKey)               AS Customers,
       CAST(SUM(f.ExtendedAmount) AS decimal(12,2)) AS Revenue
FROM dwh.FactSales   AS f
JOIN dwh.DimEmployee AS e ON e.EmployeeKey = f.EmployeeKey
WHERE e.EmployeeKey <> -1
GROUP BY e.FullName
ORDER BY Revenue DESC;

PRINT '========== 5. the simulated invoice 900001 landed in the fact ==========';
SELECT f.InvoiceId, f.InvoiceLineId, c.FirstName, c.LastName,
       t.TrackName, f.Quantity, f.ExtendedAmount, d.[Date]
FROM dwh.FactSales   AS f
JOIN dwh.DimCustomer AS c ON c.CustomerKey = f.CustomerKey
JOIN dwh.DimTrack    AS t ON t.TrackKey    = f.TrackKey
JOIN dwh.DimDate     AS d ON d.DateKey     = f.DateKey
WHERE f.InvoiceId = 900001;
GO
