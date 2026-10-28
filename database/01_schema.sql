/* =====================================================================
   01_schema.sql
   Đề tài: Phân tích và thiết kế CSDL quản lý chuỗi cửa hàng bán lẻ
           thời trang và tích điểm khách hàng
   DBMS  : Microsoft SQL Server 2019+
   ===================================================================== */

IF DB_ID(N'FashionRetailDB') IS NOT NULL
BEGIN
    ALTER DATABASE FashionRetailDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE FashionRetailDB;
END
GO
CREATE DATABASE FashionRetailDB;
GO
USE FashionRetailDB;
GO

/* ---------- 1. Chi nhánh & nhân viên ---------- */
CREATE TABLE Branch (
    BranchID    INT IDENTITY(1,1) CONSTRAINT PK_Branch PRIMARY KEY,
    BranchName  NVARCHAR(100) NOT NULL,
    Address     NVARCHAR(200) NOT NULL,
    City        NVARCHAR(60)  NOT NULL,
    Phone       VARCHAR(15)   NULL,
    OpenDate    DATE          NOT NULL DEFAULT (CAST(GETDATE() AS DATE)),
    IsActive    BIT           NOT NULL DEFAULT 1
);

CREATE TABLE Employee (
    EmployeeID  INT IDENTITY(1,1) CONSTRAINT PK_Employee PRIMARY KEY,
    FullName    NVARCHAR(100) NOT NULL,
    Phone       VARCHAR(15)   NULL,
    Position    NVARCHAR(30)  NOT NULL
                CONSTRAINT CK_Employee_Position CHECK (Position IN (N'Quản lý', N'Thu ngân', N'Bán hàng', N'Thủ kho')),
    BranchID    INT NOT NULL CONSTRAINT FK_Employee_Branch REFERENCES Branch(BranchID),
    HireDate    DATE NOT NULL,
    Salary      DECIMAL(18,2) NOT NULL CONSTRAINT CK_Employee_Salary CHECK (Salary >= 0),
    IsActive    BIT NOT NULL DEFAULT 1
);

/* ---------- 2. Sản phẩm ---------- */
CREATE TABLE Category (
    CategoryID  INT IDENTITY(1,1) CONSTRAINT PK_Category PRIMARY KEY,
    CategoryName NVARCHAR(80) NOT NULL,
    ParentID    INT NULL CONSTRAINT FK_Category_Parent REFERENCES Category(CategoryID)
);

CREATE TABLE Product (
    ProductID   INT IDENTITY(1,1) CONSTRAINT PK_Product PRIMARY KEY,
    ProductName NVARCHAR(150) NOT NULL,
    CategoryID  INT NOT NULL CONSTRAINT FK_Product_Category REFERENCES Category(CategoryID),
    Brand       NVARCHAR(60) NULL,
    Description NVARCHAR(500) NULL,
    IsActive    BIT NOT NULL DEFAULT 1
);

-- Mỗi sản phẩm có nhiều biến thể (size/màu) -> đơn vị tồn kho & bán hàng
CREATE TABLE ProductVariant (
    VariantID   INT IDENTITY(1,1) CONSTRAINT PK_Variant PRIMARY KEY,
    ProductID   INT NOT NULL CONSTRAINT FK_Variant_Product REFERENCES Product(ProductID),
    SKU         VARCHAR(30) NOT NULL CONSTRAINT UQ_Variant_SKU UNIQUE,
    Size        VARCHAR(10) NOT NULL,
    Color       NVARCHAR(30) NOT NULL,
    CostPrice   DECIMAL(18,2) NOT NULL CONSTRAINT CK_Variant_Cost CHECK (CostPrice >= 0),
    ListPrice   DECIMAL(18,2) NOT NULL CONSTRAINT CK_Variant_List CHECK (ListPrice >= 0),
    CONSTRAINT UQ_Variant_Combo UNIQUE (ProductID, Size, Color)
);

CREATE TABLE Inventory (
    BranchID    INT NOT NULL CONSTRAINT FK_Inv_Branch REFERENCES Branch(BranchID),
    VariantID   INT NOT NULL CONSTRAINT FK_Inv_Variant REFERENCES ProductVariant(VariantID),
    Quantity    INT NOT NULL CONSTRAINT CK_Inv_Qty CHECK (Quantity >= 0),
    MinStock    INT NOT NULL DEFAULT 5,
    CONSTRAINT PK_Inventory PRIMARY KEY (BranchID, VariantID)
);

/* ---------- 3. Nhập hàng ---------- */
CREATE TABLE Supplier (
    SupplierID  INT IDENTITY(1,1) CONSTRAINT PK_Supplier PRIMARY KEY,
    SupplierName NVARCHAR(120) NOT NULL,
    Phone       VARCHAR(15) NULL,
    Email       VARCHAR(100) NULL,
    Address     NVARCHAR(200) NULL
);

CREATE TABLE PurchaseOrder (
    POID        INT IDENTITY(1,1) CONSTRAINT PK_PO PRIMARY KEY,
    SupplierID  INT NOT NULL CONSTRAINT FK_PO_Supplier REFERENCES Supplier(SupplierID),
    BranchID    INT NOT NULL CONSTRAINT FK_PO_Branch REFERENCES Branch(BranchID),
    OrderDate   DATE NOT NULL DEFAULT (CAST(GETDATE() AS DATE)),
    Status      NVARCHAR(20) NOT NULL DEFAULT N'Chờ nhập'
                CONSTRAINT CK_PO_Status CHECK (Status IN (N'Chờ nhập', N'Đã nhập', N'Đã hủy'))
);

CREATE TABLE PurchaseOrderDetail (
    POID        INT NOT NULL CONSTRAINT FK_POD_PO REFERENCES PurchaseOrder(POID),
    VariantID   INT NOT NULL CONSTRAINT FK_POD_Variant REFERENCES ProductVariant(VariantID),
    Quantity    INT NOT NULL CONSTRAINT CK_POD_Qty CHECK (Quantity > 0),
    UnitCost    DECIMAL(18,2) NOT NULL CONSTRAINT CK_POD_Cost CHECK (UnitCost >= 0),
    CONSTRAINT PK_POD PRIMARY KEY (POID, VariantID)
);

/* ---------- 4. Khách hàng & tích điểm ---------- */
CREATE TABLE MembershipTier (
    TierID          INT IDENTITY(1,1) CONSTRAINT PK_Tier PRIMARY KEY,
    TierName        NVARCHAR(30) NOT NULL CONSTRAINT UQ_Tier_Name UNIQUE,
    MinPoints       INT NOT NULL CONSTRAINT CK_Tier_Min CHECK (MinPoints >= 0),   -- điểm tích lũy tối thiểu
    DiscountPercent DECIMAL(5,2) NOT NULL CONSTRAINT CK_Tier_Disc CHECK (DiscountPercent BETWEEN 0 AND 100),
    PointMultiplier DECIMAL(4,2) NOT NULL CONSTRAINT CK_Tier_Mult CHECK (PointMultiplier >= 1)
);

CREATE TABLE Customer (
    CustomerID  INT IDENTITY(1,1) CONSTRAINT PK_Customer PRIMARY KEY,
    FullName    NVARCHAR(100) NOT NULL,
    Phone       VARCHAR(15) NOT NULL CONSTRAINT UQ_Customer_Phone UNIQUE,
    Email       VARCHAR(100) NULL,
    Gender      NCHAR(3) NULL CONSTRAINT CK_Customer_Gender CHECK (Gender IN (N'Nam', N'Nữ', N'Khác')),
    BirthDate   DATE NULL,
    Address     NVARCHAR(200) NULL,
    TierID      INT NOT NULL CONSTRAINT FK_Customer_Tier REFERENCES MembershipTier(TierID),
    Points      INT NOT NULL DEFAULT 0 CONSTRAINT CK_Customer_Points CHECK (Points >= 0),      -- điểm khả dụng
    LifetimePoints INT NOT NULL DEFAULT 0 CONSTRAINT CK_Customer_LP CHECK (LifetimePoints >= 0), -- điểm tích lũy trọn đời (xét hạng)
    JoinDate    DATE NOT NULL DEFAULT (CAST(GETDATE() AS DATE))
);

CREATE TABLE Promotion (
    PromoID     INT IDENTITY(1,1) CONSTRAINT PK_Promo PRIMARY KEY,
    PromoName   NVARCHAR(120) NOT NULL,
    DiscountPercent DECIMAL(5,2) NOT NULL CONSTRAINT CK_Promo_Disc CHECK (DiscountPercent BETWEEN 0 AND 100),
    CategoryID  INT NULL CONSTRAINT FK_Promo_Category REFERENCES Category(CategoryID), -- NULL = toàn bộ sản phẩm
    StartDate   DATE NOT NULL,
    EndDate     DATE NOT NULL,
    CONSTRAINT CK_Promo_Date CHECK (EndDate >= StartDate)
);

/* ---------- 5. Hóa đơn bán hàng ---------- */
CREATE TABLE Invoice (
    InvoiceID   INT IDENTITY(1,1) CONSTRAINT PK_Invoice PRIMARY KEY,
    InvoiceDate DATETIME NOT NULL DEFAULT GETDATE(),
    BranchID    INT NOT NULL CONSTRAINT FK_Inv_BranchX REFERENCES Branch(BranchID),
    EmployeeID  INT NOT NULL CONSTRAINT FK_Invoice_Employee REFERENCES Employee(EmployeeID),
    CustomerID  INT NULL CONSTRAINT FK_Invoice_Customer REFERENCES Customer(CustomerID), -- NULL = khách vãng lai
    SubTotal        DECIMAL(18,2) NOT NULL DEFAULT 0,
    TierDiscount    DECIMAL(18,2) NOT NULL DEFAULT 0,
    PointsUsed      INT NOT NULL DEFAULT 0,
    PointDiscount   DECIMAL(18,2) NOT NULL DEFAULT 0,
    TotalAmount     DECIMAL(18,2) NOT NULL DEFAULT 0,
    PointsEarned    INT NOT NULL DEFAULT 0,
    PaymentMethod   NVARCHAR(20) NOT NULL DEFAULT N'Tiền mặt'
                    CONSTRAINT CK_Invoice_Pay CHECK (PaymentMethod IN (N'Tiền mặt', N'Thẻ', N'Chuyển khoản', N'Ví điện tử')),
    Status      NVARCHAR(15) NOT NULL DEFAULT N'Nháp'
                CONSTRAINT CK_Invoice_Status CHECK (Status IN (N'Nháp', N'Hoàn tất', N'Đã hủy'))
);

CREATE TABLE InvoiceDetail (
    InvoiceID   INT NOT NULL CONSTRAINT FK_ID_Invoice REFERENCES Invoice(InvoiceID) ON DELETE CASCADE,
    VariantID   INT NOT NULL CONSTRAINT FK_ID_Variant REFERENCES ProductVariant(VariantID),
    Quantity    INT NOT NULL CONSTRAINT CK_ID_Qty CHECK (Quantity > 0),
    UnitPrice   DECIMAL(18,2) NOT NULL CONSTRAINT CK_ID_Price CHECK (UnitPrice >= 0),
    DiscountPercent DECIMAL(5,2) NOT NULL DEFAULT 0 CONSTRAINT CK_ID_Disc CHECK (DiscountPercent BETWEEN 0 AND 100),
    LineTotal   AS (CAST(Quantity * UnitPrice * (1 - DiscountPercent / 100.0) AS DECIMAL(18,2))) PERSISTED,
    CONSTRAINT PK_InvoiceDetail PRIMARY KEY (InvoiceID, VariantID)
);

-- Nhật ký điểm: mọi thay đổi điểm đều được ghi lại để đối soát
CREATE TABLE LoyaltyTransaction (
    TransID     BIGINT IDENTITY(1,1) CONSTRAINT PK_LoyTrans PRIMARY KEY,
    CustomerID  INT NOT NULL CONSTRAINT FK_Loy_Customer REFERENCES Customer(CustomerID),
    InvoiceID   INT NULL CONSTRAINT FK_Loy_Invoice REFERENCES Invoice(InvoiceID),
    Points      INT NOT NULL,                      -- dương = cộng, âm = trừ
    TransType   VARCHAR(10) NOT NULL CONSTRAINT CK_Loy_Type CHECK (TransType IN ('EARN','REDEEM','ADJUST','EXPIRE')),
    CreatedAt   DATETIME NOT NULL DEFAULT GETDATE(),
    Note        NVARCHAR(200) NULL
);
GO
