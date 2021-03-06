Parallel Distributed Query (or pretty damn quick) BLAST allows parallel blast queries to be run without MPI and with true evalue calculation for large query sets

```
File:			Description:
-----------------------	------------------------------------------------------------------------------------
0README			This file

example.pdqBLASTrc	Example .pdqBLASTrc that users need to place in their home directory

init			Scripts and SQL to initialize the MySQL database for pdqBLAST data
init/init_db		Call this once to initialize the MySQL database WARNING! This blows away all data
init/init_db.sql	Called by init_db
init/init_test		Test script for database, should not be run on live system
init/init_test.sql	Called by init_test
init/test_blast.out	Sample BLAST input used by init_test.sql

bin						Scripts that make up the heart of pdqBLAST
bin/pdqBLAST					Create a new pdqBLAST job
bin/pdqBLAST_show_config			Shows the current configuration in .pdqBLASTrc
bin/pdqBLAST_job_status				Display the status of a job and its work units
# the following should not be called directory and are intended to be called by pdqBLAST during exec/setup
bin/pdqBLAST_split_fasta			Chunk a FASTA input file into work units
bin/pdqBLAST_update_job_status			Update the status of a pdqBLAST job
bin/pdqBLAST_update_work_unit_status		Update the status of a pdqBLAST workunit
bin/pdqBLAST_load_work_unit_script		Load the input script to the scheduler for a work unit into the db
bin/pdqBLAST_load_work_unit_log			Load the log output from work unit steps into the db
bin/pdqBLAST_load_work_unit_blast_results	Load the BLAST results file (tab formatted) into the output table
bin/pdqBLAST_execute_work_unit			The central script executed for each work unit

test			Test scripts and jobs
test/go			Tiny submission against tiny test database
test/query.fasta	Tiny query fasta
test/go.big		'Big' query against RDP database
test/big_query.fasta	'Big' query fasta
test/go.huge		Huge query against RDP database

tmp			Where job temporary files reside
```

