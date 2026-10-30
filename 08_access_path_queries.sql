/* =====================================================================
   08_access_path_queries.sql
   Khai thác dữ liệu bằng SQL DML theo các CON ĐƯỜNG TRUY XUẤT
   trên đồ thị quan hệ (báo cáo mục 9 - 10).
   Ký hiệu cung c1..c19 theo bảng tạo cung (báo cáo mục 8).
   Chạy sau 01 -> 07.
   ===================================================================== */
USE FashionRetailDB;
GO

/* ---------------------------------------------------------------------
   P1: Branch -c4-> Invoice -c18-> InvoiceDetail
   Ý nghĩa: chi nhánh bán được bao nhiêu hóa đơn, bao nhiêu sản phẩm
   trong một khoảng thời gian.
   --------------------------------------------------------------------- */
SELECT b.BranchName,
       COUNT(DISTINCT i.InvoiceID) AS SoHoaDon,
       SUM(d.Quantity)             AS SoLuongBan,
       SUM(d.LineTotal)            AS TienHangSauKM
FROM Branch b
JOIN Invoice i       ON i.BranchID  = b.BranchID AND i.Status = N'Hoàn tất'
JOIN InvoiceDetail d ON d.InvoiceID = i.InvoiceID
WHERE i.InvoiceDate >= '2026-10-01' AND i.InvoiceDate < '2026-11-01'
GROUP BY b.BranchName
ORDER BY TienHangSauKM DESC;
GO

/* ---------------------------------------------------------------------
   P2: Category -c7-> Product -c9-> ProductVariant -c12-> InvoiceDetail
   Ý nghĩa: sản phẩm nào, thuộc danh mục nào bán chạy nhất.
   --------------------------------------------------------------------- */
SELECT c.CategoryName, p.ProductName,
       SUM(d.Quantity)  AS SoLuongBan,
       SUM(d.LineTotal) AS TienHang
FROM Category c
JOIN Product p        ON p.CategoryID = c.CategoryID
JOIN ProductVariant v ON v.ProductID  = p.ProductID
JOIN InvoiceDetail d  ON d.VariantID  = v.VariantID
JOIN Invoice i        ON i.InvoiceID  = d.InvoiceID AND i.Status = N'Hoàn tất'
GROUP BY c.CategoryName, p.ProductName
ORDER BY TienHang DESC;
GO

/* ---------------------------------------------------------------------
   P1 ⋈ P2 (hai chuỗi hội tụ tại nút lá InvoiceDetail)
   Ý nghĩa: bảng chéo doanh số chi nhánh x danh mục.
   --------------------------------------------------------------------- */
SELECT b.BranchName, c.CategoryName,
       SUM(d.Quantity)  AS SoLuongBan,
       SUM(d.LineTotal) AS TienHang
FROM Branch b
JOIN Invoice i        ON i.BranchID   = b.BranchID AND i.Status = N'Hoàn tất'
JOIN InvoiceDetail d  ON d.InvoiceID  = i.InvoiceID
JOIN ProductVariant v ON v.VariantID  = d.VariantID
JOIN Product p        ON p.ProductID  = v.ProductID
JOIN Category c       ON c.CategoryID = p.CategoryID
GROUP BY b.BranchName, c.CategoryName
ORDER BY b.BranchName, TienHang DESC;
GO

/* ---------------------------------------------------------------------
   P3: MembershipTier -c15-> Customer -c16-> Invoice
   Ý nghĩa: mỗi hạng thành viên có bao nhiêu khách, chi tiêu bao nhiêu.
   --------------------------------------------------------------------- */
SELECT t.TierName,
       COUNT(DISTINCT c.CustomerID)  AS SoKhach,
       COUNT(i.InvoiceID)            AS SoHoaDon,
       ISNULL(SUM(i.TotalAmount), 0) AS TongChiTieu,
       CAST(ISNULL(SUM(i.TotalAmount), 0) / NULLIF(COUNT(DISTINCT c.CustomerID), 0)
            AS DECIMAL(18,0))        AS ChiTieuBinhQuanMoiKhach
FROM MembershipTier t
LEFT JOIN Customer c ON c.TierID     = t.TierID
LEFT JOIN Invoice i  ON i.CustomerID = c.CustomerID AND i.Status = N'Hoàn tất'
GROUP BY t.TierID, t.TierName, t.MinPoints
ORDER BY t.MinPoints;
GO

/* ---------------------------------------------------------------------
   P4: Customer -c17-> LoyaltyTransaction   (vào từ nút nghiệp vụ Customer.Phone)
   Ý nghĩa: sổ điểm của một khách, số dư lũy kế sau từng giao dịch.
   --------------------------------------------------------------------- */
DECLARE @Phone VARCHAR(15) = '0912000001';
SELECT c.FullName, l.CreatedAt, l.TransType, l.Points, l.InvoiceID, l.Note,
       SUM(l.Points) OVER (ORDER BY l.CreatedAt, l.TransID
                           ROWS UNBOUNDED PRECEDING) AS SoDuLuyKe
FROM Customer c
JOIN LoyaltyTransaction l ON l.CustomerID = c.CustomerID
WHERE c.Phone = @Phone
ORDER BY l.CreatedAt, l.TransID;
GO

/* ---------------------------------------------------------------------
   P5: Supplier -c13-> PurchaseOrder -c14-> PurchaseOrderDetail
   Ý nghĩa: giá trị hàng đã nhập từ từng nhà cung cấp.
   --------------------------------------------------------------------- */
SELECT s.SupplierName,
       COUNT(DISTINCT po.POID)        AS SoPhieuNhap,
       SUM(d.Quantity)                AS SoLuongNhap,
       SUM(d.Quantity * d.UnitCost)   AS GiaTriNhap
FROM Supplier s
JOIN PurchaseOrder po      ON po.SupplierID = s.SupplierID AND po.Status = N'Đã nhập'
JOIN PurchaseOrderDetail d ON d.POID        = po.POID
GROUP BY s.SupplierName
ORDER BY GiaTriNhap DESC;
GO

/* ---------------------------------------------------------------------
   P6: Branch -c2-> Inventory <-c10- ProductVariant <-c9- Product
   Ý nghĩa: mặt hàng nào ở chi nhánh nào đang dưới mức tồn tối thiểu.
   --------------------------------------------------------------------- */
SELECT b.BranchName, p.ProductName, v.SKU, v.Size, v.Color,
       inv.Quantity AS TonHienTai, inv.MinStock AS TonToiThieu,
       inv.MinStock - inv.Quantity AS CanNhapThem
FROM Branch b
JOIN Inventory inv    ON inv.BranchID = b.BranchID
JOIN ProductVariant v ON v.VariantID  = inv.VariantID
JOIN Product p        ON p.ProductID  = v.ProductID
WHERE inv.Quantity <= inv.MinStock
ORDER BY CanNhapThem DESC;
GO

/* ---------------------------------------------------------------------
   P7 (hai con đường song song Branch -> Invoice):
       P7a: Branch -c4-> Invoice
       P7b: Branch -c1-> Employee -c5-> Invoice
   Ý nghĩa: chi nhánh ghi trên hóa đơn và chi nhánh hiện tại của nhân viên
   lập hóa đơn. Khác nhau = nhân viên đã điều chuyển hoặc bán hỗ trợ.
   Dùng để kiểm tra nhất quán / kiểm soát nội bộ.
   --------------------------------------------------------------------- */
SELECT i.InvoiceID, i.InvoiceDate, e.FullName AS NhanVien,
       bi.BranchName AS ChiNhanhTrenHoaDon,
       be.BranchName AS ChiNhanhCuaNhanVien
FROM Invoice i
JOIN Branch bi   ON bi.BranchID   = i.BranchID
JOIN Employee e  ON e.EmployeeID  = i.EmployeeID
JOIN Branch be   ON be.BranchID   = e.BranchID
WHERE i.BranchID <> e.BranchID;
GO

/* ---------------------------------------------------------------------
   P8 (hai con đường song song Customer -> LoyaltyTransaction):
       P8a: Customer -c17-> LoyaltyTransaction
       P8b: Customer -c16-> Invoice -c19-> LoyaltyTransaction
   Ý nghĩa: điểm phát sinh từ hóa đơn phải ghi cho đúng khách của hóa đơn
   (quy tắc 14). Kết quả PHẢI RỖNG nếu dữ liệu nhất quán.
   --------------------------------------------------------------------- */
SELECT l.TransID, l.InvoiceID, l.TransType, l.Points,
       l.CustomerID AS KhachTrongSoDiem,
       i.CustomerID AS KhachTrenHoaDon
FROM LoyaltyTransaction l
JOIN Invoice i ON i.InvoiceID = l.InvoiceID
WHERE i.CustomerID IS NULL OR i.CustomerID <> l.CustomerID;
GO

/* ---------------------------------------------------------------------
   P9 (ba chuỗi hội tụ tại cặp chi nhánh - biến thể):
       Branch -c3-> PurchaseOrder -c14-> PurchaseOrderDetail <-c11- ProductVariant  (nhập)
       Branch -c4-> Invoice       -c18-> InvoiceDetail       <-c12- ProductVariant  (xuất)
       Branch -c2-> Inventory                                 <-c10- ProductVariant  (tồn)
   Ý nghĩa: báo cáo nhập - xuất - tồn. Tồn đầu suy ra = tồn hiện tại - nhập + bán.
   --------------------------------------------------------------------- */
WITH Nhap AS (
    SELECT po.BranchID, d.VariantID, SUM(d.Quantity) AS SLNhap
    FROM PurchaseOrder po
    JOIN PurchaseOrderDetail d ON d.POID = po.POID
    WHERE po.Status = N'Đã nhập'
    GROUP BY po.BranchID, d.VariantID
), Ban AS (
    SELECT i.BranchID, d.VariantID, SUM(d.Quantity) AS SLBan
    FROM Invoice i
    JOIN InvoiceDetail d ON d.InvoiceID = i.InvoiceID
    WHERE i.Status = N'Hoàn tất'
    GROUP BY i.BranchID, d.VariantID
)
SELECT b.BranchName, v.SKU,
       inv.Quantity - ISNULL(n.SLNhap, 0) + ISNULL(x.SLBan, 0) AS TonDauSuyRa,
       ISNULL(n.SLNhap, 0) AS SLNhap,
       ISNULL(x.SLBan, 0)  AS SLBan,
       inv.Quantity        AS TonCuoi
FROM Inventory inv
JOIN Branch b         ON b.BranchID  = inv.BranchID
JOIN ProductVariant v ON v.VariantID = inv.VariantID
LEFT JOIN Nhap n ON n.BranchID = inv.BranchID AND n.VariantID = inv.VariantID
LEFT JOIN Ban  x ON x.BranchID = inv.BranchID AND x.VariantID = inv.VariantID
ORDER BY b.BranchName, v.SKU;
GO

/* P9 - lệnh UPDATE theo cùng con đường: nâng mức tồn tối thiểu lên 10
   cho các mặt hàng đã bán từ 2 sản phẩm trở lên tại chi nhánh.
   Bọc trong transaction và ROLLBACK để chạy thử không làm đổi dữ liệu mẫu;
   đổi ROLLBACK thành COMMIT nếu muốn lưu.                                  */
BEGIN TRANSACTION;
    UPDATE inv
    SET inv.MinStock = 10
    FROM Inventory inv
    JOIN (SELECT i.BranchID, d.VariantID
          FROM Invoice i
          JOIN InvoiceDetail d ON d.InvoiceID = i.InvoiceID
          WHERE i.Status = N'Hoàn tất'
          GROUP BY i.BranchID, d.VariantID
          HAVING SUM(d.Quantity) >= 2) x
      ON x.BranchID = inv.BranchID AND x.VariantID = inv.VariantID
    WHERE inv.MinStock < 10;
    SELECT @@ROWCOUNT AS SoDongDuocCapNhat;
ROLLBACK TRANSACTION;
GO

/* ---------------------------------------------------------------------
   P10: Category -c8-> Promotion  kết hợp  Category -c7-> Product -c9-> ProductVariant -c12-> InvoiceDetail
   Ý nghĩa: hiệu quả từng chương trình khuyến mãi (khớp cách tính của
   sp_CheckoutInvoice: KM áp cho danh mục, danh mục cha, hoặc toàn sàn).
   --------------------------------------------------------------------- */
SELECT pr.PromoName, pr.DiscountPercent, pr.StartDate, pr.EndDate,
       COUNT(DISTINCT i.InvoiceID) AS SoHoaDon,
       ISNULL(SUM(d.Quantity), 0)  AS SoLuongBan,
       ISNULL(SUM(d.LineTotal), 0) AS TienHangSauKM
FROM Promotion pr
LEFT JOIN (InvoiceDetail d
           JOIN Invoice i        ON i.InvoiceID  = d.InvoiceID AND i.Status = N'Hoàn tất'
           JOIN ProductVariant v ON v.VariantID  = d.VariantID
           JOIN Product p        ON p.ProductID  = v.ProductID
           JOIN Category c       ON c.CategoryID = p.CategoryID)
  ON  d.DiscountPercent > 0
  AND CAST(i.InvoiceDate AS DATE) BETWEEN pr.StartDate AND pr.EndDate
  AND (pr.CategoryID IS NULL OR pr.CategoryID = c.CategoryID OR pr.CategoryID = c.ParentID)
GROUP BY pr.PromoID, pr.PromoName, pr.DiscountPercent, pr.StartDate, pr.EndDate
ORDER BY pr.StartDate;
GO

/* ---------------------------------------------------------------------
   P11: Category -c6-> Category (cung đệ quy)  rồi  -c7-> Product
   Ý nghĩa: cây danh mục nhiều cấp và số sản phẩm ở mỗi nút.
   --------------------------------------------------------------------- */
WITH Tree AS (
    SELECT CategoryID, CategoryName, ParentID, 0 AS Cap,
           CAST(CategoryName AS NVARCHAR(400)) AS DuongDan
    FROM Category
    WHERE ParentID IS NULL
    UNION ALL
    SELECT c.CategoryID, c.CategoryName, c.ParentID, t.Cap + 1,
           CAST(t.DuongDan + N' > ' + c.CategoryName AS NVARCHAR(400))
    FROM Category c
    JOIN Tree t ON c.ParentID = t.CategoryID
)
SELECT t.DuongDan, t.Cap, COUNT(p.ProductID) AS SoSanPham
FROM Tree t
LEFT JOIN Product p ON p.CategoryID = t.CategoryID
GROUP BY t.DuongDan, t.Cap
ORDER BY t.DuongDan;
GO

/* ---------------------------------------------------------------------
   P12: Branch -c1-> Employee -c5-> Invoice
   Ý nghĩa: hiệu suất bán hàng của nhân viên, xếp hạng trong chi nhánh.
   --------------------------------------------------------------------- */
SELECT b.BranchName, e.FullName, e.Position,
       COUNT(i.InvoiceID)            AS SoHoaDon,
       ISNULL(SUM(i.TotalAmount), 0) AS DoanhThu,
       RANK() OVER (PARTITION BY b.BranchID
                    ORDER BY ISNULL(SUM(i.TotalAmount), 0) DESC) AS HangTrongChiNhanh
FROM Branch b
JOIN Employee e     ON e.BranchID   = b.BranchID
LEFT JOIN Invoice i ON i.EmployeeID = e.EmployeeID AND i.Status = N'Hoàn tất'
GROUP BY b.BranchID, b.BranchName, e.EmployeeID, e.FullName, e.Position
ORDER BY b.BranchName, HangTrongChiNhanh;
GO
