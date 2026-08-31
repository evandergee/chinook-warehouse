/* =============================================================================
   Extract:  dbo (source OLTP)  ->  stg (staging)
   -----------------------------------------------------------------------------
   A full extract every run — staging is a scratch area, always a complete
   snapshot of the source. Track is denormalised here (album / artist / genre /
   media type flattened onto the row) so the dimension load is a straight copy.

   RowHash = SHA-256 of the business attributes. The dimension loads compare
   hashes to decide what actually changed, instead of column-by-column.

   Run:  .\q.ps1 -File sql\02_extract_to_staging.sql
   ============================================================================= */
SET NOCOUNT ON;
GO

TRUNCATE TABLE stg.InvoiceLine;
TRUNCATE TABLE stg.Invoice;
TRUNCATE TABLE stg.Customer;
TRUNCATE TABLE stg.Track;
TRUNCATE TABLE stg.Employee;
GO

INSERT stg.Employee (EmployeeId, FullName, Title, RowHash)
SELECT
    e.EmployeeId,
    CONCAT(e.FirstName, N' ', e.LastName),
    e.Title,
    HASHBYTES('SHA2_256', CONCAT_WS(N'|', e.FirstName, e.LastName, e.Title))
FROM dbo.Employee AS e;
PRINT CONCAT('stg.Employee : ', @@ROWCOUNT);
GO

INSERT stg.Customer (CustomerId, FirstName, LastName, Email, City, [State], Country, SupportRepId, RowHash)
SELECT
    c.CustomerId, c.FirstName, c.LastName, c.Email, c.City, c.[State], c.Country, c.SupportRepId,
    HASHBYTES('SHA2_256', CONCAT_WS(N'|', c.FirstName, c.LastName, c.Email, c.City, c.[State], c.Country))
FROM dbo.Customer AS c;
PRINT CONCAT('stg.Customer : ', @@ROWCOUNT);
GO

INSERT stg.Track (TrackId, TrackName, Album, Artist, Genre, MediaType, Composer, Milliseconds, UnitPrice, RowHash)
SELECT
    t.TrackId,
    t.Name,
    ISNULL(al.Title, N'(no album)'),
    ISNULL(ar.Name,  N'(unknown artist)'),
    ISNULL(g.Name,   N'(no genre)'),
    ISNULL(mt.Name,  N'(unknown)'),
    t.Composer,
    t.Milliseconds,
    t.UnitPrice,
    HASHBYTES('SHA2_256', CONCAT_WS(N'|',
        t.Name, al.Title, ar.Name, g.Name, mt.Name, t.Composer,
        CAST(t.Milliseconds AS nvarchar(20)), CAST(t.UnitPrice AS nvarchar(20))))
FROM dbo.Track AS t
LEFT JOIN dbo.Album     AS al ON al.AlbumId     = t.AlbumId
LEFT JOIN dbo.Artist    AS ar ON ar.ArtistId    = al.ArtistId
LEFT JOIN dbo.Genre     AS g  ON g.GenreId      = t.GenreId
LEFT JOIN dbo.MediaType AS mt ON mt.MediaTypeId = t.MediaTypeId;
PRINT CONCAT('stg.Track    : ', @@ROWCOUNT);
GO

INSERT stg.Invoice (InvoiceId, CustomerId, InvoiceDate)
SELECT i.InvoiceId, i.CustomerId, i.InvoiceDate
FROM dbo.Invoice AS i;
PRINT CONCAT('stg.Invoice  : ', @@ROWCOUNT);
GO

INSERT stg.InvoiceLine (InvoiceLineId, InvoiceId, TrackId, UnitPrice, Quantity)
SELECT il.InvoiceLineId, il.InvoiceId, il.TrackId, il.UnitPrice, il.Quantity
FROM dbo.InvoiceLine AS il;
PRINT CONCAT('stg.InvoiceLine: ', @@ROWCOUNT);
GO

PRINT 'Extract complete.';
GO
