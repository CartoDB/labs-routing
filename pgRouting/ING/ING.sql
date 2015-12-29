-- --------------------------------------------------------------------------------------------------------------
-- Nearest ING ATM in terms of routed distance or driving time
CREATE OR REPLACE FUNCTION ing_pgrdist(
    IN atm integer,
    IN patm integer,
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
    sql := 'WITH t2t AS ' || input_table || ' SELECT the_geom::text FROM t2t WHERE id_dom=' || atm;
    EXECUTE sql INTO g1;
    sql := 'SELECT the_geom::text FROM atmgratis1 WHERE id_atm=' || patm ;
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
    IN atm_id integer,
    IN input_table text
    )
  RETURNS TABLE(PATM text, dist integer)  AS
$BODY$
DECLARE
    geom geography;
    red text;
BEGIN
    red := 'atmgratis1';
    EXECUTE 'WITH t2t as ' || input_table || ' SELECT the_geom::geography FROM t2t WHERE id_dom=' || atm_id INTO geom;
    RETURN QUERY EXECUTE 'WITH distance as('
    || 'SELECT p.id_atm::text as PATM, ST_distance(''' || geom::text || ''', p.the_geom::geography)::integer as dist'
    || ' FROM ' || red || ' as p'
    || ')'
    || ' SELECT * FROM distance'
    || ' WHERE dist > 0'
    || ' ORDER BY dist ASC limit 3';
END;
$BODY$
LANGUAGE plpgsql;

-- --------------------------------------------------------------------------------------------------------------
-- Main function
CREATE OR REPLACE FUNCTION ing_core(
    IN input_table text,
    IN car text,
    IN fastest text,
    OUT id1 bigint,
    OUT id2 bigint,
    OUT dist bigint,
    OUT pgdist bigint,
    OUT t bigint
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
    sql0 := 'WITH t2t as ' || input_table || ' SELECT id_dom, the_geom FROM t2t WHERE the_geom IS NOT NULL';
    FOR rec0 IN EXECUTE sql0
    LOOP
        sql1 := 'SELECT * FROM ing_neighbors(''' || rec0.id_dom || ''',''' || input_table || ''')';
        FOR rec1 IN EXECUTE sql1
        LOOP
            EXECUTE 'SELECT (scost*60) AS min, pgdist FROM ing_pgrdist('
                || rec0.id_dom || ','
                || rec1.PATM || ','''
                || input_table || ''','''
                || car || ''','''
                || fastest || ''')' INTO rec2;
            id1 := rec0.id_dom;
            id2 := rec1.PATM;
            dist := rec1.dist::bigint;
            pgdist := rec2.pgdist::bigint;
            t := rec2.min::bigint;
            -- RAISE NOTICE '% -  %', id1, id2;
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
    input_table := 'domicilios1';
    -- harcoded flags car = 'true', fastest = 'true'
    sql := 'SELECT * FROM ing_core(''''ing_tmp'''',''''false'''',''''false'''')';
    numberofcores := numberofcores - 2;
    -- EXECUTE 'CREATE TABLE IF NOT EXISTS ' || output_table || ' (id1 text, id2 text, dist integer, pgdist integer, t integer)';
    EXECUTE 'SELECT a.attname'
        || ' FROM   pg_index i'
        || ' JOIN   pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)'
        || ' WHERE  i.indrelid =''' || input_table|| '''::regclass'
        || ' AND    i.indisprimary;' INTO prim;
    -- EXECUTE 'DROP TABLE IF EXISTS ing_tmp';
    -- EXECUTE 'CREATE TABLE IF NOT EXISTS ing_tmp AS SELECT * FROM ' || input_table;
    -- EXECUTE 'ALTER TABLE ing_tmp  ADD PRIMARY KEY (' || prim || ')';
    -- Parallelization query
    EXECUTE 'SELECT parsel('
        || '''ing_tmp'', '
        || '''' || prim::text || ''', '
        || '''' || sql::text || ''', '
        || '''' || output_table::text || ''', '
        || '''input_alias'', '
        || numberofcores::integer || ');' INTO final;
    -- EXECUTE 'DROP TABLE IF EXISTS ing_tmp';
    RETURN final;
END;
$BODY$
language 'plpgsql';
