/* =============================================================================
   Chinook warehouse — schema build
   -----------------------------------------------------------------------------
   Creates two schemas and drops/recreates every object, so this is safe to run
   repeatedly:

       stg   staging   — a raw copy of the source tables, one row per business key
       dwh   warehouse — a Kimball star schema loaded from stg

   Star:                         DimDate
                                    |
              DimCustomer  --- FactSales ---  DimTrack
                   |                              (grain: one invoice line)
              DimEmployee

     DimCustomer   SCD Type 2  (address changes keep history)
     DimTrack      SCD Type 1  (catalog corrections overwrite)
     DimEmployee   SCD Type 1
     DimDate       static calendar
     FactSales     additive measures: Quantity, ExtendedAmount

   Run:  .\q.ps1 -File sql\01_create_schemas.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('dwh') IS NULL EXEC('CREATE SCHEMA dwh');
GO

/* ---- drop in FK order --------------------------------------------------------- */
DROP TABLE IF EXISTS dwh.FactSales;
DROP TABLE IF EXISTS dwh.DimCustomer;
DROP TABLE IF EXISTS dwh.DimTrack;
DROP TABLE IF EXISTS dwh.DimEmployee;
DROP TABLE IF EXISTS dwh.DimDate;

DROP TABLE IF EXISTS stg.InvoiceLine;
DROP TABLE IF EXISTS stg.Invoice;
DROP TABLE IF EXISTS stg.Customer;
DROP TABLE IF EXISTS stg.Track;
DROP TABLE IF EXISTS stg.Employee;
GO

/* ============================ staging ======================================== */
CREATE TABLE stg.Customer (
    CustomerId    int          NOT NULL PRIMARY KEY,
    FirstName     nvarchar(40) NULL,
    LastName      nvarchar(20) NULL,
    Email         nvarchar(60) NULL,
    City          nvarchar(40) NULL,
    [State]       nvarchar(40) NULL,
    Country       nvarchar(40) NULL,
    SupportRepId  int          NULL,
    RowHash       varbinary(32) NOT NULL
);

CREATE TABLE stg.Employee (
    EmployeeId  int           NOT NULL PRIMARY KEY,
    FullName    nvarchar(80)  NULL,
    Title       nvarchar(30)  NULL,
    RowHash     varbinary(32) NOT NULL
);

CREATE TABLE stg.Track (
    TrackId       int           NOT NULL PRIMARY KEY,
    TrackName     nvarchar(200) NULL,
    Album         nvarchar(160) NULL,
    Artist        nvarchar(120) NULL,
    Genre         nvarchar(120) NULL,
    MediaType     nvarchar(120) NULL,
    Composer      nvarchar(220) NULL,
    Milliseconds  int           NULL,
    UnitPrice     decimal(10,2) NULL,
    RowHash       varbinary(32) NOT NULL
);

CREATE TABLE stg.Invoice (
    InvoiceId   int          NOT NULL PRIMARY KEY,
    CustomerId  int          NOT NULL,
    InvoiceDate datetime2(3) NOT NULL
);

CREATE TABLE stg.InvoiceLine (
    InvoiceLineId int           NOT NULL PRIMARY KEY,
    InvoiceId     int           NOT NULL,
    TrackId       int           NOT NULL,
    UnitPrice     decimal(10,2) NOT NULL,
    Quantity      int           NOT NULL
);
GO

/* ============================ dimensions ==================================== */
CREATE TABLE dwh.DimDate (
    DateKey      int         NOT NULL PRIMARY KEY,   -- yyyymmdd, -1 = Unknown
    [Date]       date        NOT NULL,
    [Year]       smallint    NOT NULL,
    [Quarter]    tinyint     NOT NULL,
    MonthNo      tinyint     NOT NULL,
    MonthName    varchar(12) NOT NULL,
    DayNo        tinyint     NOT NULL,
    WeekdayName  varchar(12) NOT NULL,
    IsWeekend    bit         NOT NULL
);

CREATE TABLE dwh.DimCustomer (
    CustomerKey   int          NOT NULL IDENTITY(1,1) PRIMARY KEY,  -- surrogate
    CustomerId    int          NOT NULL,                            -- business key
    FirstName     nvarchar(40) NULL,
    LastName      nvarchar(20) NULL,
    Email         nvarchar(60) NULL,
    City          nvarchar(40) NULL,
    [State]       nvarchar(40) NULL,
    Country       nvarchar(40) NULL,
    RowHash       varbinary(32) NOT NULL,
    RowStartDate  datetime2(0) NOT NULL,
    RowEndDate    datetime2(0) NOT NULL,               -- '9999-12-31' while current
    IsCurrent     bit          NOT NULL
);
CREATE INDEX IX_DimCustomer_BK ON dwh.DimCustomer (CustomerId, IsCurrent);

CREATE TABLE dwh.DimTrack (
    TrackKey      int           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    TrackId       int           NOT NULL,
    TrackName     nvarchar(200) NULL,
    Album         nvarchar(160) NULL,
    Artist        nvarchar(120) NULL,
    Genre         nvarchar(120) NULL,
    MediaType     nvarchar(120) NULL,
    Composer      nvarchar(220) NULL,
    Milliseconds  int           NULL,
    UnitPrice     decimal(10,2) NULL,
    RowHash       varbinary(32) NOT NULL
);
CREATE UNIQUE INDEX IX_DimTrack_BK ON dwh.DimTrack (TrackId);

CREATE TABLE dwh.DimEmployee (
    EmployeeKey int           NOT NULL IDENTITY(1,1) PRIMARY KEY,
    EmployeeId  int           NOT NULL,
    FullName    nvarchar(80)  NULL,
    Title       nvarchar(30)  NULL,
    RowHash     varbinary(32) NOT NULL
);
CREATE UNIQUE INDEX IX_DimEmployee_BK ON dwh.DimEmployee (EmployeeId);
GO

/* ---- Unknown members: every dimension gets a -1 row so the fact never has a
        NULL foreign key (late-arriving / missing source data lands here). ------ */
SET IDENTITY_INSERT dwh.DimCustomer ON;
INSERT dwh.DimCustomer (CustomerKey, CustomerId, FirstName, LastName, Email, City, [State], Country, RowHash, RowStartDate, RowEndDate, IsCurrent)
VALUES (-1, -1, N'Unknown', N'Unknown', NULL, NULL, NULL, NULL, 0x00, '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT dwh.DimCustomer OFF;

SET IDENTITY_INSERT dwh.DimTrack ON;
INSERT dwh.DimTrack (TrackKey, TrackId, TrackName, Album, Artist, Genre, MediaType, Composer, Milliseconds, UnitPrice, RowHash)
VALUES (-1, -1, N'Unknown', N'Unknown', N'Unknown', N'Unknown', N'Unknown', NULL, NULL, NULL, 0x00);
SET IDENTITY_INSERT dwh.DimTrack OFF;

SET IDENTITY_INSERT dwh.DimEmployee ON;
INSERT dwh.DimEmployee (EmployeeKey, EmployeeId, FullName, Title, RowHash)
VALUES (-1, -1, N'Unknown', NULL, 0x00);
SET IDENTITY_INSERT dwh.DimEmployee OFF;

INSERT dwh.DimDate (DateKey, [Date], [Year], [Quarter], MonthNo, MonthName, DayNo, WeekdayName, IsWeekend)
VALUES (-1, '1900-01-01', 1900, 1, 1, 'Unknown', 1, 'Unknown', 0);
GO

/* ============================ fact ========================================== */
CREATE TABLE dwh.FactSales (
    FactSalesKey   bigint        NOT NULL IDENTITY(1,1) PRIMARY KEY,
    InvoiceLineId  int           NOT NULL,       -- business key (degenerate)
    InvoiceId      int           NOT NULL,       -- degenerate dimension
    DateKey        int           NOT NULL,
    CustomerKey    int           NOT NULL,
    TrackKey       int           NOT NULL,
    EmployeeKey    int           NOT NULL,
    Quantity       int           NOT NULL,
    UnitPrice      decimal(10,2) NOT NULL,
    ExtendedAmount decimal(12,2) NOT NULL,        -- Quantity * UnitPrice
    LoadedAt       datetime2(0)  NOT NULL,
    CONSTRAINT UQ_FactSales_BK UNIQUE (InvoiceLineId),
    CONSTRAINT FK_FactSales_Date     FOREIGN KEY (DateKey)     REFERENCES dwh.DimDate (DateKey),
    CONSTRAINT FK_FactSales_Customer FOREIGN KEY (CustomerKey) REFERENCES dwh.DimCustomer (CustomerKey),
    CONSTRAINT FK_FactSales_Track    FOREIGN KEY (TrackKey)    REFERENCES dwh.DimTrack (TrackKey),
    CONSTRAINT FK_FactSales_Employee FOREIGN KEY (EmployeeKey) REFERENCES dwh.DimEmployee (EmployeeKey)
);
CREATE INDEX IX_FactSales_Customer ON dwh.FactSales (CustomerKey);
CREATE INDEX IX_FactSales_Track    ON dwh.FactSales (TrackKey);
CREATE INDEX IX_FactSales_Date     ON dwh.FactSales (DateKey);
GO

PRINT 'Schemas stg + dwh created (empty, Unknown members seeded).';
GO
