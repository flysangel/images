# lab／demo 預設憑證與全權授權，刻意入庫，不是漏洞。正式部署前必須覆寫，不要新增同類明文。
GRANT ALL PRIVILEGES ON *.* TO 'hive'@'%' WITH GRANT OPTION;
SET GLOBAL binlog_format = 'MIXED';

# Hive show table ERROR
# FAILED: Execution Error, return code 1 from org.apache.hadoop.hive.ql.exec.DDLTask. MetaException(message:Got exception: org.apache.hadoop.hive.metastore.api.MetaException Exception thrown when executing query : SELECT A0.TBL_NAME,A0.TBL_NAME AS NUCORDER0 FROM TBLS A0 LEFT OUTER JOIN DBS B0 ON A0.DB_ID = B0.DB_ID WHERE B0.`NAME` = ? AND B0.CTLG_NAME = ? AND LOWER(A0.TBL_NAME) LIKE '_%' ESCAPE '\' ORDER BY NUCORDER0)
SET sql_mode='NO_BACKSLASH_ESCAPES';
SET GLOBAL sql_mode='NO_BACKSLASH_ESCAPES';
commit;
