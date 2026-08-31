/* =============================================================================
   Load dimensions:  stg  ->  dwh.Dim*
   -----------------------------------------------------------------------------
   Incremental and idempotent. Run it once for the initial load and again after
   every extract; each object only touches the rows that actually changed.

     DimDate      generate any missing calendar days
     DimEmployee  SCD Type 1  — overwrite in place
     DimTrack     SCD Type 1  — overwrite in place
     DimCustomer  SCD Type 2  — expire the old row, insert a new current version

   Run:  .\q.ps1 -File sql\03_load_dimensions.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

/* ---- DimDate --------------------------------------------------------------------
   Cover every year touched by an invoice, Jan 1 .. Dec 31, and only insert days
   that aren't already there. */
DECLARE @min date = (SELECT DATEFROMPARTS(YEAR(MIN(InvoiceDate)),  1,  1) FROM stg.Invoice);
DECLARE @max date = (SELECT DATEFROMPARTS(YEAR(MAX(InvoiceDate)), 12, 31) FROM stg.Invoice);

;WITH d AS (
    SELECT DATEADD(DAY, value, @min) AS dt
    FROM GENERATE_SERIES(0, DATEDIFF(DAY, @min, @max))
)
INSERT dwh.DimDate (DateKey, [Date], [Year], [Quarter], MonthNo, MonthName, DayNo, WeekdayName, IsWeekend)
SELECT
    YEAR(dt) * 10000 + MONTH(dt) * 100 + DAY(dt),
    dt, YEAR(dt), DATEPART(QUARTER, dt), MONTH(dt),
    DATENAME(MONTH, dt), DAY(dt), DATENAME(WEEKDAY, dt),
    CASE WHEN DATENAME(WEEKDAY, dt) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END
FROM d
WHERE NOT EXISTS (
    SELECT 1 FROM dwh.DimDate dd
    WHERE dd.DateKey = YEAR(d.dt) * 10000 + MONTH(d.dt) * 100 + DAY(d.dt)
);
PRINT CONCAT('DimDate      : +', @@ROWCOUNT, ' new days');
GO

/* ---- DimEmployee : SCD Type 1 -------------------------------------------------- */
MERGE dwh.DimEmployee AS tgt
USING stg.Employee AS src
    ON tgt.EmployeeId = src.EmployeeId
WHEN MATCHED AND tgt.RowHash <> src.RowHash THEN
    UPDATE SET tgt.FullName = src.FullName,
               tgt.Title    = src.Title,
               tgt.RowHash  = src.RowHash
WHEN NOT MATCHED BY TARGET THEN
    INSERT (EmployeeId, FullName, Title, RowHash)
    VALUES (src.EmployeeId, src.FullName, src.Title, src.RowHash);
PRINT CONCAT('DimEmployee  : ', @@ROWCOUNT, ' inserted/updated');
GO

/* ---- DimTrack : SCD Type 1 --------------------------------------------------- */
MERGE dwh.DimTrack AS tgt
USING stg.Track AS src
    ON tgt.TrackId = src.TrackId
WHEN MATCHED AND tgt.RowHash <> src.RowHash THEN
    UPDATE SET tgt.TrackName    = src.TrackName,
               tgt.Album        = src.Album,
               tgt.Artist       = src.Artist,
               tgt.Genre        = src.Genre,
               tgt.MediaType    = src.MediaType,
               tgt.Composer     = src.Composer,
               tgt.Milliseconds = src.Milliseconds,
               tgt.UnitPrice    = src.UnitPrice,
               tgt.RowHash      = src.RowHash
WHEN NOT MATCHED BY TARGET THEN
    INSERT (TrackId, TrackName, Album, Artist, Genre, MediaType, Composer, Milliseconds, UnitPrice, RowHash)
    VALUES (src.TrackId, src.TrackName, src.Album, src.Artist, src.Genre, src.MediaType,
            src.Composer, src.Milliseconds, src.UnitPrice, src.RowHash);
PRINT CONCAT('DimTrack     : ', @@ROWCOUNT, ' inserted/updated');
GO

/* ---- DimCustomer : SCD Type 2 ----------------------------------------------------
   Two steps:
     1. MERGE — insert brand-new customers, and EXPIRE the current row of any
        customer whose hash changed (IsCurrent -> 0, RowEndDate -> now). The
        expired rows are captured via OUTPUT ... INTO.
     2. INSERT a fresh current version for every customer the MERGE expired.
   (The wrapped "INSERT ... SELECT FROM (MERGE ...)" form can't be used here
   because FactSales has a foreign key to DimCustomer.)
   First-time rows start at 1900-01-01 so every historical invoice falls inside
   some version's [RowStartDate, RowEndDate) window. */
DECLARE @Now datetime2(0) = SYSUTCDATETIME();
DECLARE @changed TABLE (
    MergeAction nvarchar(10),
    CustomerId  int,
    FirstName   nvarchar(40),
    LastName    nvarchar(20),
    Email       nvarchar(60),
    City        nvarchar(40),
    [State]     nvarchar(40),
    Country     nvarchar(40),
    RowHash     varbinary(32)
);

MERGE dwh.DimCustomer AS tgt
USING stg.Customer AS src
    ON tgt.CustomerId = src.CustomerId AND tgt.IsCurrent = 1
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CustomerId, FirstName, LastName, Email, City, [State], Country, RowHash, RowStartDate, RowEndDate, IsCurrent)
    VALUES (src.CustomerId, src.FirstName, src.LastName, src.Email, src.City, src.[State], src.Country,
            src.RowHash, '1900-01-01', '9999-12-31', 1)
WHEN MATCHED AND tgt.RowHash <> src.RowHash THEN
    UPDATE SET tgt.IsCurrent = 0,
               tgt.RowEndDate = @Now
OUTPUT $action, src.CustomerId, src.FirstName, src.LastName, src.Email,
       src.City, src.[State], src.Country, src.RowHash
INTO @changed;

INSERT dwh.DimCustomer
    (CustomerId, FirstName, LastName, Email, City, [State], Country, RowHash, RowStartDate, RowEndDate, IsCurrent)
SELECT
    CustomerId, FirstName, LastName, Email, City, [State], Country, RowHash, @Now, '9999-12-31', 1
FROM @changed
WHERE MergeAction = 'UPDATE';

DECLARE @newRows int = @@ROWCOUNT;
DECLARE @newCust int = (SELECT COUNT(*) FROM @changed WHERE MergeAction = 'INSERT');
PRINT CONCAT('DimCustomer  : +', @newCust, ' new customers, ', @newRows, ' new versions from changed rows');
GO

PRINT 'Dimension load complete.';
GO
