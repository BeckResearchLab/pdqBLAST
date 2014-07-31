WARNINGS;

DROP DATABASE IF EXISTS pdqBLAST;

CREATE DATABASE pdqBLAST;

USE pdqBLAST;

CREATE TABLE master_job_status (
	status_id SMALLINT UNSIGNED NOT NULL PRIMARY KEY,
	status_text VARCHAR(128)
) ENGINE=INNODB;

INSERT INTO master_job_status (status_id, status_text) VALUES (1, "Setup");
INSERT INTO master_job_status (status_id, status_text) VALUES (2, "Waiting");
INSERT INTO master_job_status (status_id, status_text) VALUES (3, "Running");
INSERT INTO master_job_status (status_id, status_text) VALUES (4, "Complete");

CREATE TABLE master_job (
	job_id INTEGER UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
	status_id SMALLINT UNSIGNED NOT NULL,
	blast_db VARCHAR(256) NOT NULL,
	query_file VARCHAR(256) NOT NULL,
	blast_program VARCHAR(256) NOT NULL,
	blast_threads SMALLINT UNSIGNED NOT NULL,
	blast_arguments VARCHAR(256) NOT NULL,
	temporary_directory VARCHAR(256),
	work_units MEDIUMINT UNSIGNED NOT NULL,
	output_table VARCHAR(256) NOT NULL,
	submitted DATETIME NOT NULL,
	started DATETIME,
	completed DATETIME,
	FOREIGN KEY (status_id) REFERENCES master_job_status(status_id)
) ENGINE=INNODB;

CREATE TABLE master_work_unit_status (
	status_id SMALLINT UNSIGNED NOT NULL PRIMARY KEY,
	status_text VARCHAR(128)
) ENGINE=INNODB;

INSERT INTO master_work_unit_status (status_id, status_text) VALUES (1, "Not submitted");
INSERT INTO master_work_unit_status (status_id, status_text) VALUES (2, "Waiting to run");
INSERT INTO master_work_unit_status (status_id, status_text) VALUES (3, "Staging data");
INSERT INTO master_work_unit_status (status_id, status_text) VALUES (4, "Running BLAST");
INSERT INTO master_work_unit_status (status_id, status_text) VALUES (5, "Loading results");
INSERT INTO master_work_unit_status (status_id, status_text) VALUES (6, "Clean up");
INSERT INTO master_work_unit_status (status_id, status_text) VALUES (7, "Complete");

CREATE TABLE master_work_unit (
	job_id INTEGER UNSIGNED NOT NULL,
	work_unit_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
	work_unit_number MEDIUMINT UNSIGNED NOT NULL,
	status_id SMALLINT UNSIGNED NOT NULL,
	script_filename VARCHAR(256),
	script LONGTEXT,
	scheduler_id VARCHAR(32),
	node VARCHAR(64),
	temporary_directory VARCHAR(64),
	submitted DATETIME,
	started DATETIME,
	staging_completed DATETIME,
	running_completed DATETIME,
	loading_completed DATETIME,
	completed DATETIME,
	stage_log LONGTEXT,
	blast_log LONGTEXT,
	cleanup_log LONGTEXT,
	FOREIGN KEY (job_id) REFERENCES master_job(job_id),
	FOREIGN KEY (status_id) REFERENCES master_work_unit_status(status_id)
) ENGINE=INNODB;

DELIMITER $$

CREATE PROCEDURE job_add(IN blast_program VARCHAR(256), IN blast_threads SMALLINT UNSIGNED, IN blast_arguments VARCHAR(256), IN blast_db VARCHAR(256), IN query_file VARCHAR(256), IN work_units MEDIUMINT UNSIGNED, IN output_table VARCHAR(256), OUT new_job_id INTEGER UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Adds a new pdqBLAST job to master job and work unit tables'
BEGIN
	DECLARE work_unit_number MEDIUMINT UNSIGNED DEFAULT 1;
	START TRANSACTION;
	INSERT INTO master_job (status_id, blast_program, blast_threads, blast_arguments, blast_db, query_file, work_units, output_table, submitted)
		VALUES (1, blast_program, blast_threads, blast_arguments, blast_db, query_file, work_units, output_table, NOW());
	SET new_job_id = LAST_INSERT_ID();
	SELECT 1 INTO work_unit_number;
	WHILE work_unit_number <= work_units DO
		INSERT INTO master_work_unit (job_id, work_unit_number, status_id)
			VALUES (new_job_id, work_unit_number, 1);
		SET work_unit_number = work_unit_number + 1;
	END WHILE;
	COMMIT;

	SET @statement = CONCAT('CREATE TABLE ', output_table, ' ( qseqid varchar(128) NOT NULL, sseqid varchar(128) NOT NULL, pident FLOAT NOT NULL, length INTEGER UNSIGNED NOT NULL, mismatch INTEGER UNSIGNED NOT NULL, gapopen INTEGER UNSIGNED NOT NULL, qstart INTEGER UNSIGNED NOT NULL, qend INTEGER UNSIGNED NOT NULL, sstart INTEGER UNSIGNED NOT NULL, send INTEGER UNSIGNED NOT NULL, evalue DOUBLE NOT NULL, bitscore INTEGER UNSIGNED NOT NULL) ');
	PREPARE stmt FROM @statement;
	EXECUTE stmt;
	DEALLOCATE PREPARE stmt;
END$$

CREATE PROCEDURE job_update_temporary_directory(IN my_job_id INTEGER UNSIGNED, IN my_temporary_directory VARCHAR(256))
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Sets the shared temporary directory for a job'
BEGIN
	UPDATE master_job SET temporary_directory = my_temporary_directory WHERE job_id = my_job_id;
END$$


CREATE PROCEDURE job_status_waiting(IN my_job_id INTEGER UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Update status for a job to waiting'
BEGIN
-- update the status to waiting, but only do this if the status has not already progressed to running by a call to job_work_unit_status_staging
	UPDATE master_job SET status_id=2 WHERE job_id=my_job_id AND status_id < 2;
END$$

CREATE PROCEDURE job_work_unit_load_script(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, IN my_script_filename VARCHAR(256))
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Load the scheduler script used to run a work unit'
BEGIN
	UPDATE master_work_unit SET script_filename=my_script_filename, script=LOAD_FILE(my_script_filename) WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_work_unit_status_submitted(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, IN my_scheduler_id VARCHAR(32))
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Update status for a work unit to submitted w/ scheduler ID'
BEGIN
	UPDATE master_work_unit SET status_id=2, submitted=NOW(), scheduler_id=my_scheduler_id WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_work_unit_status_staging(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, IN my_node VARCHAR(64), IN my_temporary_directory VARCHAR(64))
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Update status for a work unit to staging w/ node info'
BEGIN
	UPDATE master_work_unit SET status_id=3, started=NOW(), node=my_node, temporary_directory=my_temporary_directory WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
-- change the job status to running and set the started time if the job status is still waiting
	UPDATE master_job SET status_id=3, started=NOW() WHERE job_id=my_job_id AND status_id=2;
END$$

CREATE PROCEDURE job_work_unit_status_running(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Update status for a work unit to running'
BEGIN
	UPDATE master_work_unit SET status_id=4, staging_completed=NOW() WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_work_unit_status_loading(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Update status for a work unit to cleaning up'
BEGIN
	UPDATE master_work_unit SET status_id=5, running_completed=NOW() WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_work_unit_status_cleanup(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Update status for a work unit to cleaning up'
BEGIN
	UPDATE master_work_unit SET status_id=6, loading_completed=NOW() WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_work_unit_status_complete(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Update status for a work unit to complete update job if done'
BEGIN
	UPDATE master_work_unit SET status_id=7, completed=NOW() WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
	IF 
		(SELECT COUNT(work_unit_number) FROM master_work_unit WHERE job_id=my_job_id AND NOT ISNULL(completed)) = 
		(SELECT COUNT(work_unit_number) FROM master_work_unit WHERE job_id=my_job_id) THEN
		UPDATE master_job SET status_id=4, completed=NOW() WHERE job_id=my_job_id;
	END IF;
END$$

CREATE PROCEDURE job_work_unit_load_stage_log(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, IN my_log_filename VARCHAR(256))
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Load the log file generated by the staging phase of a work unit'
BEGIN
	UPDATE master_work_unit SET stage_log=LOAD_FILE(my_log_filename) WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_work_unit_load_blast_log(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, IN my_log_filename VARCHAR(256))
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Load the log file generated by the BLAST phase of a work unit'
BEGIN
	UPDATE master_work_unit SET blast_log=LOAD_FILE(my_log_filename) WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_work_unit_load_cleanup_log(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, IN my_log_filename VARCHAR(256))
LANGUAGE SQL
DETERMINISTIC
MODIFIES SQL DATA
SQL SECURITY INVOKER
COMMENT 'Load the log file generated by the cleanup phase of a work unit'
BEGIN
	UPDATE master_work_unit SET cleanup_log=LOAD_FILE(my_log_filename) WHERE job_id=my_job_id AND work_unit_number=my_work_unit_number;
END$$

CREATE PROCEDURE job_status(IN my_job_id INTEGER UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
COMMENT 'Return status for a job'
BEGIN
	SELECT j.job_id, js.status_text, j.blast_program, j.blast_threads, j.blast_arguments, j.blast_db, j.query_file, j.temporary_directory, j.work_units, IF(ISNULL(jc.work_units_complete), 0, jc.work_units_complete) AS work_units_complete, j.output_table, j.submitted, j.started, j.completed
		FROM master_job AS j
			INNER JOIN master_job_status AS js ON j.status_id = js.status_id
			LEFT JOIN (SELECT my_job_id AS job_id, COUNT(work_unit_number) AS work_units_complete FROM master_work_unit AS w
					WHERE NOT ISNULL(completed) AND job_id = my_job_id) AS jc ON j.job_id = jc.job_id
		WHERE j.job_id = my_job_id
	;
END$$

CREATE PROCEDURE job_work_unit_status(IN my_job_id INTEGER UNSIGNED)
LANGUAGE SQL
DETERMINISTIC
COMMENT 'Return status of a job work unit'
BEGIN
	SELECT w.job_id, w.work_unit_number, ws.status_text, w.scheduler_id, w.node, w.temporary_directory, w.script_filename, w.submitted, TIME_FORMAT(TIMEDIFF(w.started, w.submitted), "%T") AS queued_time, w.started, w.staging_completed, TIME_FORMAT(TIMEDIFF(w.staging_completed, w.started), "%T") AS staging_time, w.running_completed, TIME_FORMAT(TIMEDIFF(w.running_completed, w.staging_completed), "%T") AS blast_time, w.loading_completed, TIME_FORMAT(TIMEDIFF(w.loading_completed, w.running_completed), "%T") AS loading_time, w.completed, TIME_FORMAT(TIMEDIFF(w.completed, w.loading_completed), "%T") AS cleanup_time
		FROM master_work_unit AS w
			INNER JOIN master_work_unit_status AS ws ON w.status_id = ws.status_id
		WHERE w.job_id = my_job_id
		ORDER BY w.work_unit_number
	;
END$$

CREATE PROCEDURE job_work_unit_node(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, OUT my_node VARCHAR(64))
LANGUAGE SQL
DETERMINISTIC
COMMENT 'Return node assigned to a job work unit'
BEGIN
	DECLARE node_count MEDIUMINT UNSIGNED;

	SET node_count = (SELECT COUNT(node) FROM master_work_unit WHERE job_id = my_job_id AND work_unit_number = my_work_unit_number);
	IF node_count <> 1 THEN
		SET my_node = NULL;
	ELSE
		SET my_node = (SELECT node FROM master_work_unit WHERE job_id = my_job_id AND work_unit_number = my_work_unit_number);
	END IF;
END$$

CREATE PROCEDURE job_work_unit_temporary_directory(IN my_job_id INTEGER UNSIGNED, IN my_work_unit_number MEDIUMINT UNSIGNED, OUT my_temporary_directory VARCHAR(64))
LANGUAGE SQL
DETERMINISTIC
COMMENT 'Return the node local temp. dir for a job work unit'
BEGIN
	DECLARE node_count MEDIUMINT UNSIGNED;

	SET node_count = (SELECT COUNT(node) FROM master_work_unit WHERE job_id = my_job_id AND work_unit_number = my_work_unit_number);
	IF node_count <> 1 THEN
		SET my_temporary_directory = NULL;
	ELSE
		SET my_temporary_directory = (SELECT temporary_directory FROM master_work_unit WHERE job_id = my_job_id AND work_unit_number = my_work_unit_number);
	END IF;
END$$
