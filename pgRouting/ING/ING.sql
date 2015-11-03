-- --------------------------------------------------------------------------------------------------------------
-- Nearest ING ATM in terms of routed distance or driving time
CREATE OR REPLACE FUNCTION ing_pgrdist(
	IN atm text,
	IN patm text,
	IN input_table text,
	IN car text,
	IN fastest text
	)
  RETURNS TABLE(scost double precision, pgdist float) AS
$BODY$
DECLARE
	sql text;
	g1 geometry;
	g2 geometry;
	p1 text;
	p2 text;
	dist double precision;
BEGIN
	sql := 'WITH t2t AS ' || input_table || ' SELECT the_geom::text FROM t2t WHERE num_atm=''' || atm || '''';
	EXECUTE sql INTO g1;
	sql := 'SELECT the_geom::text FROM "demo-admin".direcciones_popular WHERE num_atm=''' || patm || '''';
	EXECUTE sql INTO g2;
	p1 := 'ST_X(''' || g1::text || '''), ST_Y(''' || g1::text || ''')';
	p2 := 'ST_X(''' || g2::text || '''), ST_Y(''' || g2::text || ''')';
	RETURN QUERY EXECUTE 'SELECT SUM(cost) as scost, SUM(length) as pgdist FROM pgr_p2p(''routing_sp_ways'',' || p1 || ',' || p2 || ',''' || car || ''',''' || fastest || ''')';
END;
$BODY$
language 'plpgsql';

-- --------------------------------------------------------------------------------------------------------------
-- Finds the 3 (harcoded) nearest ATM in terms of linear distance
CREATE OR REPLACE FUNCTION ing_neighbors(
	IN atm_id text,
	IN input_table text
	)
  RETURNS TABLE(PATM text, dist integer)  AS
$BODY$
DECLARE
	geom geography;
BEGIN
	  EXECUTE 'WITH t2t as ' || input_table || ' SELECT the_geom::geography FROM t2t WHERE num_atm=''' || atm_id || '''' INTO geom;
	  RETURN QUERY EXECUTE 'SELECT p.num_atm::text as PATM, ST_distance(''' || geom::text || ''',p.the_geom::geography)::integer as dist'
	|| ' FROM "demo-admin".direcciones_popular as p'
	|| ' WHERE ST_distance(''' || geom::text || ''',p.the_geom::geography) > 0'
	|| ' ORDER BY ST_distance(''' || geom::text || ''',p.the_geom::geography) ASC LIMIT 3';
END;
$BODY$
LANGUAGE plpgsql;

-- --------------------------------------------------------------------------------------------------------------
-- Main function
CREATE OR REPLACE FUNCTION ing_core(
	IN input_table text,
	IN car text,
	IN fastest text,
	OUT id1 text,
	OUT id2 text,
	OUT dist integer,
	OUT pgdist integer,
	OUT t integer
	)
  RETURNS SETOF record AS
$BODY$
DECLARE
	rec0 record;
	rec1 record;
	rec2 record;
	sql0 text;
	sql1 text;
	sql2 text;
	sdist text;
BEGIN
	sql0 := 'WITH t2t as ' || input_table || ' SELECT num_atm, the_geom FROM t2t WHERE the_geom IS NOT NULL';
	FOR rec0 IN EXECUTE sql0
	LOOP
		sql1 := 'SELECT * FROM ing_neighbors(''' || rec0.num_atm || ''',''' || input_table || ''')';
		FOR rec1 IN EXECUTE sql1
		LOOP
			EXECUTE 'SELECT (scost*60) AS min, pgdist FROM ing_pgrdist('''
				|| rec0.num_atm || ''','''
				|| rec1.PATM || ''','''
				|| input_table || ''','''
				|| car || ''','''
				|| fastest || ''')' INTO rec2;
			id1 := rec0.num_atm::text;
			id2 := rec1.PATM::text;
			dist := rec1.dist::integer;
			pgdist := rec2.pgdist::integer;
			t := rec2.min::integer;
			RETURN NEXT;
		END LOOP;
		RETURN NEXT;
	END LOOP;
	RETURN;
END;
$BODY$
language 'plpgsql';

-- ------------------------------------------------------------------------------------------------------------
-- LAUNCHER
CREATE OR REPLACE FUNCTION ing_launch(
	IN output_table text,
	IN numberofcores integer
)
RETURNS text AS
$BODY$
DECLARE
	input_table text;
	tmp_table text;
	sql text;
	prim text;
	final text;
	msg text;
BEGIN
	input_table := '"demo-admin".direcciones_uso';
	-- harcoded flags car=true, fastest=true
	sql := 'SELECT * FROM ing_core(''''ing_tmp'''',''''true'''',''''true'''')';
	numberofcores := numberofcores - 2;
	EXECUTE 'CREATE TABLE IF NOT EXISTS ' || output_table || ' (id1 text, id2 text, dist integer, pgdist integer, t integer)';
	EXECUTE 'SELECT a.attname'
		|| ' FROM   pg_index i'
		|| ' JOIN   pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)'
		|| ' WHERE  i.indrelid =''' || input_table|| '''::regclass'
		|| ' AND    i.indisprimary;' INTO prim;
	EXECUTE 'CREATE TEMP TABLE ing_tmp AS SELECT * FROM ' || input_table;
	EXECUTE 'ALTER TABLE ing_tmp  ADD PRIMARY KEY (' || prim || ')';
	-- Parallelization query
	EXECUTE 'SELECT parsel('
		|| '''ing_tmp'', '
		|| '''' || prim::text || ''', '
		|| '''' || sql::text || ''', '
		|| '''' || output_table::text || ''', '
		|| '''input_alias'', '
		|| numberofcores::integer || ');' INTO final;
	EXECUTE 'DROP TABLE ing_tmp';
	RETURN final;
END;
$BODY$
language 'plpgsql';
