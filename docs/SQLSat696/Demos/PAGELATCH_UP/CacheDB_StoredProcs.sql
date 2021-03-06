-- Sample code inspired by the contributions from the bwin team (https://blogs.msdn.microsoft.com/sqlcat/2016/10/26/how-bwin-is-using-sql-server-2016-in-memory-oltp-to-achieve-unprecedented-performance-and-scale/)
-- The bwin team had provided the scripts here: http://www.mrc.at/Files/CacheDB.zip

USE pfscontention
GO
/****** Object:  StoredProcedure [dbo].[GetCacheItem]    Script Date: 8/16/2017 9:35:15 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[GetCacheItem]
    @Key nvarchar(256),
    @Value varbinary(max) OUT
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS 
BEGIN ATOMIC WITH
(
    TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english'
)         

    DECLARE @IsSlidingExpiration BIT = 0
    DECLARE @SlidingIntervalInSeconds INT = 0;

    SELECT 
        @Value = [Value], 
        @IsSlidingExpiration = [IsSlidingExpiration],
        @SlidingIntervalInSeconds = [SlidingIntervalInSeconds]
    FROM  
		dbo.CacheItems
    WHERE 
		[Key] = @Key;

    -- Refresh Expiration if this item has sliding expiration set
    IF (@@ROWCOUNT > 0) AND (@IsSlidingExpiration = 1)
    BEGIN
		BEGIN TRY
			/*UPDATE dbo.CacheItems
			SET [Expiration] = DATEADD(SECOND, @SlidingIntervalInSeconds, GETUTCDATE())*/
			INSERT INTO [dbo].[CacheItems_Expiration] ([Key], [Expiration])
			VALUES (@Key, DATEADD(SECOND, @SlidingIntervalInSeconds, GETUTCDATE()))
        END TRY
		BEGIN CATCH -- do not throw an exception if it's caused by the optimistic concurrency control paradigm
            IF ERROR_NUMBER() NOT IN (41301, 41302, 41305, 41325) 
            THROW
        END CATCH

    END   
    RETURN 0
END


GO
/****** Object:  StoredProcedure [dbo].[RemoveCacheItem]    Script Date: 8/16/2017 9:35:15 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[RemoveCacheItem]
    @Key NVARCHAR(256),
    @Value VARBINARY(MAX) OUT
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS 
BEGIN ATOMIC WITH
(
    TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english'
)         
       
    SELECT @Value = [Value] FROM dbo.CacheItems
    WHERE [Key] = @Key;
    
    DELETE dbo.CacheItems WHERE [Key] = @Key
	DELETE dbo.CacheItems_Expiration WHERE @Key = [Key]

    --RETURN @Value;
	RETURN 0;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            
END



GO
/****** Object:  StoredProcedure [dbo].[SetCacheItem]    Script Date: 8/16/2017 9:35:15 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[SetCacheItem]
    @Key NVARCHAR(256),
    @Value VARBINARY(MAX),
    @Expiration DATETIME2(2) = NULL,
    @IsSlidingExpiration BIT = 0,
    @SlidingIntervalInSeconds INT = NULL
WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS 
BEGIN ATOMIC WITH
(
    TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english'
)         

    DECLARE @NewExpiration DATETIME2(2) = @Expiration

    IF @IsSlidingExpiration = 1
	BEGIN
        SET @NewExpiration = DATEADD(SECOND, @SlidingIntervalInSeconds, GETUTCDATE())
	END

	IF (@NewExpiration='9999-12-31 23:59:59.99')
	BEGIN
		 SET @NewExpiration = DATEADD(DAY, 1, GETUTCDATE())
	END

    DELETE dbo.CacheItems WHERE @Key = [Key]
	DELETE dbo.CacheItems_Expiration WHERE @Key = [Key]

    INSERT INTO dbo.CacheItems ([Key], [Value], [IsSlidingExpiration], [SlidingIntervalInSeconds])
    VALUES (@Key, @Value, @IsSlidingExpiration, @SlidingIntervalInSeconds)

	INSERT INTO [dbo].[CacheItems_Expiration] ([Key], [Expiration])
	VALUES (@Key,@NewExpiration)

    RETURN 0
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            
END


GO
/****** Object:  StoredProcedure [dbo].[DeleteExpiredCacheItems]    Script Date: 8/16/2017 9:35:15 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[DeleteExpiredCacheItems]
--WITH NATIVE_COMPILATION, SCHEMABINDING, EXECUTE AS OWNER
AS
BEGIN
--BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
	
    DECLARE @CurrentTimeWithGracePeriod AS DATETIME2(2) = DATEADD(MINUTE, -1, GETUTCDATE())  -- Grace period of 1 minute included

	/*insert into #temp select [KEY] from [dbo].[CacheItems_Expiration] 
	group by [KEY]
	having max([Expiration]) < @CurrentTimeWithGracePeriod
	drop table #temp
	*/
	
	BEGIN TRY
		DELETE top (1000000) [dbo].[CacheItems_Expiration] WHERE [Expiration] < @CurrentTimeWithGracePeriod
		DELETE top (100000) [dbo].[CacheItems] where [Key] not in (select [Key] from [dbo].[CacheItems_Expiration])

		while (@@rowcount > 0)
			begin
				DELETE top (1000000) [dbo].[CacheItems_Expiration] WHERE [Expiration] < @CurrentTimeWithGracePeriod

				DELETE top (100000) [dbo].[CacheItems] where [Key] not in (select [Key] from [dbo].[CacheItems_Expiration])
			end
	END TRY
	BEGIN CATCH
      IF ERROR_NUMBER() NOT IN (41302,41305,41325,41301)
		  BEGIN
				  --SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
				  THROW;
		  END 
    END CATCH
END
GO

GRANT EXECUTE ON SetCacheItem TO nonadmin
GRANT EXECUTE ON GetCacheItem TO nonadmin
GRANT EXECUTE ON RemoveCacheItem TO nonadmin
GRANT EXECUTE ON DeleteExpiredCacheItems TO nonadmin

/*
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
SOFTWARE. 

This sample code is not supported under any Microsoft standard support program or service.  
The entire risk arising out of the use or performance of the sample scripts and documentation remains with you.  
In no event shall Microsoft, its authors, or anyone else involved in the creation, production, or delivery of the scripts 
be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, 
business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability 
to use the sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages. 
*/