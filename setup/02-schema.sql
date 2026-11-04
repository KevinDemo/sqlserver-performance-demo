-- Schema for Harbour Freight Couriers, a fictional courier company.
USE HarbourDemo;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE dbo.Zones
(
    ZoneId     INT          NOT NULL CONSTRAINT PK_Zones PRIMARY KEY,
    ZoneCode   VARCHAR(10)  NOT NULL,
    ZoneName   NVARCHAR(60) NOT NULL,
    BaseRate   DECIMAL(9,2) NOT NULL
);

CREATE TABLE dbo.Customers
(
    CustomerId   INT           NOT NULL CONSTRAINT PK_Customers PRIMARY KEY,
    AccountCode  VARCHAR(12)   NOT NULL,
    CustomerName NVARCHAR(100) NOT NULL,
    HomeZoneId   INT           NOT NULL CONSTRAINT FK_Customers_Zones REFERENCES dbo.Zones (ZoneId),
    CreatedUtc   DATETIME2(0)  NOT NULL
);

CREATE TABLE dbo.Drivers
(
    DriverId    INT          NOT NULL CONSTRAINT PK_Drivers PRIMARY KEY,
    DriverCode  VARCHAR(10)  NOT NULL,
    DisplayName NVARCHAR(60) NOT NULL,
    VehicleType VARCHAR(10)  NOT NULL, -- Bike, Car, Van, Truck
    HomeZoneId  INT          NOT NULL CONSTRAINT FK_Drivers_Zones REFERENCES dbo.Zones (ZoneId),
    IsActive    BIT          NOT NULL
);

CREATE TABLE dbo.Jobs
(
    JobId          INT           NOT NULL CONSTRAINT PK_Jobs PRIMARY KEY,
    CustomerId     INT           NOT NULL CONSTRAINT FK_Jobs_Customers REFERENCES dbo.Customers (CustomerId),
    DriverId       INT           NULL     CONSTRAINT FK_Jobs_Drivers REFERENCES dbo.Drivers (DriverId),
    PickupZoneId   INT           NOT NULL CONSTRAINT FK_Jobs_PickupZone REFERENCES dbo.Zones (ZoneId),
    DeliveryZoneId INT           NOT NULL CONSTRAINT FK_Jobs_DeliveryZone REFERENCES dbo.Zones (ZoneId),
    JobStatus      TINYINT       NOT NULL, -- 0 Booked, 1 Despatched, 2 PickedUp, 3 Delivered, 4 Cancelled
    ServiceLevel   CHAR(3)       NOT NULL, -- STD, EXP, ONT
    BookedUtc      DATETIME2(0)  NOT NULL,
    DeliveredUtc   DATETIME2(0)  NULL,
    RatedAmount    DECIMAL(9,2)  NULL,
    RatedUtc       DATETIME2(0)  NULL,
    Reference      VARCHAR(30)   NULL,
    Notes          NVARCHAR(200) NULL
);
-- Single-column indexes of the kind that build up over the years. The scenarios add or replace others.
CREATE INDEX IX_Jobs_BookedUtc ON dbo.Jobs (BookedUtc);
CREATE INDEX IX_Jobs_CustomerId ON dbo.Jobs (CustomerId);

CREATE TABLE dbo.Consignments
(
    ConsignmentId     INT           NOT NULL CONSTRAINT PK_Consignments PRIMARY KEY,
    JobId             INT           NOT NULL CONSTRAINT FK_Consignments_Jobs REFERENCES dbo.Jobs (JobId),
    ConsignmentNumber VARCHAR(20)   NOT NULL,
    WeightKg          DECIMAL(7,2)  NOT NULL,
    Items             SMALLINT      NOT NULL,
    PodSignedBy       NVARCHAR(60)  NULL,
    PodUtc            DATETIME2(0)  NULL,
    LastUpdatedUtc    DATETIME2(0)  NOT NULL
);
CREATE UNIQUE INDEX UX_Consignments_Number ON dbo.Consignments (ConsignmentNumber);
CREATE INDEX IX_Consignments_JobId ON dbo.Consignments (JobId);

CREATE TABLE dbo.JobEvents
(
    JobEventId BIGINT       NOT NULL CONSTRAINT PK_JobEvents PRIMARY KEY,
    JobId      INT          NOT NULL CONSTRAINT FK_JobEvents_Jobs REFERENCES dbo.Jobs (JobId),
    EventType  TINYINT      NOT NULL, -- same values as JobStatus
    EventUtc   DATETIME2(0) NOT NULL,
    DriverId   INT          NULL,
    Detail     VARCHAR(40)  NULL
);
CREATE INDEX IX_JobEvents_JobId ON dbo.JobEvents (JobId);
GO
