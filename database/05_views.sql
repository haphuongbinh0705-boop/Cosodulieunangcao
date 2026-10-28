/* =====================================================================
   05_views.sql
   ===================================================================== */
USE FashionRetailDB;
GO

/* Doanh thu theo chi nhánh theo tháng (chỉ tính hóa đơn Hoàn tất) */
CREATE OR ALTER VIEW dbo.vw_BranchRevenueMonthly AS
SELECT b.BranchID, b.BranchName,
       YEAR(i.InvoiceDate)  AS [Year],
       MONTH(i.InvoiceDate) AS [Month],
       COUNT(*)             AS InvoiceCount,
       SUM(i.TotalAmount)   AS Revenue
FROM Invoice i
JOIN Branch b ON b.BranchID = i.BranchID
WHERE i.Status = N'Hoàn tất'
GROUP BY b.BranchID, b.BranchName, YEAR(i.InvoiceDate), MONTH(i.InvoiceDate);
GO

/* Hàng tồn thấp hơn mức tối thiểu -> cần nhập thêm */
CREATE OR ALTER VIEW dbo.vw_LowStock AS
SELECT b.BranchName, p.ProductName, v.SKU, v.Size, v.Color,
       i.Quantity, i.MinStock
FROM Inventory i
JOIN Branch b         ON b.BranchID  = i.BranchID
JOIN ProductVariant v ON v.VariantID = i.VariantID
JOIN Product p        ON p.ProductID = v.ProductID
WHERE i.Quantity <= i.MinStock;
GO

/* Sản phẩm bán chạy + lợi nhuận gộp ước tính */
CREATE OR ALTER VIEW dbo.vw_ProductSales AS
SELECT p.ProductID, p.ProductName, v.SKU,
       SUM(d.Quantity)  AS QtySold,
       SUM(d.LineTotal) AS GrossRevenue,
       SUM(d.LineTotal - d.Quantity * v.CostPrice) AS GrossProfit
FROM InvoiceDetail d
JOIN Invoice i        ON i.InvoiceID = d.InvoiceID AND i.Status = N'Hoàn tất'
JOIN ProductVariant v ON v.VariantID = d.VariantID
JOIN Product p        ON p.ProductID = v.ProductID
GROUP BY p.ProductID, p.ProductName, v.SKU;
GO

/* Tổng quan khách hàng thân thiết */
CREATE OR ALTER VIEW dbo.vw_CustomerLoyalty AS
SELECT c.CustomerID, c.FullName, c.Phone, t.TierName,
       c.Points, c.LifetimePoints,
       COUNT(i.InvoiceID)              AS InvoiceCount,
       ISNULL(SUM(i.TotalAmount), 0)   AS TotalSpent,
       MAX(i.InvoiceDate)              AS LastPurchase,
       nt.TierName                     AS NextTier,
       nt.MinPoints - c.LifetimePoints AS PointsToNextTier
FROM Customer c
JOIN MembershipTier t ON t.TierID = c.TierID
LEFT JOIN Invoice i   ON i.CustomerID = c.CustomerID AND i.Status = N'Hoàn tất'
OUTER APPLY (SELECT TOP 1 TierName, MinPoints
             FROM MembershipTier
             WHERE MinPoints > c.LifetimePoints
             ORDER BY MinPoints) nt
GROUP BY c.CustomerID, c.FullName, c.Phone, t.TierName, c.Points, c.LifetimePoints,
         nt.TierName, nt.MinPoints;
GO

/* Đối soát: điểm trong nhật ký phải khớp với số dư của khách */
CREATE OR ALTER VIEW dbo.vw_PointReconciliation AS
SELECT c.CustomerID, c.FullName, c.Points AS BalanceInCustomer,
       ISNULL(SUM(l.Points), 0) AS BalanceInLedger,
       c.Points - ISNULL(SUM(l.Points), 0) AS Difference
FROM Customer c
LEFT JOIN LoyaltyTransaction l ON l.CustomerID = c.CustomerID
GROUP BY c.CustomerID, c.FullName, c.Points;
GO
