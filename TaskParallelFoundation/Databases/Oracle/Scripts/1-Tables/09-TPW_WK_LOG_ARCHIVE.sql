-- CREATE TABLE
CREATE TABLE XYZ.TPW_WK_LOG_ARCHIVE
(
	LOG_TIME			TIMESTAMP(3)	NOT NULL,
	REFER_ID			NUMBER(10)		NOT NULL,

	STATE_ID_OLD		NUMBER(5),
	EVENT_ID			NUMBER(5),
	STATE_ID_NEW		NUMBER(5)		NOT NULL,

	MESSAGE_			VARCHAR2(1024)
)
STORAGE (INITIAL 8M NEXT 8M)
COMPRESS FOR ALL OPERATIONS;

CREATE INDEX XYZ.IX_TPW_WK_LOG_ARCHIVE1 ON XYZ.TPW_WK_LOG_ARCHIVE (LOG_TIME, REFER_ID, STATE_ID_OLD, EVENT_ID, STATE_ID_NEW) COMPRESS;
CREATE INDEX XYZ.IX_TPW_WK_LOG_ARCHIVE2 ON XYZ.TPW_WK_LOG_ARCHIVE (REFER_ID, EVENT_ID, STATE_ID_OLD, STATE_ID_NEW) COMPRESS;