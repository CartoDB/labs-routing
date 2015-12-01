# OSMR

The **Open Source Routing Machine** or OSRM is a C++ implementation of a high-performance routing engine for shortest paths in road networks. Licensed under the permissive 2-clause BSD license, OSRM is a free network service. OSRM supports Linux, FreeBSD, Windows, and Mac OS X platform.

It combines sophisticated routing algorithms with the open and free road network data of the OpenStreetMap (OSM) project. Shortest path computation on a continental sized network can take up to several seconds if it is done without a so-called speedup-technique. OSRM uses an implementation of Contraction Hierarchies and is able to compute and output a shortest path between any origin and destination within a few milliseconds, whereby the pure route computation takes much less time. Most effort is spent in annotating the route and transmitting the geometry over the network.

Since it is designed with OpenStreetMap compatibility in mind, OSM data files can be easily imported. A demo installation is sponsored by Karlsruhe Institute of Technology and previously by Geofabrik. OSRM is under active development. The screen shot image shown is since Sept 2015 out of date with loss of attendant routing service features.

OSRM was part of the 2011 Google Summer of Code class.

Source: [Wikipedia](https://en.wikipedia.org/wiki/Open_Source_Routing_Machine)

Project homepage: http://project-osrm.org/

Demo server: http://map.project-osrm.org/s

**Notes:**

* OSRM backend builds all the possible routes prior to use the server, so the UX is great
* An OSRM instance doesn't need PostGIS (or CartoDB). It uses its own indexed files format

## Installation

[Reference](https://github.com/Project-OSRM/osrm-backend/wiki/Building-OSRM)
[Tutorial, Ubuntu 14.04](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-osrm-server-on-ubuntu-14-04)

* You need to build OSRM from the sources
* Tipically, in an Ubuntu instance, you need first to install the dependencies. For 15.04 it would be like:

```bash
sudo apt-get install build-essential git cmake pkg-config \
libbz2-dev libstxxl-dev libstxxl1 libxml2-dev \
libzip-dev libboost-all-dev lua5.1 liblua5.1-0-dev libluabind-dev libluajit-5.1-dev libtbb-dev
```

* Then, download and compile the sources:

```bash
git clone https://github.com/Project-OSRM/osrm-backend.git
cd osrm-backend
mkdir -p build
cd build
cmake ..
make
sudo make install
```

(If you have multiple cores available to build you can also pass '-j x' to the make command where **x** is the number of cores to use.)

## Setting up the data

### Download the dataset

```bash
wget http://planet.osm.org/planet/planet-latest.osm.bz2
```

### Link the speed profiles and extract the routing data from the whole dataset

There are several profiles available as car.lua, bicycle.lua, bike-routing.lua,... You can use only one at a time! So you can generate different datasets for each kind of route.

```bash
ln -s ../profiles/car.lua profile.lua
ln -s ../profiles/lib/

```

Then:

```bash
./osrm-extract planet-latest.osm.bz2
```

**Timing:** 6-8h per profile

**Peak Memory:** 8GB
(16cores, 160GB RAM)

### Prepare the data

Generate precomputed data to find optimal routes within short time.

```bash
./osrm-prepare  planet-latest.osrm
```

**Timing:** 8-20h per profile

**Peak Memory:** 120-150GB
(16cores, 160GB RAM)

### Run!

```bash
./osrm-routed   planet-latest.osrm
```

**Peak Memory:** 30-45GB
(16cores, 160GB RAM)

## Tweaking

[Blog post](https://www.mapbox.com/blog/osrm-shared-memory/)
[Reference](https://github.com/Project-OSRM/osrm-backend/wiki/Configuring-and-using-Shared-Memory)

Let's load all the shared memory directly into RAM. Once you have set up the shared memory as stated in reference, you can load the data into shared memory:

```bash
./osrm-datastore planet-latest.osrm
```

And then, start the routing process (server) and pointing it to shared memory:

```bash
./osrm-routed --shared-memory=yes
```

## Using the server

[Reference](https://github.com/Project-OSRM/osrm-backend/wiki/Server-api)

The HTTP interface provided by osrm-routed (partially) implements HTTP 1.1 and serves queries much like normal web servers do:

```
http://{server address}/{service}?{parameter}={value}
```

And gives back a response in **JSON** format.

```javascript
{
  status: 0,
  status_message: "Message text",
  .....
}
```

### Available services

* **viaroute:** shortest path between given coordinates
* **nearest:** returns the nearest street segment for a given coordinate (snap to street)
* **locate:** returns coordinate snapped to nearest node (snap to node)
* **table:** computes distance tables for given coordinates
* **match:** matches given coordinates to the road network (vg.: fit GPS positions to the plausible actual route)
* **trip:** Compute the shortest round trip between given coordinates ([Traveling Salesman Problem](https://en.wikipedia.org/wiki/Travelling_salesman_problem))

Check the [reference](https://github.com/Project-OSRM/osrm-backend/wiki/Server-api) for full info.

