CREATE OR REPLACE PACKAGE XYZ.TPW_SERVICE IS

----------------------------------------------------------------------------------------------------
--
--	Copyright 2012 Abel Cheng
--	This source code is subject to terms and conditions of the Apache License, Version 2.0.
--	See http://www.apache.org/licenses/LICENSE-2.0.
--	All other rights reserved.
--	You must not remove this notice, or any other, from this software.
--
--	Original Author:	Abel Cheng <abelcys@gmail.com>
--	Created Date:		2012-03-23
--	Primary Host:		http://dbParallel.codeplex.com
--	Change Log:
--	Author				Date			Comment
--
--
--
--
--	(Keep clean code rather than complicated code plus long comments.)
--
----------------------------------------------------------------------------------------------------


TYPE Int_Array		IS TABLE OF PLS_INTEGER INDEX BY PLS_INTEGER;
TYPE Rowid_Array	IS TABLE OF UROWID INDEX BY PLS_INTEGER;


FUNCTION NEXT_PJOB_ID
RETURN PLS_INTEGER;

FUNCTION NEXT_TASK_ID
(
	inPJob_ID	PLS_INTEGER
)	RETURN		PLS_INTEGER;

PROCEDURE CHECK_STATE_ID_NAME
(
	outState_ID		IN OUT	NUMBER,
	outActivity		IN OUT	VARCHAR2,
	outState_Name	IN OUT	VARCHAR2
);

PROCEDURE CHECK_EVENT_ID_NAME
(
	outEvent_ID		IN OUT	NUMBER,
	outActivity		IN OUT	VARCHAR2,
	outEvent_Name	IN OUT	VARCHAR2
);


FUNCTION WF_GET_INIT_STATE
(
	inActivity		VARCHAR2
)	RETURN			PLS_INTEGER;


FUNCTION WF_EVENT_HANDLER
(
	inCurrent_State	PLS_INTEGER,
	outEvent_ID		IN OUT PLS_INTEGER,
	inEvent_Name	IN VARCHAR2,
	inCheck_State	BOOLEAN	:= TRUE
)	RETURN			PLS_INTEGER;


PROCEDURE WF_LOG
(
	inRefer_ID		NUMBER,
	inState_ID_Old	NUMBER,
	inEvent_ID		NUMBER,
	inState_ID_New	NUMBER,
	inMessage		VARCHAR2
);


PROCEDURE ON_PJOB_EVENT
(
	inPJob_ID			PLS_INTEGER,
	inEvent_Name		VARCHAR2,
	inCheck_State		BOOLEAN		:= TRUE,
	inLog				BOOLEAN		:= TRUE,
	inMessage			VARCHAR2	:= ''
);


PROCEDURE ADD_TASK
(
	inPJob_ID			PLS_INTEGER,
	inTask_ID			PLS_INTEGER,
	inDynamic_SQL_STMT	CLOB,
	inCommand_Timeout	PLS_INTEGER,
	inDescription_		VARCHAR2
);


FUNCTION GET_STANDBY_INTERVAL
RETURN	NUMBER;

FUNCTION GET_ARCHIVE_INTERVAL
RETURN	NUMBER;

FUNCTION GET_EXPIRE_INTERVAL
RETURN	NUMBER;


PROCEDURE RUN_PJOB
(
	inPJob_ID	PLS_INTEGER,
	RC1			OUT SYS_REFCURSOR
);


PROCEDURE RUN_TASK
(
	inPJob_ID	PLS_INTEGER,
	inTask_ID	PLS_INTEGER
);


PROCEDURE FAULT_TASK
(
	inPJob_ID			PLS_INTEGER,
	inTask_ID			PLS_INTEGER,
	inError_Message		VARCHAR2
);


PROCEDURE CALLBACK_TASK
(
	inPJob_ID	PLS_INTEGER,
	inTask_ID	PLS_INTEGER
);


PROCEDURE COMPLETE_PJOB
(
	inPJob_ID	PLS_INTEGER
);


PROCEDURE PUMP_PJOB
(
	outSwitch_To_Mode	OUT VARCHAR2,
	RC1					OUT SYS_REFCURSOR
);


PROCEDURE STANDBY_PING
(
	outSwitch_To_Mode	OUT VARCHAR2
);


PROCEDURE GET_SERVICE_CONFIG
(
	outPrimary_Interval			OUT NUMBER,
	outStandby_Interval			OUT NUMBER,
	outDegree_Task_Parallelism	OUT NUMBER,
	outMax_Threads_In_Pool		OUT NUMBER
);


PROCEDURE LOG_SYS_ERROR
(
	inReference		VARCHAR2,
	inMessage		VARCHAR2
);


FUNCTION WRAP_SQL_STMT
(
	inDynamic_SQL_STMT	CLOB
)	RETURN				CLOB;


PROCEDURE RECENT_WK_LOG
(
	inLast_Time		TIMESTAMP,
	RC1				OUT SYS_REFCURSOR
);


PROCEDURE WAIT_PJOB
(
	inPJob_ID	PLS_INTEGER
);


END TPW_SERVICE;
/
CREATE OR REPLACE PACKAGE BODY XYZ.TPW_SERVICE IS

g_Standby_Interval	NUMBER;
g_Archive_Interval	NUMBER;
g_Expire_Interval	NUMBER;
g_Polling_Interval	NUMBER;

FUNCTION GET_STANDBY_INTERVAL
RETURN	NUMBER
AS
BEGIN
	IF g_Standby_Interval IS NULL THEN
		SELECT	NUMBER_VALUE / 86400.0		INTO g_Standby_Interval
		FROM	XYZ.TPW_PUMP_CONFIG
		WHERE	ELEMENT_NAME = 'STANDBY_INTERVAL';
	END IF;
	RETURN g_Standby_Interval;
END GET_STANDBY_INTERVAL;

FUNCTION GET_ARCHIVE_INTERVAL
RETURN	NUMBER
AS
BEGIN
	IF g_Archive_Interval IS NULL THEN
		SELECT	NUMBER_VALUE / 1440.0		INTO g_Archive_Interval
		FROM	XYZ.TPW_PUMP_CONFIG
		WHERE	ELEMENT_NAME = 'ARCHIVE_INTERVAL';
	END IF;
	RETURN g_Archive_Interval;
END GET_ARCHIVE_INTERVAL;

FUNCTION GET_EXPIRE_INTERVAL
RETURN	NUMBER
AS
BEGIN
	IF g_Expire_Interval IS NULL THEN
		SELECT	NUMBER_VALUE / 24.0			INTO g_Expire_Interval
		FROM	XYZ.TPW_PUMP_CONFIG
		WHERE	ELEMENT_NAME = 'EXPIRE_INTERVAL';
	END IF;
	RETURN g_Expire_Interval;
END GET_EXPIRE_INTERVAL;


FUNCTION NEXT_PJOB_ID
RETURN	PLS_INTEGER
AS
	tNew_ID	PLS_INTEGER;
--PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
	UPDATE	XYZ.TPW_PUMP_CONFIG
	SET		NUMBER_VALUE	= NUMBER_VALUE + 1
	WHERE	ELEMENT_NAME	= 'PJOB_ID_RECORD'
	RETURNING NUMBER_VALUE INTO tNew_ID;

--	COMMIT WORK;
	RETURN tNew_ID;
END NEXT_PJOB_ID;

FUNCTION NEXT_TASK_ID
(
	inPJob_ID	PLS_INTEGER
)	RETURN		PLS_INTEGER
AS
	tNew_ID		PLS_INTEGER;
--PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
	UPDATE	XYZ.TPW_PJOB
	SET		TASK_ID_RECORD	= TASK_ID_RECORD + 1
	WHERE	PJOB_ID	= inPJob_ID
	RETURNING TASK_ID_RECORD INTO tNew_ID;

--	COMMIT WORK;
	RETURN tNew_ID;
END NEXT_TASK_ID;


FUNCTION GET_ALERT_NAME
(
	inPJob_ID	PLS_INTEGER
)	RETURN	VARCHAR2
IS
BEGIN
	RETURN 'pJob#' || TO_CHAR(inPJob_ID) || 'Done';
END GET_ALERT_NAME;


PROCEDURE CHECK_STATE_ID_NAME
(
	outState_ID		IN OUT	NUMBER,
	outActivity		IN OUT	VARCHAR2,
	outState_Name	IN OUT	VARCHAR2
)	AS
	tState_ID		PLS_INTEGER;
	tActivity		VARCHAR2(32);
	tState_Name		VARCHAR2(32);
BEGIN
	IF outState_Name IS NOT NULL AND outActivity IS NOT NULL THEN
		SELECT STATE_ID INTO tState_ID FROM XYZ.TPW_WF_STATE WHERE STATE_NAME = outState_Name AND ACTIVITY = outActivity;

		IF outState_ID IS NOT NULL THEN
			IF outState_ID != tState_ID THEN
				RAISE_APPLICATION_ERROR(-20001, 'STATE_ID mismatches with ACTIVITY and STATE_NAME!');
			END IF;
		ELSE
			outState_ID	:= tState_ID;
		END IF;
	ELSIF outState_ID IS NOT NULL THEN
		SELECT ACTIVITY, STATE_NAME INTO tActivity, tState_Name FROM XYZ.TPW_WF_STATE WHERE STATE_ID = outState_ID;

		IF outActivity IS NOT NULL THEN
			IF outActivity != tActivity THEN
				RAISE_APPLICATION_ERROR(-20001, 'ACTIVITY mismatches with STATE_ID!');
			END IF;
		ELSE
			outActivity	:= tActivity;
		END IF;

		IF outState_Name IS NOT NULL THEN
			IF outState_Name != tState_Name THEN
				RAISE_APPLICATION_ERROR(-20001, 'STATE_NAME mismatches with STATE_ID!');
			END IF;
		ELSE
			outState_Name	:= tState_Name;
		END IF;
	END IF;
END CHECK_STATE_ID_NAME;

PROCEDURE CHECK_EVENT_ID_NAME
(
	outEvent_ID		IN OUT	NUMBER,
	outActivity		IN OUT	VARCHAR2,
	outEvent_Name	IN OUT	VARCHAR2
)	AS
	tEvent_ID		PLS_INTEGER;
	tActivity		VARCHAR2(32);
	tEvent_Name		VARCHAR2(32);
BEGIN
	IF outEvent_Name IS NOT NULL AND outActivity IS NOT NULL THEN
		SELECT EVENT_ID INTO tEvent_ID FROM XYZ.TPW_WF_EVENT WHERE EVENT_NAME = outEvent_Name AND ACTIVITY = outActivity;

		IF outEvent_ID IS NOT NULL THEN
			IF outEvent_ID != tEvent_ID THEN
				RAISE_APPLICATION_ERROR(-20002, 'EVENT_ID mismatches with ACTIVITY and EVENT_NAME!');
			END IF;
		ELSE
			outEvent_ID	:= tEvent_ID;
		END IF;
	ELSIF outEvent_ID IS NOT NULL THEN
		SELECT ACTIVITY, EVENT_NAME INTO tActivity, tEvent_Name FROM XYZ.TPW_WF_EVENT WHERE EVENT_ID = outEvent_ID;

		IF outActivity IS NOT NULL THEN
			IF outActivity != tActivity THEN
				RAISE_APPLICATION_ERROR(-20002, 'ACTIVITY mismatches with EVENT_ID!');
			END IF;
		ELSE
			outActivity	:= tActivity;
		END IF;

		IF outEvent_Name IS NOT NULL THEN
			IF outEvent_Name != tEvent_Name THEN
				RAISE_APPLICATION_ERROR(-20002, 'EVENT_NAME mismatches with EVENT_ID!');
			END IF;
		ELSE
			outEvent_Name	:= tEvent_Name;
		END IF;
	END IF;
END CHECK_EVENT_ID_NAME;


FUNCTION WF_GET_INIT_STATE
(
	inActivity		VARCHAR2
)	RETURN			PLS_INTEGER
AS
	tBegin_State_ID	PLS_INTEGER;
BEGIN
	SELECT BEGIN_STATE_ID INTO tBegin_State_ID FROM XYZ.TPW_WF_ACTIVITY WHERE ACTIVITY = inActivity;
	RETURN tBegin_State_ID;
END WF_GET_INIT_STATE;


FUNCTION WF_EVENT_HANDLER
(
	inCurrent_State	PLS_INTEGER,
	outEvent_ID		IN OUT PLS_INTEGER,
	inEvent_Name	IN VARCHAR2,
	inCheck_State	BOOLEAN	:= TRUE
)	RETURN			PLS_INTEGER
AS
	t_New_State_ID	PLS_INTEGER;
BEGIN
	IF outEvent_ID IS NOT NULL THEN
		SELECT STATE_ID_NEW INTO t_New_State_ID
		FROM XYZ.TPW_WF_STATE_MACHINE
		WHERE EVENT_ID = outEvent_ID AND STATE_ID_OLD = inCurrent_State;
	ELSE
		SELECT STATE_ID_NEW, EVENT_ID INTO t_New_State_ID, outEvent_ID
		FROM XYZ.TPW_WF_STATE_MACHINE
		WHERE EVENT_NAME = inEvent_Name AND STATE_ID_OLD = inCurrent_State;
	END IF;

	RETURN t_New_State_ID;
EXCEPTION
	WHEN NO_DATA_FOUND THEN
		IF inCheck_State THEN
			RAISE_APPLICATION_ERROR(-20003, 'EVENT can not apply to current STATE!');
		ELSE
			RETURN t_New_State_ID;
		END IF;
END WF_EVENT_HANDLER;


PROCEDURE WF_LOG
(
	inRefer_ID		NUMBER,
	inState_ID_Old	NUMBER,
	inEvent_ID		NUMBER,
	inState_ID_New	NUMBER,
	inMessage		VARCHAR2
)	AS
BEGIN
	INSERT INTO XYZ.TPW_WK_LOG (LOG_TIME, REFER_ID, STATE_ID_OLD, EVENT_ID, STATE_ID_NEW, MESSAGE_)
	VALUES (SYSTIMESTAMP, inRefer_ID, inState_ID_Old, inEvent_ID, inState_ID_New, inMessage);
END WF_LOG;

PROCEDURE SET_SIGNAL
(
	inPJob_ID		PLS_INTEGER,
	inOld_State_ID	PLS_INTEGER,
	inEvent_Name	VARCHAR2,
	inNew_State_ID	PLS_INTEGER
)	IS
	tOld_Done		PLS_INTEGER;
	tNew_Done		PLS_INTEGER;
BEGIN
	IF inNew_State_ID <> inOld_State_ID THEN
		SELECT	IS_DONE	INTO tOld_Done	FROM XYZ.TPW_WF_STATE	WHERE STATE_ID	= inOld_State_ID;
		SELECT	IS_DONE	INTO tNew_Done	FROM XYZ.TPW_WF_STATE	WHERE STATE_ID	= inNew_State_ID;

		IF tOld_Done = 0 AND tNew_Done = 1 THEN
			DBMS_ALERT.SIGNAL(GET_ALERT_NAME(inPJob_ID), inEvent_Name);
		END IF;
	END IF;
END SET_SIGNAL;

PROCEDURE ON_PJOB_EVENT
(
	inPJob_ID			PLS_INTEGER,
	inEvent_Name		VARCHAR2,
	inCheck_State		BOOLEAN		:= TRUE,
	inLog				BOOLEAN		:= TRUE,
	inMessage			VARCHAR2	:= ''
)	AS
	tOld_State_ID		PLS_INTEGER;
	tEvent_ID			PLS_INTEGER;
	tNew_State_ID		PLS_INTEGER;
BEGIN
	SELECT STATE_ID INTO tOld_State_ID FROM XYZ.TPW_PJOB WHERE PJOB_ID = inPJob_ID;

	tNew_State_ID	:= WF_EVENT_HANDLER(tOld_State_ID, tEvent_ID, inEvent_Name, inCheck_State);

	UPDATE XYZ.TPW_PJOB
	SET		STATE_ID		= tNew_State_ID
	WHERE	STATE_ID		= tOld_State_ID
		AND	PJOB_ID			= inPJob_ID
		AND tNew_State_ID	!= tOld_State_ID;

	SET_SIGNAL(inPJob_ID, tOld_State_ID, inEvent_Name, tNew_State_ID);

	IF  inLog THEN
		WF_LOG(inPJob_ID, tOld_State_ID, tEvent_ID, tNew_State_ID, NVL(inMessage, inEvent_Name));
	END IF;

EXCEPTION
	WHEN NO_DATA_FOUND THEN
		NULL;
END ON_PJOB_EVENT;


PROCEDURE ADD_TASK
(
	inPJob_ID			PLS_INTEGER,
	inTask_ID			PLS_INTEGER,
	inDynamic_SQL_STMT	CLOB,
	inCommand_Timeout	PLS_INTEGER,
	inDescription_		VARCHAR2
)	AS
	tCommand_Timeout	PLS_INTEGER	:= LEAST(GREATEST(inCommand_Timeout, 1), 32767);
BEGIN
	ON_PJOB_EVENT(inPJob_ID, 'ADD_TASK', (inTask_ID > 0));

	INSERT INTO XYZ.TPW_TASK (PJOB_ID, TASK_ID, COMMAND_TIMEOUT, DYNAMIC_SQL_STMT, DESCRIPTION_)
	VALUES (inPJob_ID, inTask_ID, tCommand_Timeout, WRAP_SQL_STMT(inDynamic_SQL_STMT), inDescription_);

	COMMIT;
END ADD_TASK;


PROCEDURE RUN_PJOB
(
	inPJob_ID	PLS_INTEGER,
	RC1			OUT SYS_REFCURSOR
)	AS
BEGIN
	ON_PJOB_EVENT(inPJob_ID, 'RUN');

	UPDATE	XYZ.TPW_PJOB
	SET		START_TIME	= SYSTIMESTAMP
	WHERE	PJOB_ID		= inPJob_ID;

	COMMIT;

	OPEN RC1 FOR
	SELECT
		PJOB_ID,
		TASK_ID,
		COMMAND_TIMEOUT
	FROM
		XYZ.TPW_TASK
	WHERE
		PJOB_ID	= inPJob_ID;

EXCEPTION
	WHEN OTHERS THEN
		ROLLBACK;
END RUN_PJOB;


PROCEDURE RUN_TASK
(
	inPJob_ID	PLS_INTEGER,
	inTask_ID	PLS_INTEGER
)	AS
	tDynamic_SQL_STMT	CLOB;
BEGIN
	UPDATE		XYZ.TPW_TASK
	SET			START_TIME = SYSTIMESTAMP
	WHERE		TASK_ID = inTask_ID AND PJOB_ID = inPJob_ID
	RETURNING	DYNAMIC_SQL_STMT INTO tDynamic_SQL_STMT;

	IF SQL%ROWCOUNT > 0 THEN
		COMMIT;

		EXECUTE IMMEDIATE tDynamic_SQL_STMT;

		UPDATE XYZ.TPW_TASK SET END_TIME = SYSTIMESTAMP WHERE TASK_ID = inTask_ID AND PJOB_ID = inPJob_ID;
		COMMIT;
	END IF;
END RUN_TASK;


PROCEDURE FAULT_TASK
(
	inPJob_ID			PLS_INTEGER,
	inTask_ID			PLS_INTEGER,
	inError_Message		VARCHAR2
)	AS
BEGIN
	UPDATE XYZ.TPW_TASK
	SET
		END_TIME		= SYSTIMESTAMP,
		ERROR_MESSAGE	= inError_Message
	WHERE
			END_TIME	IS NULL
		AND TASK_ID		= inTask_ID
		AND PJOB_ID		= inPJob_ID;

	ON_PJOB_EVENT(inPJob_ID, 'FAULT', FALSE, TRUE, SUBSTRB('[Task_ID=' || TO_CHAR(inTask_ID) || ']' || inError_Message, 1, 1024));

END FAULT_TASK;


PROCEDURE CALLBACK_TASK
(
	inPJob_ID	PLS_INTEGER,
	inTask_ID	PLS_INTEGER
)	AS
BEGIN
	ON_PJOB_EVENT(inPJob_ID, 'CALLBACK');
	RUN_TASK(inPJob_ID, inTask_ID);
	COMMIT;
END CALLBACK_TASK;


PROCEDURE COMPLETE_PJOB
(
	inPJob_ID	PLS_INTEGER
)	AS
	tEvent_Name		CONSTANT VARCHAR2(32)	:= 'COMPLETE';
BEGIN
	ON_PJOB_EVENT(inPJob_ID, tEvent_Name);

	UPDATE	XYZ.TPW_PJOB
	SET		END_TIME	= SYSTIMESTAMP
	WHERE	END_TIME	IS NULL
		AND	PJOB_ID		= inPJob_ID;

	COMMIT;
END COMPLETE_PJOB;


PROCEDURE EXPIRE_PJOB
AS
	tInterval		NUMBER					:= GET_EXPIRE_INTERVAL;
	tNow			DATE					:= SYSDATE;
	tEvent_Name		CONSTANT VARCHAR2(32)	:= 'EXPIRE';
	tRowids			Rowid_Array;
	tPJob_IDs		Int_Array;
	tState_IDs		Int_Array;
	tEvent_IDs		Int_Array;
	tState_ID_News	Int_Array;
BEGIN
	UPDATE	XYZ.TPW_PUMP_CONFIG
	SET		DATE_VALUE		= tNow
	WHERE	DATE_VALUE		< tNow - tInterval
		AND	ELEMENT_NAME	= 'LAST_EXPIRED';

	IF SQL%ROWCOUNT > 0 THEN
		SELECT				ROW_ID, PJOB_ID, STATE_ID, EVENT_ID, STATE_ID_NEW
		BULK COLLECT INTO	tRowids, tPJob_IDs, tState_IDs, tEvent_IDs, tState_ID_News
		FROM				XYZ.VIEW_TPW_PJOB_STATE_MACHINE
		WHERE				EXPIRY_TIME	< tNow	AND	EVENT_NAME	= tEvent_Name;

		IF tRowids.COUNT > 0 THEN
			FORALL i IN tRowids.FIRST .. tRowids.LAST
				INSERT INTO XYZ.TPW_WK_LOG (LOG_TIME, REFER_ID, STATE_ID_OLD, EVENT_ID, STATE_ID_NEW, MESSAGE_)
				VALUES (SYSTIMESTAMP, tPJob_IDs(i), tState_IDs(i), tEvent_IDs(i), tState_ID_News(i), tEvent_Name);

			FORALL i IN tRowids.FIRST .. tRowids.LAST
				UPDATE	XYZ.TPW_PJOB
				SET		STATE_ID = tState_ID_News(i)
				WHERE	ROWID = tRowids(i);

			FOR i IN tRowids.FIRST .. tRowids.LAST
			LOOP
				DBMS_ALERT.SIGNAL(GET_ALERT_NAME(tPJob_IDs(i)), tEvent_Name);
			END LOOP;
		END IF;
	END IF;
END;


FUNCTION ARCHIVE_PJOB
RETURN	BOOLEAN
AS
	tInterval	NUMBER					:= GET_ARCHIVE_INTERVAL;
	tNow		DATE					:= SYSDATE;
	tEvent_Name	CONSTANT VARCHAR2(32)	:= 'ARCHIVE';
BEGIN
	UPDATE	XYZ.TPW_PUMP_CONFIG
	SET		DATE_VALUE		= tNow
	WHERE	DATE_VALUE		< tNow - tInterval
		AND	ELEMENT_NAME	= 'LAST_ARCHIVED';

	IF SQL%ROWCOUNT > 0 THEN
		INSERT ALL
		INTO XYZ.TPW_PJOB_ARCHIVE (PJOB_ID, STATE_ID, TASK_ID_RECORD, SCHEDULED_TIME, EXPIRY_TIME, START_TIME, END_TIME, USER_APP, USER_NAME, DESCRIPTION_)
		VALUES (PJOB_ID, STATE_ID_NEW, TASK_COUNT, SCHEDULED_TIME, EXPIRY_TIME, START_TIME, END_TIME, USER_APP, USER_NAME, DESCRIPTION_)
		INTO XYZ.TPW_WK_LOG (LOG_TIME, REFER_ID, STATE_ID_OLD, EVENT_ID, STATE_ID_NEW, MESSAGE_)
		VALUES (SYSTIMESTAMP, PJOB_ID, STATE_ID, EVENT_ID, STATE_ID_NEW, tEvent_Name)
		SELECT
			STATE_ID,
			EVENT_ID,
			PJOB_ID,
			STATE_ID_NEW,
			TASK_COUNT,
			SCHEDULED_TIME,
			EXPIRY_TIME,
			START_TIME,
			END_TIME,
			USER_APP,
			USER_NAME,
			DESCRIPTION_
		FROM
			XYZ.VIEW_TPW_PJOB_STATE_MACHINE
		WHERE
			EVENT_NAME	= tEvent_Name;

		INSERT INTO XYZ.TPW_TASK_ARCHIVE (PJOB_ID, TASK_ID, COMMAND_TIMEOUT, DYNAMIC_SQL_STMT, DESCRIPTION_, START_TIME, END_TIME, ERROR_MESSAGE)
		SELECT
			T.PJOB_ID, T.TASK_ID, T.COMMAND_TIMEOUT, T.DYNAMIC_SQL_STMT, T.DESCRIPTION_, T.START_TIME, T.END_TIME, T.ERROR_MESSAGE
		FROM
			XYZ.TPW_TASK						T,
			XYZ.VIEW_TPW_PJOB_STATE_MACHINE	J
		WHERE
				T.PJOB_ID		= J.PJOB_ID
			AND J.EVENT_NAME	= tEvent_Name;

		DELETE FROM XYZ.TPW_PJOB
		WHERE ROWID IN
		(
			SELECT
				ROW_ID
			FROM
				XYZ.VIEW_TPW_PJOB_STATE_MACHINE
			WHERE
				EVENT_NAME = tEvent_Name
		);

		COMMIT;
		RETURN TRUE;
	ELSE
		RETURN FALSE;
	END IF;
END ARCHIVE_PJOB;


PROCEDURE SERVICE_PING
(
	inIs_Primary	CHAR
)
AS
BEGIN
	MERGE INTO XYZ.TPW_PUMP_SERVER		P
	USING
	(
		SELECT
			NVL(SYS_CONTEXT('USERENV', 'TERMINAL'), '?')	AS SERVER_NAME,
			SYSTIMESTAMP									AS SERVICE_BEAT,
			inIs_Primary									AS IS_PRIMARY,
			NVL(SYS_CONTEXT('USERENV', 'OS_USER'), '?')		AS SERVICE_ACCOUNT
		FROM
			DUAL
	)	C
	ON	(P.SERVER_NAME = C.SERVER_NAME)
	WHEN MATCHED THEN
		UPDATE SET
			P.SERVICE_BEAT		= C.SERVICE_BEAT,
			P.IS_PRIMARY		= C.IS_PRIMARY,
			P.SERVICE_ACCOUNT	= C.SERVICE_ACCOUNT
	WHEN NOT MATCHED THEN
		INSERT	(P.SERVER_NAME, P.SERVICE_BEAT, P.IS_PRIMARY, P.SERVICE_ACCOUNT)
		VALUES	(C.SERVER_NAME, C.SERVICE_BEAT, C.IS_PRIMARY, C.SERVICE_ACCOUNT);

END SERVICE_PING;


PROCEDURE PUMP_PJOB		-- DISPATCH_PJOB
(
	outSwitch_To_Mode	OUT VARCHAR2,
	RC1					OUT SYS_REFCURSOR
)
AS
	tNow	DATE	:= SYSDATE;
BEGIN
	UPDATE	XYZ.TPW_PUMP_CONFIG
	SET		DATE_VALUE		= tNow
	WHERE	ELEMENT_NAME	= 'PRIMARY_BEAT';

	IF ARCHIVE_PJOB THEN
		EXPIRE_PJOB;
	END IF;

	OPEN RC1 FOR
	SELECT
		PJOB_ID
	FROM
		XYZ.VIEW_TPW_PJOB_STATE_MACHINE
	WHERE
			SCHEDULED_TIME	<= tNow
		AND EVENT_NAME		= 'RUN'			-- Can run
	ORDER BY
		PJOB_ID;

	outSwitch_To_Mode	:= 'Primary';

	SERVICE_PING('Y');
	COMMIT;
END PUMP_PJOB;


PROCEDURE STANDBY_PING
(
	outSwitch_To_Mode	OUT VARCHAR2
)
AS
	tInterval		NUMBER	:= GET_STANDBY_INTERVAL;
	tNow			DATE	:= SYSDATE;
	tPrimary_Beat	DATE;
BEGIN
	UPDATE	XYZ.TPW_PUMP_CONFIG
	SET		DATE_VALUE		= tNow
	WHERE	DATE_VALUE		<= tNow - tInterval
		AND	ELEMENT_NAME	= 'STANDBY_BEAT';

	IF SQL%ROWCOUNT > 0 THEN
		SELECT DATE_VALUE INTO tPrimary_Beat FROM XYZ.TPW_PUMP_CONFIG WHERE ELEMENT_NAME = 'PRIMARY_BEAT';
		IF (tNow - tPrimary_Beat) > (tInterval / 2) THEN
			outSwitch_To_Mode	:= 'Primary';
		ELSE
			outSwitch_To_Mode	:= 'Standby';
		END IF;
	END IF;

	SERVICE_PING('N');
	COMMIT;
END STANDBY_PING;


PROCEDURE GET_SERVICE_CONFIG
(
	outPrimary_Interval			OUT NUMBER,
	outStandby_Interval			OUT NUMBER,
	outDegree_Task_Parallelism	OUT NUMBER,
	outMax_Threads_In_Pool		OUT NUMBER
)
AS
BEGIN
	SELECT NUMBER_VALUE INTO outPrimary_Interval		FROM XYZ.TPW_PUMP_CONFIG WHERE ELEMENT_NAME = 'PRIMARY_INTERVAL';
	SELECT NUMBER_VALUE INTO outStandby_Interval		FROM XYZ.TPW_PUMP_CONFIG WHERE ELEMENT_NAME = 'STANDBY_INTERVAL';
	SELECT NUMBER_VALUE INTO outDegree_Task_Parallelism	FROM XYZ.TPW_PUMP_CONFIG WHERE ELEMENT_NAME = 'DEGREE_OF_TASK_PARALLELISM';
	SELECT NUMBER_VALUE INTO outMax_Threads_In_Pool		FROM XYZ.TPW_PUMP_CONFIG WHERE ELEMENT_NAME = 'MAX_THREADS_IN_POOL';
END GET_SERVICE_CONFIG;


PROCEDURE LOG_SYS_ERROR
(
	inReference		VARCHAR2,
	inMessage		VARCHAR2
)
AS
BEGIN
	INSERT INTO XYZ.TPW_SYS_ERROR (LOG_TIME, REFERENCE_, MESSAGE_)
	VALUES (SYSTIMESTAMP, inReference, inMessage);
	COMMIT;
END LOG_SYS_ERROR;


FUNCTION WRAP_SQL_STMT
(
	inDynamic_SQL_STMT	CLOB
)	RETURN				CLOB
AS
	tSingle		CONSTANT VARCHAR2(64)	:= '(INSERT)|(DELETE)|(UPDATE)|(MERGE)';
	tEnclose	CONSTANT VARCHAR2(16)	:= 'BEGIN.+END;';
	tRetChar	CONSTANT VARCHAR2(2)	:= CHR(13)||CHR(10);
	tDynamic_SQL_STMT	CLOB			:= TRIM(inDynamic_SQL_STMT);
BEGIN
	IF NOT REGEXP_LIKE(tDynamic_SQL_STMT, tSingle, 'i') THEN
		IF SUBSTR(tDynamic_SQL_STMT, LENGTH(tDynamic_SQL_STMT), 1) != ';' THEN
			tDynamic_SQL_STMT	:= tDynamic_SQL_STMT || ';';
		END IF;

		IF NOT REGEXP_LIKE(tDynamic_SQL_STMT, tEnclose, 'i') THEN
			tDynamic_SQL_STMT	:= 'BEGIN' || tRetChar || tDynamic_SQL_STMT || tRetChar || 'END;';
		END IF;
	END IF;

	RETURN tDynamic_SQL_STMT;
END WRAP_SQL_STMT;


PROCEDURE RECENT_WK_LOG
(
	inLast_Time		TIMESTAMP,
	RC1				OUT SYS_REFCURSOR
)
AS
BEGIN
	OPEN RC1 FOR
	SELECT
		L.LOG_TIME,
		L.REFER_ID,
		O.STATE_NAME				AS OLD_STATE,
		E.EVENT_NAME				AS EVENT_,
		N.STATE_NAME				AS NEW_STATE,
		L.MESSAGE_
	FROM
		XYZ.TPW_WF_STATE				O,
		XYZ.TPW_WF_EVENT				E,
		XYZ.TPW_WF_STATE				N,
		XYZ.TPW_WK_LOG					L
	WHERE
			O.STATE_ID(+)	= L.STATE_ID_OLD
		AND E.EVENT_ID(+)	= L.EVENT_ID
		AND N.STATE_ID		= L.STATE_ID_NEW
		AND L.LOG_TIME		> inLast_Time
	ORDER BY
		L.LOG_TIME,
		L.REFER_ID;
END RECENT_WK_LOG;


FUNCTION GET_STATUS_POLLING_INTERVAL
RETURN	NUMBER
AS
BEGIN
	IF g_Polling_Interval IS NULL THEN
		SELECT	NUMBER_VALUE / 1000		INTO g_Polling_Interval
		FROM	XYZ.TPW_PUMP_CONFIG
		WHERE	ELEMENT_NAME = 'STATUS_POLLING_INTERVAL';

		IF g_Polling_Interval < 0.1 THEN
			g_Polling_Interval	:= 0.1;
		END IF;
	END IF;
	RETURN g_Polling_Interval;
END GET_STATUS_POLLING_INTERVAL;


PROCEDURE WAIT_PJOB
(
	inPJob_ID	PLS_INTEGER
)	IS
	tIs_Done	PLS_INTEGER;
	tAlert_Name	VARCHAR2(30)	:= GET_ALERT_NAME(inPJob_ID);
	tMessage	VARCHAR2(32);
	tStatus		INTEGER;
BEGIN
	DBMS_ALERT.REGISTER(tAlert_Name);

	SELECT	MAX(S.IS_DONE)	INTO tIs_Done
	FROM
			XYZ.TPW_WF_STATE	S,
			XYZ.TPW_PJOB		J
	WHERE
			S.STATE_ID	= J.STATE_ID
		AND	J.PJOB_ID	= inPJob_ID;

	IF tIs_Done = 0 THEN
		DBMS_ALERT.SET_DEFAULTS(GET_STATUS_POLLING_INTERVAL);
		DBMS_ALERT.WAITONE(tAlert_Name, tMessage, tStatus);
	END IF;

	DBMS_ALERT.REMOVE(tAlert_Name);
END WAIT_PJOB;


END TPW_SERVICE;
/
