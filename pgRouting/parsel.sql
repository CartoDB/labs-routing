
-- https://gist.github.com/minus34/53570f5f274c30bc44e3

-- DROP FUNCTION public.parsel(table_to_chunk text, pkey text, query text, output_table text, table_to_chunk_alias text, num_chunks integer);
CREATE OR REPLACE FUNCTION public.parsel(table_to_chunk text, pkey text, query text, output_table text, table_to_chunk_alias text, num_chunks integer)
  RETURNS text AS
$BODY$
DECLARE
  checkint integer;
  checkbool boolean;
  dbname text;
  portnum text;
  username text;
  pword text;
  connectstring text;
  sql text;
  min_id integer;
  max_id integer;
  step_size integer;
  lbnd integer;
  ubnd integer;
  subquery text;
  insert_query text;
  i integer;
  conn text;
  n integer;
  num_done integer;
  status integer;
  dispatch_result integer;
  dispatch_error text;
  part text;
  rand text;
  output_table_cleaned text;

BEGIN

  RAISE NOTICE 'Inserting into % : %', output_table, query;


  -- GET DB NAME AND PORT NUMBER

  -- get calling database name
  sql := 'SELECT current_database();';
  EXECUTE sql INTO dbname;

--   --get calling database schema name
--   sql := 'SELECT current_schema();';
--   EXECUTE sql INTO schemaname;

  --get calling database port (required for dblink when more than one version of Postgres installed)
  sql := 'SELECT setting FROM pg_settings WHERE name = ''port'';';
  EXECUTE sql INTO portnum;


  ---------------------------------------------------------------------------
  -- TO DO: edit your user name and/or password and/or connect string here --
  ---------------------------------------------------------------------------

  username := 'postgres';
--  pword :=  '<a password>';

--  connectstring := QUOTE_LITERAL('dbname=' || dbname || ' user=' || username || ' password=' || pword || ' port=' || portnum);
  connectstring := QUOTE_LITERAL('dbname=' || dbname || ' user=' || username || ' port=' || portnum);
--  connectstring := QUOTE_LITERAL('dbname=' || dbname || ' port=' || portnum);

  ------------------------------------------------------------------
  -- END TO DO
  ------------------------------------------------------------------


  -- CHECKING INPUT PARAMETERS

  -- Check table to chunk exists
  sql := 'SELECT position(''.'' in ' || QUOTE_LITERAL(table_to_chunk) || ');'; -- first check if there's a dot signifying a schema prefix
  EXECUTE sql INTO checkint;

  IF checkint > 0 THEN
	sql := 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_schema || ''.'' || table_name = ' || QUOTE_LITERAL(table_to_chunk) || ' );'; -- check schema.table exists
  ELSE
	sql := 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name = ' || QUOTE_LITERAL(table_to_chunk) || ' );'; -- check table exists (no schema prefix)
  END IF;
  EXECUTE sql INTO checkbool;

  IF NOT checkbool THEN
	RAISE EXCEPTION 'TABLE TO CHUNK DOESN''T EXIST - CANNOT CONTINUE!';
	EXIT;
  END IF;

  -- Check table to insert into exists using the above logic
  sql := 'SELECT position(''('' in ' || QUOTE_LITERAL(output_table) || ');';
  EXECUTE sql INTO checkint;

  IF checkint > 0 THEN
	sql := 'SELECT TRIM(SUBSTRING(' || QUOTE_LITERAL(output_table) || ', 1, ' || checkint || ' - 1));';
	EXECUTE sql INTO output_table_cleaned;
  ELSE
	output_table_cleaned := output_table;
  END IF;

  sql := 'SELECT position(''.'' in ' || QUOTE_LITERAL(output_table_cleaned) || ');';
  EXECUTE sql INTO checkint;

  IF checkint > 0 THEN
	sql := 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_schema || ''.'' || table_name = ' || QUOTE_LITERAL(output_table_cleaned) || ' );';
  ELSE
	sql := 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name = ' || QUOTE_LITERAL(output_table_cleaned) || ' );';
  END IF;
  EXECUTE sql INTO checkbool;

  IF NOT checkbool THEN
	RAISE EXCEPTION 'OUTPUT TABLE DOESN''T EXIST - CANNOT CONTINUE!';
	EXIT;
  END IF;

  -- Check if input table to chunk is actually in the query (well duh, but it causes a silent error which can lead to having to kill processes manually or a restart of Postgres!)
  sql := 'SELECT position(' || QUOTE_LITERAL(table_to_chunk) || ' in ' || QUOTE_LITERAL(query) || ');';
  EXECUTE sql INTO checkint;

  IF checkint = 0 THEN
	RAISE EXCEPTION 'TABLE TO CHUNK NOT IN QUERY - CANNOT CONTINUE!';
	EXIT;
  END IF;

  -- Check table has a few more rows than processes and reduce process count if required (NOT TESTED THOROUGHLY)
  sql := 'SELECT Count(*) FROM ' || table_to_chunk || ';';
  EXECUTE sql INTO checkint;

  IF checkint = 0 THEN -- if no rows then exit
	RAISE EXCEPTION 'TABLE TO CHUNK HAS NO ROWS - CANNOT CONTINUE!';
	EXIT;
  END IF;

  IF checkint < num_chunks THEN
	num_chunks = checkint;
	RAISE NOTICE 'Number of processes reduced due to small number of table to chunk rows';
  END IF;


  -- GET MIN/MAX IDs AND NUMBER OF RECORDS TO PROCESS, PER PROCESS

  -- find minimum pkey id
  sql := 'SELECT min(' || pkey || ') from ' || table_to_chunk || ';';
  EXECUTE sql INTO min_id;

  -- find maximum pkey id
  sql := 'SELECT max(' || pkey || ') from ' || table_to_chunk || ';';
  EXECUTE sql INTO max_id;

  -- determine size of chunks based on min id, max id, and number of chunks
  sql := 'SELECT ( ' || max_id || '-' || min_id || ')/' || num_chunks - 1 || ';';
  EXECUTE sql INTO step_size;


  -- CREATE EACH DBLINK CONNECTION TO PROCESS A CHUNK OF WORK IN A SEPARATE PROCESS

  FOR lbnd, ubnd, i IN
	SELECT  generate_series(min_id, max_id, step_size) as lbnd,
		generate_series(min_id + step_size, max_id + step_size, step_size) as ubnd,
		generate_series(1, num_chunks) as i
  LOOP
	-- for debugging
	-- RAISE NOTICE 'Chunk %: % >= % and % < %', i, pkey, lbnd, pkey, ubnd;

	-- make a new db connection
	conn := 'conn_' || i;
	sql := 'SELECT dblink_connect(' || QUOTE_LITERAL(conn) || ',' || connectstring || ');';
	EXECUTE sql;

	-- create a subquery string that will replace the table name in the original query
	part := '(SELECT * FROM ' || table_to_chunk || ' WHERE ' || pkey || ' >= ' || lbnd || ' AND ' || pkey || ' < ' || ubnd || ') ';

	-- edit the input query using the subsquery string
	sql := 'SELECT REPLACE(' || QUOTE_LITERAL(query) || ',' || QUOTE_LITERAL(table_to_chunk) || ',' || QUOTE_LITERAL(part) || ');';
	EXECUTE sql INTO subquery;

	insert_query := 'INSERT INTO ' || output_table || ' ' || subquery || ';';
	-- RAISE NOTICE 'Connection % : %', i, insert_query;

	-- send the query asynchronously using the dblink connection
	sql := 'SELECT dblink_send_query(' || QUOTE_LITERAL(conn) || ',' || QUOTE_LITERAL(insert_query) || ');';
	EXECUTE sql INTO dispatch_result;

	-- check for errors dispatching the query
	IF dispatch_result = 0 THEN
	sql := 'SELECT dblink_error_message(' || QUOTE_LITERAL(conn)  || ');';
	EXECUTE sql INTO dispatch_error;
		RAISE '%', dispatch_error;
	END IF;

  END LOOP;


  -- WAIT UNTIL ALL QUERIES ARE FINISHED

  LOOP
	num_done := 0;

	FOR i IN 1..num_chunks
	LOOP
	  conn := 'conn_' || i;
	  sql := 'SELECT dblink_is_busy(' || QUOTE_LITERAL(conn) || ');';
	  EXECUTE sql INTO status;

	  IF status = 0 THEN
		-- check for error messages
		sql := 'SELECT dblink_error_message(' || QUOTE_LITERAL(conn)  || ');';
		EXECUTE sql INTO dispatch_error;
		IF dispatch_error <> 'OK' THEN
		  RAISE '%', dispatch_error;
		END IF;

		num_done := num_done + 1;
	  END if;
	END LOOP;

	IF num_done >= num_chunks THEN
	  EXIT;
	END IF;

  END LOOP;

  -- disconnect the dblinks
  FOR i IN 1..num_chunks
  LOOP
	conn := 'conn_' || i;
	sql := 'SELECT dblink_disconnect(' || QUOTE_LITERAL(conn) || ');';
	EXECUTE sql;
  END LOOP;

  RETURN 'Success';

  -- error catching to disconnect dblink connections, if error occurs
  EXCEPTION WHEN others THEN
	BEGIN
	  RAISE NOTICE '% %', SQLERRM, SQLSTATE;
	  FOR n IN
		SELECT generate_series(1,i) as n
	  LOOP
		conn := 'conn_' || n;
		sql := 'SELECT dblink_disconnect(' || QUOTE_LITERAL(conn) || ');';
		EXECUTE sql;
	  END LOOP;

	  EXCEPTION WHEN others THEN
		RAISE NOTICE '% %', SQLERRM, SQLSTATE;
	END;

END;
$BODY$
  LANGUAGE plpgsql STABLE
  COST 100;
