/* =====================================================================
   06_queries.sql  -  Các truy vấn phân tích nâng cao
   ===================================================================== */
USE FashionRetailDB;
GO

-- Q1. Doanh thu từng chi nhánh theo tháng + doanh thu lũy kế + tăng trưởng so với tháng trước
SELECT BranchName, [Year], [Month], Revenue,
       SUM(Revenue) OVER (PARTITION BY BranchID ORDER BY [Year], [Month]) AS RunningRevenue,
       LAG(Revenue) OVER (PARTITION BY BranchID ORDER BY [Year], [Month]) AS PrevMonth,
       CAST(100.0 * (Revenue - LAG(Revenue) OVER (PARTITION BY BranchID ORDER BY [Year], [Month]))
            / NULLIF(LAG(Revenue) OVER (PARTITION BY BranchID ORDER BY [Year], [Month]), 0) AS DECIMAL(10,2)) AS GrowthPct
FROM vw_BranchRevenueMonthly
ORDER BY BranchName, [Year], [Month];

-- Q2. Top 3 sản phẩm bán chạy nhất tại mỗi chi nhánh (DENSE_RANK)
WITH s AS (
    SELECT i.BranchID, v.ProductID, SUM(d.Quantity) AS Qty,
           DENSE_RANK() OVER (PARTITION BY i.BranchID ORDER BY SUM(d.Quantity) DESC) AS rk
    FROM InvoiceDetail d
    JOIN Invoice i        ON i.InvoiceID = d.InvoiceID AND i.Status = N'Hoàn tất'
    JOIN ProductVariant v ON v.VariantID = d.VariantID
    GROUP BY i.BranchID, v.ProductID
)
SELECT b.BranchName, p.ProductName, s.Qty, s.rk
FROM s
JOIN Branch b  ON b.BranchID  = s.BranchID
JOIN Product p ON p.ProductID = s.ProductID
WHERE s.rk <= 3
ORDER BY b.BranchName, s.rk;

-- Q3. Phân khúc khách hàng theo RFM (Recency - Frequency - Monetary), chia 3 nhóm bằng NTILE
WITH rfm AS (
    SELECT c.CustomerID, c.FullName,
           DATEDIFF(DAY, MAX(i.InvoiceDate), '2026-10-28') AS Recency,
           COUNT(i.InvoiceID)  AS Frequency,
           SUM(i.TotalAmount)  AS Monetary
    FROM Customer c
    JOIN Invoice i ON i.CustomerID = c.CustomerID AND i.Status = N'Hoàn tất'
    GROUP BY c.CustomerID, c.FullName
)
SELECT *,
       NTILE(3) OVER (ORDER BY Recency DESC)  AS R_Score,   -- mua gần đây -> điểm cao
       NTILE(3) OVER (ORDER BY Frequency)     AS F_Score,
       NTILE(3) OVER (ORDER BY Monetary)      AS M_Score
FROM rfm
ORDER BY Monetary DESC;

-- Q4. Khách sắp lên hạng (còn dưới 100 điểm)
SELECT FullName, TierName, LifetimePoints, NextTier, PointsToNextTier
FROM vw_CustomerLoyalty
WHERE NextTier IS NOT NULL AND PointsToNextTier <= 100
ORDER BY PointsToNextTier;

-- Q5. Sinh nhật trong tháng này (để gửi voucher / chăm sóc khách)
SELECT CustomerID, FullName, Phone, BirthDate
FROM Customer
WHERE MONTH(BirthDate) = MONTH('2026-10-28')
ORDER BY DAY(BirthDate);

-- Q6. Sản phẩm chưa phát sinh doanh số (hàng tồn lâu)
SELECT p.ProductName, v.SKU, SUM(inv.Quantity) AS TotalStock
FROM ProductVariant v
JOIN Product p   ON p.ProductID = v.ProductID
JOIN Inventory inv ON inv.VariantID = v.VariantID
WHERE NOT EXISTS (
    SELECT 1
    FROM InvoiceDetail d
    JOIN Invoice i ON i.InvoiceID = d.InvoiceID AND i.Status = N'Hoàn tất'
    WHERE d.VariantID = v.VariantID)
GROUP BY p.ProductName, v.SKU
ORDER BY TotalStock DESC;

-- Q7. Cây danh mục (CTE đệ quy)
WITH tree AS (
    SELECT CategoryID, CategoryName, ParentID, 0 AS Lvl,
           CAST(CategoryName AS NVARCHAR(400)) AS Path
    FROM Category WHERE ParentID IS NULL
    UNION ALL
    SELECT c.CategoryID, c.CategoryName, c.ParentID, t.Lvl + 1,
           CAST(t.Path + N' > ' + c.CategoryName AS NVARCHAR(400))
    FROM Category c JOIN tree t ON c.ParentID = t.CategoryID
)
SELECT Lvl, Path FROM tree ORDER BY Path;

-- Q8. Tồn kho theo chi nhánh dạng bảng chéo (PIVOT)
SELECT SKU, [Fashion Hub Quận 1] AS Q1, [Fashion Hub Cầu Giấy] AS CauGiay, [Fashion Hub Hải Châu] AS HaiChau
FROM (
    SELECT v.SKU, b.BranchName, i.Quantity
    FROM Inventory i
    JOIN ProductVariant v ON v.VariantID = i.VariantID
    JOIN Branch b ON b.BranchID = i.BranchID
) src
PIVOT (SUM(Quantity) FOR BranchName IN ([Fashion Hub Quận 1], [Fashion Hub Cầu Giấy], [Fashion Hub Hải Châu])) pv
ORDER BY SKU;

-- Q9. Hiệu quả khuyến mãi: doanh thu & số lượng của các dòng hàng có giảm giá
SELECT d.DiscountPercent, COUNT(*) AS Lines, SUM(d.Quantity) AS Qty, SUM(d.LineTotal) AS Revenue
FROM InvoiceDetail d
JOIN Invoice i ON i.InvoiceID = d.InvoiceID AND i.Status = N'Hoàn tất'
GROUP BY d.DiscountPercent
ORDER BY d.DiscountPercent DESC;

-- Q10. Đối soát điểm: kết quả phải rỗng nếu dữ liệu nhất quán
SELECT * FROM vw_PointReconciliation WHERE Difference <> 0;

-- Q11. Hiệu suất nhân viên (doanh thu + số hóa đơn)
SELECT e.FullName, b.BranchName, COUNT(*) AS Invoices, SUM(i.TotalAmount) AS Revenue,
       RANK() OVER (ORDER BY SUM(i.TotalAmount) DESC) AS RevenueRank
FROM Invoice i
JOIN Employee e ON e.EmployeeID = i.EmployeeID
JOIN Branch b   ON b.BranchID   = e.BranchID
WHERE i.Status = N'Hoàn tất'
GROUP BY e.FullName, b.BranchName;
GO
