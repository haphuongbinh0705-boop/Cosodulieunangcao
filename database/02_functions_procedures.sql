/* =====================================================================
   02_functions_procedures.sql
   Hàm + Stored Procedure xử lý nghiệp vụ bán hàng & tích điểm

   QUY TẮC TÍCH ĐIỂM (có thể chỉnh trong procedure):
     - Mỗi 10.000đ thanh toán = 1 điểm x hệ số hạng thành viên
     - 1 điểm = 1.000đ khi đổi điểm giảm giá
     - Hạng thành viên xét theo LifetimePoints (điểm tích lũy trọn đời)
   ===================================================================== */
USE FashionRetailDB;
GO

/* ---------- Hàm: xác định hạng theo điểm tích lũy ---------- */
CREATE OR ALTER FUNCTION dbo.fn_GetTierID (@LifetimePoints INT)
RETURNS INT
AS
BEGIN
    RETURN (SELECT TOP 1 TierID
            FROM MembershipTier
            WHERE MinPoints <= @LifetimePoints
            ORDER BY MinPoints DESC);
END
GO

/* ---------- Thủ tục: đăng ký thành viên mới ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_RegisterCustomer
    @FullName  NVARCHAR(100),
    @Phone     VARCHAR(15),
    @Email     VARCHAR(100) = NULL,
    @Gender    NCHAR(3)     = NULL,
    @BirthDate DATE         = NULL,
    @Address   NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM Customer WHERE Phone = @Phone)
        THROW 50020, N'Số điện thoại đã được đăng ký.', 1;

    INSERT INTO Customer (FullName, Phone, Email, Gender, BirthDate, Address, TierID)
    VALUES (@FullName, @Phone, @Email, @Gender, @BirthDate, @Address, dbo.fn_GetTierID(0));

    SELECT SCOPE_IDENTITY() AS NewCustomerID;
END
GO

/* ---------- Thủ tục: chốt hóa đơn (thanh toán) ----------
   Các bước (trong 1 transaction):
     1. Kiểm tra hóa đơn hợp lệ, đang ở trạng thái Nháp
     2. Áp dụng khuyến mãi đang hiệu lực theo ngày hóa đơn
     3. Kiểm tra & trừ tồn kho tại chi nhánh
     4. Tính giảm giá theo hạng + đổi điểm
     5. Cộng điểm, ghi nhật ký điểm, cập nhật hóa đơn
   Hạng thành viên được trigger tự nâng cấp sau khi LifetimePoints đổi.   */
CREATE OR ALTER PROCEDURE dbo.sp_CheckoutInvoice
    @InvoiceID   INT,
    @PointsToUse INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @PointValueVND INT = 1000;     -- 1 điểm = 1.000đ
    DECLARE @VNDPerPoint   INT = 10000;    -- 10.000đ = 1 điểm

    DECLARE @Status NVARCHAR(15), @CustomerID INT, @BranchID INT, @InvDate DATETIME;
    DECLARE @SubTotal DECIMAL(18,2), @TierPct DECIMAL(5,2) = 0, @Mult DECIMAL(4,2) = 1;
    DECLARE @Balance INT = 0, @TierDisc DECIMAL(18,2), @PointDisc DECIMAL(18,2);
    DECLARE @Total DECIMAL(18,2), @Earned INT = 0;

    BEGIN TRY
        BEGIN TRAN;

        SELECT @Status = Status, @CustomerID = CustomerID,
               @BranchID = BranchID, @InvDate = InvoiceDate
        FROM Invoice WITH (UPDLOCK, HOLDLOCK)
        WHERE InvoiceID = @InvoiceID;

        IF @Status IS NULL      THROW 50001, N'Hóa đơn không tồn tại.', 1;
        IF @Status <> N'Nháp'   THROW 50002, N'Hóa đơn đã được xử lý, không thể chốt lại.', 1;
        IF NOT EXISTS (SELECT 1 FROM InvoiceDetail WHERE InvoiceID = @InvoiceID)
            THROW 50003, N'Hóa đơn chưa có sản phẩm.', 1;
        IF @PointsToUse < 0     THROW 50004, N'Số điểm sử dụng không hợp lệ.', 1;
        IF @PointsToUse > 0 AND @CustomerID IS NULL
            THROW 50004, N'Khách vãng lai không thể đổi điểm.', 1;

        -- 2. Áp dụng khuyến mãi (lấy mức giảm cao nhất áp dụng được cho từng dòng)
        UPDATE d
        SET d.DiscountPercent = ISNULL(pm.MaxDisc, 0)
        FROM InvoiceDetail d
        JOIN ProductVariant v ON v.VariantID  = d.VariantID
        JOIN Product p        ON p.ProductID  = v.ProductID
        JOIN Category c       ON c.CategoryID = p.CategoryID
        OUTER APPLY (
            SELECT MAX(pr.DiscountPercent) AS MaxDisc
            FROM Promotion pr
            WHERE CAST(@InvDate AS DATE) BETWEEN pr.StartDate AND pr.EndDate
              AND (pr.CategoryID IS NULL
                   OR pr.CategoryID = c.CategoryID
                   OR pr.CategoryID = c.ParentID)
        ) pm
        WHERE d.InvoiceID = @InvoiceID;

        -- 3. Kiểm tra tồn kho rồi trừ kho
        IF EXISTS (
            SELECT 1
            FROM InvoiceDetail d
            LEFT JOIN Inventory i WITH (UPDLOCK)
                   ON i.BranchID = @BranchID AND i.VariantID = d.VariantID
            WHERE d.InvoiceID = @InvoiceID AND ISNULL(i.Quantity, 0) < d.Quantity)
            THROW 50005, N'Không đủ tồn kho tại chi nhánh cho một hoặc nhiều sản phẩm.', 1;

        UPDATE i
        SET i.Quantity = i.Quantity - d.Quantity
        FROM Inventory i
        JOIN InvoiceDetail d ON d.VariantID = i.VariantID
        WHERE i.BranchID = @BranchID AND d.InvoiceID = @InvoiceID;

        -- 4. Tính tiền
        SELECT @SubTotal = SUM(LineTotal) FROM InvoiceDetail WHERE InvoiceID = @InvoiceID;

        IF @CustomerID IS NOT NULL
            SELECT @TierPct = t.DiscountPercent, @Mult = t.PointMultiplier, @Balance = c.Points
            FROM Customer c WITH (UPDLOCK)
            JOIN MembershipTier t ON t.TierID = c.TierID
            WHERE c.CustomerID = @CustomerID;

        SET @TierDisc = ROUND(@SubTotal * @TierPct / 100.0, 0);

        IF @PointsToUse > @Balance
            THROW 50006, N'Số điểm khả dụng không đủ.', 1;

        SET @PointDisc = @PointsToUse * @PointValueVND;
        IF @PointDisc > @SubTotal - @TierDisc
            THROW 50007, N'Giá trị điểm đổi vượt quá số tiền cần thanh toán.', 1;

        SET @Total = @SubTotal - @TierDisc - @PointDisc;

        IF @CustomerID IS NOT NULL
            SET @Earned = CAST(FLOOR(@Total / @VNDPerPoint * @Mult) AS INT);

        -- 5. Cập nhật hóa đơn, khách hàng, nhật ký điểm
        UPDATE Invoice
        SET SubTotal = @SubTotal, TierDiscount = @TierDisc,
            PointsUsed = @PointsToUse, PointDiscount = @PointDisc,
            TotalAmount = @Total, PointsEarned = @Earned,
            Status = N'Hoàn tất'
        WHERE InvoiceID = @InvoiceID;

        IF @CustomerID IS NOT NULL
        BEGIN
            UPDATE Customer
            SET Points = Points - @PointsToUse + @Earned,
                LifetimePoints = LifetimePoints + @Earned
            WHERE CustomerID = @CustomerID;

            IF @PointsToUse > 0
                INSERT INTO LoyaltyTransaction (CustomerID, InvoiceID, Points, TransType, Note)
                VALUES (@CustomerID, @InvoiceID, -@PointsToUse, 'REDEEM', N'Đổi điểm giảm giá hóa đơn');

            IF @Earned > 0
                INSERT INTO LoyaltyTransaction (CustomerID, InvoiceID, Points, TransType, Note)
                VALUES (@CustomerID, @InvoiceID, @Earned, 'EARN', N'Tích điểm từ hóa đơn');
        END

        COMMIT;

        SELECT @InvoiceID AS InvoiceID, @SubTotal AS SubTotal, @TierDisc AS TierDiscount,
               @PointDisc AS PointDiscount, @Total AS TotalAmount, @Earned AS PointsEarned;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO

/* ---------- Thủ tục: hủy hóa đơn đã hoàn tất (hoàn kho + hoàn điểm) ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_CancelInvoice
    @InvoiceID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(15), @CustomerID INT, @BranchID INT;
    DECLARE @Used INT, @Earned INT, @Balance INT;

    BEGIN TRY
        BEGIN TRAN;

        SELECT @Status = Status, @CustomerID = CustomerID, @BranchID = BranchID,
               @Used = PointsUsed, @Earned = PointsEarned
        FROM Invoice WITH (UPDLOCK, HOLDLOCK)
        WHERE InvoiceID = @InvoiceID;

        IF @Status IS NULL         THROW 50010, N'Hóa đơn không tồn tại.', 1;
        IF @Status <> N'Hoàn tất'  THROW 50011, N'Chỉ hủy được hóa đơn đã hoàn tất.', 1;

        -- Hoàn kho
        UPDATE i
        SET i.Quantity = i.Quantity + d.Quantity
        FROM Inventory i
        JOIN InvoiceDetail d ON d.VariantID = i.VariantID
        WHERE i.BranchID = @BranchID AND d.InvoiceID = @InvoiceID;

        -- Hoàn điểm
        IF @CustomerID IS NOT NULL
        BEGIN
            SELECT @Balance = Points FROM Customer WITH (UPDLOCK) WHERE CustomerID = @CustomerID;
            IF @Balance + @Used - @Earned < 0
                THROW 50012, N'Khách đã dùng hết điểm được tích từ hóa đơn này, không thể hủy.', 1;

            UPDATE Customer
            SET Points = Points + @Used - @Earned,
                LifetimePoints = LifetimePoints - @Earned
            WHERE CustomerID = @CustomerID;

            IF @Used > 0
                INSERT INTO LoyaltyTransaction (CustomerID, InvoiceID, Points, TransType, Note)
                VALUES (@CustomerID, @InvoiceID, @Used, 'ADJUST', N'Hoàn điểm đã đổi do hủy hóa đơn');
            IF @Earned > 0
                INSERT INTO LoyaltyTransaction (CustomerID, InvoiceID, Points, TransType, Note)
                VALUES (@CustomerID, @InvoiceID, -@Earned, 'ADJUST', N'Thu hồi điểm đã tích do hủy hóa đơn');
        END

        UPDATE Invoice SET Status = N'Đã hủy' WHERE InvoiceID = @InvoiceID;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END
GO
