/* =====================================================================
   07_indexes_security.sql  -  Tối ưu truy vấn, phân quyền, sao lưu
   ===================================================================== */
USE FashionRetailDB;
GO

/* ---------- Chỉ mục (index) ---------- */
-- Tra cứu hóa đơn theo chi nhánh + thời gian (báo cáo doanh thu)
CREATE NONCLUSTERED INDEX IX_Invoice_Branch_Date
    ON Invoice (BranchID, InvoiceDate) INCLUDE (TotalAmount, Status);

-- Lịch sử mua hàng của khách
CREATE NONCLUSTERED INDEX IX_Invoice_Customer
    ON Invoice (CustomerID, InvoiceDate) INCLUDE (TotalAmount, Status);

-- Thống kê sản phẩm bán ra
CREATE NONCLUSTERED INDEX IX_InvoiceDetail_Variant
    ON InvoiceDetail (VariantID) INCLUDE (Quantity, LineTotal);

-- Sổ điểm của khách
CREATE NONCLUSTERED INDEX IX_Loyalty_Customer
    ON LoyaltyTransaction (CustomerID, CreatedAt);

-- Cảnh báo tồn kho thấp (chỉ lập chỉ mục các dòng cần chú ý -> filtered index)
CREATE NONCLUSTERED INDEX IX_Inventory_Low
    ON Inventory (BranchID, VariantID) INCLUDE (Quantity, MinStock)
    WHERE Quantity <= 10;
GO

/* ---------- Phân quyền theo vai trò ---------- */
CREATE ROLE role_cashier;      -- thu ngân: bán hàng, tra cứu khách
CREATE ROLE role_manager;      -- quản lý: xem báo cáo, quản lý kho
CREATE ROLE role_analyst;      -- phân tích: chỉ đọc các view
GO

GRANT SELECT ON Product, ProductVariant, Inventory, Customer, MembershipTier, Promotion TO role_cashier;
GRANT SELECT, INSERT ON Invoice TO role_cashier;
GRANT SELECT, INSERT ON InvoiceDetail TO role_cashier;
GRANT EXECUTE ON dbo.sp_CheckoutInvoice  TO role_cashier;
GRANT EXECUTE ON dbo.sp_RegisterCustomer TO role_cashier;

GRANT SELECT, INSERT, UPDATE ON Inventory, PurchaseOrder, PurchaseOrderDetail TO role_manager;
GRANT SELECT ON SCHEMA::dbo TO role_manager;
GRANT EXECUTE ON dbo.sp_CancelInvoice TO role_manager;

GRANT SELECT ON dbo.vw_BranchRevenueMonthly, dbo.vw_LowStock, dbo.vw_ProductSales,
                dbo.vw_CustomerLoyalty, dbo.vw_PointReconciliation TO role_analyst;
GO

/* ---------- Sao lưu / phục hồi (chỉnh đường dẫn cho phù hợp máy của bạn) ---------- */
-- BACKUP DATABASE FashionRetailDB TO DISK = N'C:\Backup\FashionRetailDB_full.bak' WITH INIT, COMPRESSION;
-- BACKUP LOG      FashionRetailDB TO DISK = N'C:\Backup\FashionRetailDB_log.trn';
-- RESTORE DATABASE FashionRetailDB FROM DISK = N'C:\Backup\FashionRetailDB_full.bak' WITH REPLACE;
GO
