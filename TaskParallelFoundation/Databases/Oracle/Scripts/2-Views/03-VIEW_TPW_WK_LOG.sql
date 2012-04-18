CREATE OR REPLACE VIEW XYZ.VIEW_TPW_WK_LOG AS
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
	(
		SELECT
			LOG_TIME,
			REFER_ID,
			STATE_ID_OLD,
			EVENT_ID,
			STATE_ID_NEW,
			MESSAGE_
		FROM
			XYZ.TPW_WK_LOG

		UNION ALL

		SELECT
			LOG_TIME,
			REFER_ID,
			STATE_ID_OLD,
			EVENT_ID,
			STATE_ID_NEW,
			MESSAGE_
		FROM
			XYZ.TPW_WK_LOG_ARCHIVE
	)								L
WHERE
		O.STATE_ID(+)	= L.STATE_ID_OLD
	AND E.EVENT_ID(+)	= L.EVENT_ID
	AND N.STATE_ID		= L.STATE_ID_NEW

WITH READ ONLY;