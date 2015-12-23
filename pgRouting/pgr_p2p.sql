-- ******* --
-- PGR_P2P --
-- ******* --
-- This is the function that computes the optimal route between two points
-- INPUT
-- -- tbl [string] name of the edges table, typically "ways" (in our test case: "routing_sp_ways")
-- -- x1, y1 [double],[double] lng, lat of initial point (EPSG:4326)
-- -- x2, y2 [double],[double] lng, lat of final point (EPSG:4326)
-- -- car [string] 'true' or 'false'. This flag modifies the routing method to take into account the direction of the ways and the eventual driving restrictions (walkways, steps, and so on)
-- -- fastest [string] 'true' or 'false'. This flag changes the the strategy to find the optimal route from shortest to fastest. There is no use to set it to true when car is set to false.
-- OUTPUTs an array of recordsets
-- -- sec [integer] Index of the segment within the whole route
-- -- gid [integer] ID of the segment in [tbl]
-- -- ame [string] Name of the segment if any (vg. street name)
-- -- heading [double] Heading
-- -- cost [double] Cost of the segment
-- -- geom [geometry] Linestring (EPSG:4326)
-- -- length [double] Length of the segment (meters)

CREATE OR REPLACE FUNCTION public.pgr_p2p(
    tbl character varying,
    x1 double precision,
    y1 double precision,
    x2 double precision,
    y2 double precision,
    car character varying,
    fastest character varying,
    OUT seq integer,
    OUT gid integer,
    OUT name text,
    OUT heading double precision,
    OUT cost double precision,
    OUT geom geometry,
    OUT length double precision)
RETURNS SETOF record
    AS $function$
DECLARE
    sql0     text;
    sql1     text;
    mycost text;
    myrcost text;
    mylength text;
    sql     text;
    restricted text;
    rec     record;
    p1  integer;
    p2  integer;
    buff  double precision;
    point   integer;
    tmp record;
BEGIN
    -- for limiting the scope of the node search, 0.009deg per km
    buff := 0.05;
    -- Find source and target IDs
    EXECUTE 'SELECT id::integer FROM routing_sp_ways_vertices_pgr ORDER BY the_geom <-> ST_GeometryFromText(''POINT('
        || x1 || ' ' || y1 || ')'',4326) LIMIT 1' INTO rec;
    p1 := rec.id;
    EXECUTE 'SELECT id::integer FROM routing_sp_ways_vertices_pgr ORDER BY the_geom <-> ST_GeometryFromText(''POINT('
        || x2 || ' ' || y2 || ')'',4326) LIMIT 1' INTO rec;
    p2 := rec.id;
    seq := 0;
    -- Set the type of route
    IF fastest='true' THEN
        RAISE NOTICE 'Fastest route';
        IF car = 'false' THEN
            RAISE NOTICE 'Walking route';
            mycost := '(length/4)';
            myrcost := '(reverse_cost/4)::float AS reverse_cost';
        ELSE
            RAISE NOTICE 'Pedestrian route';
            mycost := '(length/maxspeed_forward)';
            myrcost := '(reverse_cost/maxspeed_backward)::float AS reverse_cost';
        END IF;
        mylength := 'ST_Length(ST_Transform(the_geom,3857))';
    ELSE
        RAISE NOTICE 'Shortest route';
        mycost := 'length';
        myrcost := 'reverse_cost';
        mylength := '(cost*1000)';
    END IF;
    -- Dijkstra query
    sql0 := 'SELECT gid as id, source, target, '
        || mycost || '::float AS cost, '
        || myrcost || ' FROM '|| quote_ident(tbl)
         -- http://ghost.mixedbredie.net/improving-pgrouting-performance/ Expected improvement x3, up to x20
        || ' WHERE the_geom && ST_Expand((SELECT ST_Collect(the_geom) FROM routing_sp_ways_vertices_pgr WHERE id IN ('|| p1 || ', ' || p2 || ')), ' || buff || ')';
    IF car = 'true' THEN
        -- OSM restricted ways IDs
        -- http://wiki.openstreetmap.org/wiki/OSM_tags_for_routing/Access-Restrictions
        restricted := ' AND class_id NOT IN (114, 117, 118, 119, 120, 122)';
        sql1 := sql0 || restricted;
    ELSE
        sql1 := sql0;
    END IF;
    -- Core query 0
    sql :=  'SELECT gid, the_geom, name, cost, source, target, ST_Reverse(the_geom) AS flip_geom, '
        || mylength || ' AS mylength FROM '
        || 'pgr_dijkstra(' || quote_literal(sql1) || ', '|| p1 || ', ' || p2 || ' , '|| car ||', '|| car ||'), '|| quote_ident(tbl) || ' WHERE id2 = gid'
        -- Sanitize topology network
        || ' AND length != 0 AND the_geom IS NOT NULL ORDER BY seq;';
    -- first point
    point := p1;
    FOR rec IN EXECUTE sql
    LOOP
        IF ( point != rec.source ) THEN
            rec.the_geom := rec.flip_geom;
            point := rec.source;
        ELSE
            point := rec.target;
        END IF;
        -- Heading
        EXECUTE 'SELECT degrees( ST_Azimuth('
            || 'ST_StartPoint(''' || rec.the_geom::text || '''),'
            || 'ST_EndPoint(''' || rec.the_geom::text || ''') ) )'
            INTO heading;
        seq     := seq + 1;
        gid     := rec.gid;
        name    := rec.name;
        cost    := rec.cost;
        geom    := rec.the_geom;
        length  := rec.mylength;
        RETURN NEXT;
    END LOOP;
    RETURN;
    EXCEPTION WHEN OTHERS THEN
        raise notice 'EXCEPTION: % %', SQLERRM, SQLSTATE;
        heading := 0;
        seq     := seq + 1;
        gid     := -1;
        name    := '';
        cost    := 0;
        geom    := null;
        length  := 0;
END;
$function$
LANGUAGE plpgsql VOLATILE STRICT
    COST 100
    ROWS 1000;

-- Grant postgres user
ALTER FUNCTION pgr_p2p(character varying, double precision, double precision, double precision, double precision,character varying,character varying)
  OWNER TO postgres;
