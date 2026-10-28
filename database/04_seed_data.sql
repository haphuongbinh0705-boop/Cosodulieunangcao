/* =====================================================================
   04_seed_data.sql  -  Dữ liệu mẫu
   Chạy trên database mới (sau 01, 02, 03) để ID hóa đơn khớp 1..7.
   ===================================================================== */
USE FashionRetailDB;
GO

/* ---------- Hạng thành viên ---------- */
INSERT INTO MembershipTier (TierName, MinPoints, DiscountPercent, PointMultiplier) VALUES
(N'Đồng',       0,   0, 1.0),
(N'Bạc',      100,   3, 1.2),
(N'Vàng',     300,   5, 1.5),
(N'Kim cương',800,   8, 2.0);

/* ---------- Chi nhánh & nhân viên ---------- */
INSERT INTO Branch (BranchName, Address, City, Phone, OpenDate) VALUES
(N'Fashion Hub Quận 1',    N'12 Nguyễn Huệ, Quận 1',     N'TP. Hồ Chí Minh', '02838000001', '2022-03-01'),
(N'Fashion Hub Cầu Giấy',  N'88 Xuân Thủy, Cầu Giấy',    N'Hà Nội',          '02438000002', '2023-06-15'),
(N'Fashion Hub Hải Châu',  N'45 Bạch Đằng, Hải Châu',    N'Đà Nẵng',         '02363000003', '2024-01-20');

INSERT INTO Employee (FullName, Phone, Position, BranchID, HireDate, Salary) VALUES
(N'Nguyễn Văn An',   '0901000001', N'Quản lý',  1, '2022-03-01', 25000000),
(N'Trần Thị Bình',   '0901000002', N'Thu ngân', 1, '2022-04-10', 10000000),
(N'Lê Minh Châu',    '0901000003', N'Quản lý',  2, '2023-06-15', 24000000),
(N'Phạm Thu Dung',   '0901000004', N'Thu ngân', 2, '2023-07-01',  9500000),
(N'Hoàng Quốc Em',   '0901000005', N'Quản lý',  3, '2024-01-20', 23000000),
(N'Đỗ Thanh Phương', '0901000006', N'Thu ngân', 3, '2024-02-05',  9000000);

/* ---------- Danh mục & sản phẩm ---------- */
INSERT INTO Category (CategoryName, ParentID) VALUES
(N'Áo', NULL), (N'Quần', NULL), (N'Váy đầm', NULL), (N'Phụ kiện', NULL);       -- 1..4
INSERT INTO Category (CategoryName, ParentID) VALUES
(N'Áo thun', 1), (N'Áo sơ mi', 1), (N'Quần jean', 2);                         -- 5..7

INSERT INTO Product (ProductName, CategoryID, Brand, Description) VALUES
(N'Áo thun basic cotton',  5, N'Fashion Hub', N'Áo thun cotton 100%, form regular'),
(N'Áo sơ mi Oxford',       6, N'Fashion Hub', N'Sơ mi Oxford dài tay'),
(N'Quần jean slim fit',    7, N'DenimCo',     N'Jean co giãn nhẹ'),
(N'Váy midi hoa nhí',      3, N'Bloom',       N'Váy midi họa tiết hoa'),
(N'Thắt lưng da',          4, N'LeatherX',    N'Thắt lưng da bò thật'),
(N'Mũ lưỡi trai',          4, N'Fashion Hub', N'Mũ lưỡi trai unisex');

INSERT INTO ProductVariant (ProductID, SKU, Size, Color, CostPrice, ListPrice) VALUES
(1, 'AT-BSC-M-TRG', 'M',    N'Trắng',     60000, 199000),
(1, 'AT-BSC-L-DEN', 'L',    N'Đen',       60000, 199000),
(2, 'SM-OXF-M-XAN', 'M',    N'Xanh',     120000, 399000),
(2, 'SM-OXF-L-TRG', 'L',    N'Trắng',    120000, 399000),
(3, 'QJ-SLM-30-XAN','30',   N'Xanh đậm', 200000, 599000),
(3, 'QJ-SLM-32-DEN','32',   N'Đen',      200000, 599000),
(4, 'VM-HOA-S-HNG', 'S',    N'Hồng',     180000, 549000),
(4, 'VM-HOA-M-HNG', 'M',    N'Hồng',     180000, 549000),
(5, 'TL-DA-90-NAU', '90',   N'Nâu',       90000, 299000),
(6, 'ML-LT-F-DEN',  'Free', N'Đen',       30000, 129000);

/* ---------- Tồn kho: mỗi chi nhánh 50 sản phẩm / biến thể ---------- */
INSERT INTO Inventory (BranchID, VariantID, Quantity)
SELECT b.BranchID, v.VariantID, 50
FROM Branch b CROSS JOIN ProductVariant v;

-- Tạo tình huống tồn kho thấp tại chi nhánh Cầu Giấy để demo cảnh báo
UPDATE Inventory SET Quantity = 3 WHERE BranchID = 2 AND VariantID IN (5, 7);

/* ---------- Nhà cung cấp & phiếu nhập ---------- */
INSERT INTO Supplier (SupplierName, Phone, Email, Address) VALUES
(N'Công ty May Việt Tiến',  '02838111111', 'sales@viettien.example', N'Quận Tân Bình, TP.HCM'),
(N'Xưởng Denim Sài Gòn',    '02838222222', 'order@denimsg.example',  N'Quận 12, TP.HCM');

INSERT INTO PurchaseOrder (SupplierID, BranchID, OrderDate) VALUES
(1, 1, '2026-09-01'),
(2, 2, '2026-10-05');

INSERT INTO PurchaseOrderDetail (POID, VariantID, Quantity, UnitCost) VALUES
(1, 1, 30, 60000), (1, 2, 30, 60000),
(2, 5, 20, 200000), (2, 7, 20, 180000);

-- Chuyển phiếu 1 sang "Đã nhập" -> trigger tự cộng tồn kho
UPDATE PurchaseOrder SET Status = N'Đã nhập' WHERE POID = 1;

/* ---------- Khách hàng ---------- */
INSERT INTO Customer (FullName, Phone, Email, Gender, BirthDate, Address, TierID, JoinDate) VALUES
(N'Nguyễn Thị Lan',  '0912000001', 'lan@example.com',  N'Nữ',  '1995-10-12', N'Quận 3, TP.HCM',  1, '2024-01-10'),
(N'Trần Quốc Hưng',  '0912000002', 'hung@example.com', N'Nam', '1990-05-20', N'Quận 7, TP.HCM',  1, '2024-03-22'),
(N'Lê Thu Hà',       '0912000003', 'ha@example.com',   N'Nữ',  '1998-11-02', N'Đống Đa, Hà Nội',1, '2025-02-14'),
(N'Phạm Minh Tuấn',  '0912000004', 'tuan@example.com', N'Nam', '1987-08-30', N'Sơn Trà, Đà Nẵng',1,'2025-05-01'),
(N'Vũ Ngọc Anh',     '0912000005', 'anh@example.com',  N'Nữ',  '2000-10-25', N'Cầu Giấy, Hà Nội',1,'2025-09-09'),
(N'Đặng Hoài Nam',   '0912000006', NULL,               N'Nam', NULL,         NULL,               1, '2026-01-15');

/* ---------- Khuyến mãi ---------- */
INSERT INTO Promotion (PromoName, DiscountPercent, CategoryID, StartDate, EndDate) VALUES
(N'Sale áo thun tháng 10',   20, 5,    '2026-10-01', '2026-10-31'),
(N'Black Friday toàn hệ thống', 15, NULL, '2026-11-20', '2026-11-30');

/* ---------- Hóa đơn (tạo ở trạng thái Nháp rồi chốt bằng procedure) ---------- */
INSERT INTO Invoice (InvoiceDate, BranchID, EmployeeID, CustomerID, PaymentMethod) VALUES
('2026-09-05 10:15', 1, 2, 1,    N'Tiền mặt'),
('2026-09-18 15:40', 1, 2, 2,    N'Thẻ'),
('2026-10-03 11:05', 2, 4, 3,    N'Ví điện tử'),
('2026-10-10 17:30', 3, 6, 4,    N'Chuyển khoản'),
('2026-10-15 09:50', 1, 2, NULL, N'Tiền mặt'),
('2026-10-20 14:25', 2, 4, 1,    N'Thẻ'),
('2026-10-25 19:10', 1, 2, 1,    N'Thẻ');

INSERT INTO InvoiceDetail (InvoiceID, VariantID, Quantity, UnitPrice)
SELECT t.InvoiceID, v.VariantID, t.Qty, v.ListPrice
FROM (VALUES
    (1, 'AT-BSC-M-TRG', 2), (1, 'QJ-SLM-30-XAN', 1),
    (2, 'SM-OXF-M-XAN', 1), (2, 'TL-DA-90-NAU',  1),
    (3, 'VM-HOA-S-HNG', 2), (3, 'ML-LT-F-DEN',   1),
    (4, 'QJ-SLM-32-DEN',3), (4, 'AT-BSC-L-DEN',  2),
    (5, 'AT-BSC-L-DEN', 1),
    (6, 'SM-OXF-L-TRG', 4), (6, 'QJ-SLM-30-XAN', 2),
    (7, 'AT-BSC-M-TRG', 1)
) AS t(InvoiceID, SKU, Qty)
JOIN ProductVariant v ON v.SKU = t.SKU;

-- Chốt lần lượt theo thời gian. Hóa đơn 6: khách 1 đổi 50 điểm.
-- Sau HĐ 6, khách 1 lên hạng Vàng -> HĐ 7 được giảm 5% + nhân điểm 1.5.
EXEC dbo.sp_CheckoutInvoice 1;
EXEC dbo.sp_CheckoutInvoice 2;
EXEC dbo.sp_CheckoutInvoice 3;
EXEC dbo.sp_CheckoutInvoice 4;
EXEC dbo.sp_CheckoutInvoice 5;
EXEC dbo.sp_CheckoutInvoice 6, 50;
EXEC dbo.sp_CheckoutInvoice 7;
GO
