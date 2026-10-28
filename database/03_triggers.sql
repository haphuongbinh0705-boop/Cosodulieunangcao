/* =====================================================================
   03_triggers.sql
   ===================================================================== */
USE FashionRetailDB;
GO

/* ---------- Tự động nâng/hạ hạng khi điểm tích lũy thay đổi ---------- */
CREATE OR ALTER TRIGGER dbo.trg_Customer_AutoTier
ON Customer
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(LifetimePoints)
    BEGIN
        UPDATE c
        SET c.TierID = dbo.fn_GetTierID(c.LifetimePoints)
        FROM Customer c
        JOIN inserted i ON i.CustomerID = c.CustomerID
        WHERE c.TierID <> dbo.fn_GetTierID(c.LifetimePoints);
    END
END
GO

/* ---------- Khóa chi tiết hóa đơn khi hóa đơn không còn ở trạng thái Nháp ---------- */
CREATE OR ALTER TRIGGER dbo.trg_InvoiceDetail_LockCompleted
ON InvoiceDetail
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM (SELECT InvoiceID FROM inserted UNION SELECT InvoiceID FROM deleted) x
        JOIN Invoice i ON i.InvoiceID = x.InvoiceID
        WHERE i.Status <> N'Nháp')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50030, N'Không thể sửa chi tiết của hóa đơn đã hoàn tất hoặc đã hủy.', 1;
    END
END
GO

/* ---------- Nhập kho tự động khi phiếu nhập chuyển sang "Đã nhập" ---------- */
CREATE OR ALTER TRIGGER dbo.trg_PO_ReceiveStock
ON PurchaseOrder
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(Status)
    BEGIN
        MERGE Inventory AS t
        USING (
            SELECT i.BranchID, d.VariantID, SUM(d.Quantity) AS Qty
            FROM inserted i
            JOIN deleted o ON o.POID = i.POID
            JOIN PurchaseOrderDetail d ON d.POID = i.POID
            WHERE i.Status = N'Đã nhập' AND o.Status <> N'Đã nhập'
            GROUP BY i.BranchID, d.VariantID
        ) AS s
        ON t.BranchID = s.BranchID AND t.VariantID = s.VariantID
        WHEN MATCHED THEN
            UPDATE SET t.Quantity = t.Quantity + s.Qty
        WHEN NOT MATCHED THEN
            INSERT (BranchID, VariantID, Quantity) VALUES (s.BranchID, s.VariantID, s.Qty);
    END
END
GO
