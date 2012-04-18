﻿CREATE PROCEDURE dbo.TPW_SERVICE_FAULT_TASK
(
	@inPJob_ID			INT,
	@inTask_ID			SMALLINT,
	@inError_Message	NVARCHAR(1024)
)
AS
	SET NOCOUNT ON;
	DECLARE	@tReturn	INT;

	IF @inError_Message IS NULL
		SET	@inError_Message = N'';

	UPDATE	TPW_TASK
	SET
		END_TIME		= GETDATE(),
		ERROR_MESSAGE	= @inError_Message
	WHERE
			END_TIME	IS NULL
		AND TASK_ID		= @inTask_ID
		AND PJOB_ID		= @inPJob_ID;

	SET	@inError_Message = LEFT(N'[Task_ID=' + CAST(@inTask_ID AS NVARCHAR(10)) + N']' + @inError_Message, 1024);

	EXEC @tReturn = TPW_SERVICE_ON_PJOB_EVENT @inPJob_ID, N'FAULT', 0, 1, @inError_Message;

	RETURN @tReturn;