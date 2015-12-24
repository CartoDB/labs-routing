# pgRouting tests

## Test environment

* AMI 1.0.8 & pgRouting 2.0
* Test machine @ http://solutions.onpremise.local (demo-admin:test) 16 * 2.8GHz CPU, 30GB RAM

## References

* [pgRouting docs](http://pgrouting.org/documentation.html)
* [pgRouting Workshop](http://workshop.pgrouting.org/index.html)
* [OSM to pgRouting](http://pgrouting.org/docs/tools/osm2pgrouting.html)

## Install (within container)

```sh
sudo add-apt-repository ppa:georepublic/pgrouting
sudo apt-get update
sudo apt-get install postgresql-9.3-pgrouting
```

## Download OSM dataset (optional)

The main OSM data repos are:
* Cities: https://mapzen.com/data/metro-extracts
* Countries: http://download.geofabrik.de/

Then:

```sh
mkdir /home/pgrouting
mkdir /home/pgrouting/mydataset
sudo chmod 777 /home/pgrouting/mydataset
cd /home/pgrouting/mydataset
wget http://download.geofabrik.de/whatever/whatever-latest.osm.bz2
bzip2 -d whatever-latest.osm.bz2
```

**NOTE:** Download size for a country like [Spain](http://download.geofabrik.de/europe/spain-latest.osm.bz2) is ~ 0.8GB (~35min for downloading), once expanded ~11.1GB. The downloaded file contains the whole OSM dataset, and we only need the ways so the final tables are supposed to be smaller than this.

## Install extension to user' DB

```sh
psql -U postgres
```

```sql
\c "cartodb-.....-db"
CREATE EXTENSION pgrouting;
```

## Load dataset from OSM into user DB (optional)

First of all, you will need to avoid timeouts:

```sh
psql -U postgres
```

```sql
SET statement_timeout=0;
\q
```

And then

```sh
sudo apt-get install osm2pgrouting
cd /home/pgrouting/mydataset
time osm2pgrouting -file "whatever-latest.osm" -conf "/usr/share/osm2pgrouting/mapconfig.xml" -dbname cartodb_user_..._db -user postgres -host localhost -prefixtables "routing_sp_" -clean
```
It takes ~ 2h to upload the whole Spain's network (32cores, 60GB RAM)

**NOTE:** Looks like the topology sanitization of OSM2pgRouting is not as good as expected. If you use your own function to cal pgr_dijkstra(), then add this to your query (like pgr_p2p.sql:59)

```sql
... AND length != 0 AND the_geom IS NOT NULL ...
```


**CHEAT:** If the command exits with a "killed" message, may be due to a OOM error. Typical onpremise instance has no swap file, so we should follow [this method](https://www.digitalocean.com/community/tutorials/how-to-add-swap-on-ubuntu-14-04) to avoid this kind of error creating a swapfile ~2x the size of installed RAM

**NOTE:** We have used "routing_sp_" as pgRouting tables prefix (in order to have pgRouting related tables tagged), but this is optional

## Point to Point route procedure (pgr_p2p)

We will use [Dijkstra's algorithm](https://en.wikipedia.org/wiki/Dijkstra%27s_algorithm) for our optimal route search. This is a cost based algorithm, and this cost may point to any segment' attribute you would want to use as decisive factor. In this sample procedure we will use distance (segment length) as the cost parameter.

This function, takes as inputs:
* **tbl** [string] name of the edges table, typically "ways" (in our test case: "_routing_sp_ways_")
* **x1, y1** [double],[double] lng, lat of initial point (EPSG:4326)
* **x2, y2** [double],[double] lng, lat of final point (EPSG:4326)
* **car** [string] 'true' or 'false'. This flag modifies the routing method to take into account the direction of the ways and the eventual driving restrictions (walkways, steps, and so on)
* **fastest** [string] 'true' or 'false'. This flag changes the the strategy to find the optimal route from shortest to fastest. There is no use to set it to true when **car** is set to false.

Then, it returns an array of segments as recordset:
* **sec** [integer] Index of the segment within the whole route
* **gid** [integer] ID of the segment in [tbl]
* **name** [string] Name of the segment if any (vg. street name)
* **heading** [double] Heading
* **cost** [double] Cost of the segment
* **geom** [geometry] Linestring (EPSG:4326)
* **length** [double] Length of the segment (meters)

Processing time vs route length in km (ms/km)

![time-distance](http://i.imgur.com/sht1zwO.jpg?!)

The performance of this function compared to the standard one is related to the distance between the studied points. This chart represents the improvement ratio vs. distance in km.

![improvement](http://i.imgur.com/KHRIu1U.jpg)


## Sample queries to find the optimal route between two points

Pedestrian route as single Linestring and distance (Km) as attribute, ready for CartoDB

```sql
WITH route AS (
    SELECT ST_Transform(geom,3857) as the_geom, cost as distance FROM pgr_p2p('routing_sp_ways', -3.75,40.40, -3.70,40.40, 'false', 'false') ORDER BY seq
)
SELECT ST_MakeLine(route.the_geom) as the_geom_webmercator, SUM(cost) FROM route;
```

Driving route distance (Km) and duration for the fastest route:

```sql
SELECT sum(length) as distance, sum(cost) as duration FROM pgr_p2p('routing_sp_ways', -3.75,40.40, -3.70,40.40,'true','true');
```

## Parallelizing queries

Due to [this](https://wiki.postgresql.org/wiki/FAQ#How_does_PostgreSQL_use_CPU_resources.3F) a PostgreSQL query runs in a single CPU, no matter how many cores has your data blender machine. Our target was to saturate each core to be as fast as possible. Using [parsel](http://geeohspatial.blogspot.com.es/2013/12/a-simple-function-for-parallel-queries_18.html) (but [this fork](https://gist.github.com/minus34/53570f5f274c30bc44e3) instead) we have managed to lower the processing time from 100h to 45h in 1st try and 26h in 2nd try (ING testcase).

**parsel()** requires **dblink** extension.

```sql
CREATE EXTENSION dblink;
```

Check **ing_launch()** function at **ING.sql** to check a sample use of this function.

**NOTE:** [pmpp](https://github.com/moat/pmpp) extension will be tested againsta **parsel** in near future.

## So far
* Looks like pgRouting doesn't break CartoDB
* Cloud client: using a minimal impact deployment, the user must process the data prior to upload them to CartoDB. The data structure must fit the one defined by pgRouting for each and every table.
* On-premise user: osm2pgrouting is available, so is the process described above
* Processing time in current on-premise instance is a bit... crappy. No way to using pgRouting for real processing

Results could look like this:
![WIN!](http://i.imgur.com/06oXrSK.jpg?1)

## Cheats
* (Cloud client) The non-spatial tables should be uploaded as CSV, and the max_import_table_row_count parameter might need to be tweaked (you will have a lot of nodes for sure)
* (Cloud client) Once you have all the data in **your own postgreSQL**, looks like you need QGIS to export a valid shape file from ways and ways_vertices_pgr tables. For non-spatial tables, use the command

```sql
psql -U user_name -d db_name -c "COPY table_name TO stdout DELIMITER ',' CSV HEADER;" > table_name.csv
```

* (On-premise user) Maybe you need to check table permissions to GRANT SELECT to **publicuser** and **cartodb_user_...** to **every** table needed by pgrouting.
* You may need/want to check and edit if needed the 'restricted' var in the pgr_p2p function according to the country. Ref.: [Driving restrictions by country](http://wiki.openstreetmap.org/wiki/OSM_tags_for_routing/Access-Restrictions)
