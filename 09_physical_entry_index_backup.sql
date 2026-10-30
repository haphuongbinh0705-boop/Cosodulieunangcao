/* =====================================================================
   09_physical_entry_index_backup.sql
   Bổ sung cài đặt CSDL vật lý (báo cáo mục 11):
     1. Ràng buộc khóa dự tuyển còn thiếu
     2. Nonclustered index cho NÚT VÀO và cho các cung (khóa ngoại)
     3. Explicit transaction: thủ tục chuyển kho giữa hai chi nhánh
     4. Chiến lược sao lưu (Full / Differential / Log)
   Chạy sau 01 -> 08.
   ===================================================================== */
USE FashionRetailDB;
GO

/* ---------- 1. Khóa dự tuyển: mỗi hạng có ngưỡng điểm riêng ---------- */
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE name = 'UQ_Tier_MinPoints')
    ALTER TABLE MembershipTier ADD CONSTRAINT UQ_Tier_MinPoints UNIQUE (MinPoints);
GO

/* ---------- 2a. Index cho nút vào j(n) = 1 ----------
   Khóa chính (clustered) đã có sẵn; bổ sung index theo cột hay dùng để
   bắt đầu truy xuất.                                                     */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Branch_City')
    CREATE NONCLUSTERED INDEX IX_Branch_City ON Branch (City) INCLUDE (BranchName, IsActive);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Category_Parent')
    CREATE NONCLUSTERED INDEX IX_Category_Parent ON Category (ParentID) INCLUDE (CategoryName);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Supplier_Name')
    CREATE NONCLUSTERED INDEX IX_Supplier_Name ON Supplier (SupplierName);
-- MembershipTier(MinPoints): đã có index qua UQ_Tier_MinPoints, phục vụ fn_GetTierID
-- Nút vào nghiệp vụ: Customer(Phone) và ProductVariant(SKU) đã có index qua
-- UQ_Customer_Phone và UQ_Variant_SKU (tạo trong 01_schema.sql).
GO

/* ---------- 2b. Index cho các cung (khóa ngoại) chưa có index ----------
   SQL Server không tự tạo index cho khóa ngoại. Mỗi cung cần index ở
   phía nút cuối để phép kết đi theo con đường truy xuất dùng index seek. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Employee_Branch')      -- c1
    CREATE NONCLUSTERED INDEX IX_Employee_Branch ON Employee (BranchID) INCLUDE (FullName, Position);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Inventory_Variant')    -- c10
    CREATE NONCLUSTERED INDEX IX_Inventory_Variant ON Inventory (VariantID) INCLUDE (Quantity, MinStock);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PO_Branch')            -- c3
    CREATE NONCLUSTERED INDEX IX_PO_Branch ON PurchaseOrder (BranchID, OrderDate) INCLUDE (Status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PO_Supplier')          -- c13
    CREATE NONCLUSTERED INDEX IX_PO_Supplier ON PurchaseOrder (SupplierID) INCLUDE (Status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Invoice_Employee')     -- c5
    CREATE NONCLUSTERED INDEX IX_Invoice_Employee ON Invoice (EmployeeID) INCLUDE (TotalAmount, Status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Product_Category')     -- c7
    CREATE NONCLUSTERED INDEX IX_Product_Category ON Product (CategoryID) INCLUDE (ProductName);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Promotion_Category')   -- c8
    CREATE NONCLUSTERED INDEX IX_Promotion_Category ON Promotion (CategoryID, StartDate, EndDate) INCLUDE (DiscountPercent);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_POD_Variant')          -- c11
    CREATE NONCLUSTERED INDEX IX_POD_Variant ON PurchaseOrderDetail (VariantID) INCLUDE (Quantity, UnitCost);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Customer_Tier')        -- c15
    CREATE NONCLUSTERED INDEX IX_Customer_Tier ON Customer (TierID);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Loyalty_Invoice')      -- c19
    CREATE NONCLUSTERED INDEX IX_Loyalty_Invoice ON LoyaltyTransaction (InvoiceID) WHERE InvoiceID IS NOT NULL;
-- Đã có từ 07_indexes_security.sql: c4 IX_Invoice_Branch_Date, c16 IX_Invoice_Customer,
-- c12 IX_InvoiceDetail_Variant, c17 IX_Loyalty_Customer.
-- c2, c9, c14, c18 đã được phủ bởi khóa chính / UNIQUE có cột đầu là khóa ngoại.
GO

/* ---------- 3. Explicit transaction: chuyển kho giữa hai chi nhánh ----------
   Hai thao tác (trừ kho nguồn, cộng kho đích) phải cùng thành công hoặc
   cùng bị hủy. UPDLOCK/HOLDLOCK khóa dòng tồn kho nguồn, tránh hai quầy
   cùng rút một lượng hàng.                                                */
CREATE OR ALTER PROCEDURE dbo.sp_TransferStock
    @FromBranchID INT,
    @ToBranchID   INT,
    @VariantID    INT,
    @Quantity     INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 50040, N'Số lượng chuyển phải lớn hơn 0.', 1;
    IF @FromBranchID = @ToBranchID
        THROW 50041, N'Chi nhánh nguồn và đích phải khác nhau.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Ton INT;
        SELECT @Ton = Quantity
        FROM Inventory WITH (UPDLOCK, HOLDLOCK)
        WHERE BranchID = @FromBranchID AND VariantID = @VariantID;

        IF @Ton IS NULL OR @Ton < @Quantity
            THROW 50042, N'Chi nhánh nguồn không đủ hàng để chuyển.', 1;

        UPDATE Inventory
        SET Quantity = Quantity - @Quantity
        WHERE BranchID = @FromBranchID AND VariantID = @VariantID;

        IF EXISTS (SELECT 1 FROM Inventory WITH (UPDLOCK, HOLDLOCK)
                   WHERE BranchID = @ToBranchID AND VariantID = @VariantID)
            UPDATE Inventory
            SET Quantity = Quantity + @Quantity
            WHERE BranchID = @ToBranchID AND VariantID = @VariantID;
        ELSE
            INSERT INTO Inventory (BranchID, VariantID, Quantity)
            VALUES (@ToBranchID, @VariantID, @Quantity);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

GRANT EXECUTE ON dbo.sp_TransferStock TO role_manager;
GO

/* Kịch bản demo:
   EXEC dbo.sp_TransferStock @FromBranchID = 1, @ToBranchID = 2, @VariantID = 5, @Quantity = 10;  -- thành công
   EXEC dbo.sp_TransferStock @FromBranchID = 2, @ToBranchID = 1, @VariantID = 7, @Quantity = 99;  -- lỗi 50042, ROLLBACK
   SELECT * FROM Inventory WHERE VariantID IN (5, 7) ORDER BY VariantID, BranchID;               */

/* ---------- 4. Chiến lược sao lưu ----------
   - Recovery model FULL để sao lưu được nhật ký giao dịch.
   - Full backup: Chủ nhật 23:00 hằng tuần.
   - Differential backup: 23:00 các ngày còn lại.
   - Log backup: 15 phút/lần trong giờ mở cửa (mất tối đa 15 phút dữ liệu).
   - Kiểm tra bản sao lưu bằng RESTORE VERIFYONLY; giữ bản sao ở máy khác.
   Chỉ ghi tên file -> SQL Server lưu vào thư mục backup mặc định của instance.
   Bản Express không có SQL Server Agent: lập lịch bằng Windows Task Scheduler + sqlcmd. */
USE master;
GO
ALTER DATABASE FashionRetailDB SET RECOVERY FULL;
GO
BACKUP DATABASE FashionRetailDB TO DISK = N'FashionRetailDB_full.bak'
    WITH INIT, CHECKSUM, NAME = N'FashionRetailDB - Full';
GO
BACKUP DATABASE FashionRetailDB TO DISK = N'FashionRetailDB_diff.bak'
    WITH DIFFERENTIAL, INIT, CHECKSUM, NAME = N'FashionRetailDB - Differential';
GO
BACKUP LOG FashionRetailDB TO DISK = N'FashionRetailDB_log.trn'
    WITH INIT, CHECKSUM, NAME = N'FashionRetailDB - Log';
GO
RESTORE VERIFYONLY FROM DISK = N'FashionRetailDB_full.bak' WITH CHECKSUM;
GO

/* Quy trình phục hồi khi có sự cố (chạy tay, KHÔNG chạy cùng script):
   RESTORE DATABASE FashionRetailDB FROM DISK = N'FashionRetailDB_full.bak' WITH NORECOVERY, REPLACE;
   RESTORE DATABASE FashionRetailDB FROM DISK = N'FashionRetailDB_diff.bak' WITH NORECOVERY;
   RESTORE LOG      FashionRetailDB FROM DISK = N'FashionRetailDB_log.trn'  WITH RECOVERY;      */
