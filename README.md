# EGraphDB

Graph Database for building massively scalable and fault tolerant
systems.

> IMPORTANT: riak-core is removed for now.

## Overview


## Introduction

**TODO**

## Vision

The high level plan is as follows:

* Integrate into BeamParticle
* Visual web-frontend to explore data stored in the graph
* BeamParticle splits into various components largely
  to reduce its footprint
  (more details in the [BeamParticle](https://github.com/beamparticle/beamparticle) project
* Integrate to BeamParticleCore (smallest reprogrammable engine)
* Support multiple database backends (for example: PgSQL, Microsoft SQL Server, etc)
* Data partitioning for writing to different database backends
  to allow explosion in write IOPS beyond a single backend database master
* A lot more realtime monitoring

## Quick Tour

## Building and Running EgraphDB

Lets take a quick tour of the system and start with adding a couple of data
points, which in this case is list of countries.

Lets build and run the project as follows:

```bash

$ git clone https://github.com/neeraj9/egraphdb
$ cd egraphdb
$ ./rebar3 release
$ $(pwd)/_build/default/rel/egraph/bin/egraph console
```

## Adding Nodes to the Graph

Now in a separate window lets run curl commands to store information
as given in the json further below.

JSON from examples are as follows, which must be used for creating graph nodes.

* [india.json](examples/india.json)
* [usa.json](examples/usa.json)
* [japan.json](examples/japan.json)

The name of the json shall be key_data.json (say india.json, or usa.json),
which will subsequently used to while sending information to EGraphDB.

```bash
$ content_type='content-type: application/json'

$ curl -X POST -H "$content_type" -d@india.json "http://localhost:8001/detail"
$ curl -X POST -H "$content_type" -d@usa.json "http://localhost:8001/detail"
$ curl -X POST -H "$content_type" -d@japan.json "http://localhost:8001/detail"
```

The curl commands above uses the json as given below for India, USA and Japan.
It is important to note that the value of *key_data* must be globally unique,
otherwise EgraphDB shall overwrite previous node information with the same
primary key (which happens to be unique as well).

The value of *details* must be a json dictionary, while the value of *indexes*
must be generic index (*indexes*) and lowercase converted indexes
(*lowercase_indexes*). Note that indexes must be provided while creating
a node, so it must be clear that each node can have different indexes.
Additionally, the type of the indexes are derived from the json itself.

Possible types available for indexes are as follows:

* int
* double
* text
* geo
* date
* datetime

The above must be kept in mind, because these keywords shall be useful
when we run queries on the nodes created in the database.

### Querying Node Details

There are two ways to retrieve details of a node from EgraphDB.

The first one is to use the hash as returned in HTTP Response header
**location:** while creating the node.

```bash

$ curl "http://localhost:8001/detail/19181447080c72c9?keytype=rawhex"

```

Alternatively, you could use the value of **key_data** directly as well
(shown below).

```bash
$ curl "http://localhost:8001/detail/india"
```

### Searching Nodes by Index

You can use the indexes to find nodes which exists in the database as follows.
Lets find the hash-id for nodes which have **INR** as currency.

```bash

$ curl "http://localhost:8001/index/INR?keytype=text&indexname=currency"

```

The above curl command will give list of hash-ids which can then be used
to retrieve node details.

### Linking Nodes

Lets link India to USA as follows, wherein there are around 1.1 million
tourists from India to USA in 2017.

```json
{
    "source" : "india",
    "destination" : "usa",
    "details" : {
        "distance_km": 13568,
        "capital_flight_time_hours": 15.5,
        "yearly_tourists": 1100000
    }
}
```

You can now query the link via hash of source (india) and destination (usa).

```bash
$ curl "http://localhost:8001/link/19181447080c72c9?destination=ccf364f81fc02db9&keytype=rawhex"
```

Alternatively, you can use the value of the primary key (**source** and
**destination**) as follows:

```bash
$ curl "http://localhost:8001/link/india?destination=usa"
```

If you omit **destination** query parameter then it will give all destinations
from india (see below).

```bash
$ curl "http://localhost:8001/link/india"
```

### N Depth Graph Traversal

Lets traverse and list all connections originating from a given source
node with a maxdepth as well (see below).

```bash
$ curl "http://localhost:8001/v1/search/india?maxdepth=1"
```

> Note that a value of maxdepth = 1 will search level-2 nodes.

### DFS (only one path)

There is a fun little implementation of DFS (Depth First Search), wherein
the datastore shall return one path found via applying DFS on the
stored graph database.

```bash
$ curl "http://localhost:8001/v1/search/india?destination=usa&traverse=dfs"
```

### A Little More Complex Search

Lets perform a little more complex search on the datastore, wherein
all the conditions are applied with an **OR** condition (or union).
Additionally, selected node information is retrieved for the
matching nodes instead of getting everything.

```bash
content_type='content-type: application/json'
$ curl -X POST -H "$content_type" -H "$content_type" -d@query.json "http://localhost:8001/v1/search"
```

> The json within query.json is as shown below.

The following JSON shall be used for performing generic search via
HTTP POST.

> For the sake of shown range filter there are two
> filters applied for geography.water_percent.

```json
{
    "query": {
        "type": "index",
        "conditions" : {
            "any": [
                {"key": "INR",
                 "key_type": "text",
                 "index_name": "currency"},
                {"key": "tokyo",
                 "key_type": "text",
                 "index_name": "capital_lc__"},
                {"key": [1.0, 50.0],
                 "key_type": "double",
                 "index_name": "water_percent"}
            ],
            "filters": [
                {
                    "key": "India",
                    "key_type": "text",
                    "index_json_path": ["details", "name"]
                },
                {
                    "key": 9.6,
                    "key_type": "double",
                    "index_json_path": ["details", "geography", "water_percent"]
                },
                {
                    "key": [0.6, 10.2],
                    "key_type": "double",
                    "index_json_path": ["details", "geography", "water_percent"]
                }
            ]
        },
        "selected_paths": {
                             "name":  ["details", "name"],
                             "religions": ["details", "religions"],
                             "water_percent": ["details", "geography", "water_percent"]
                          }
    }
}
```

## Building on Ubuntu

> Download and install Erlang from
> https://www.erlang-solutions.com/resources/download.html
 
    sudo apt-get install build-essential
    sudo apt-get install libssl-dev

## Building on Microsoft Windows

> Download and install Erlang from
> https://www.erlang-solutions.com/resources/download.html

## Build

### Clean 

    ./rebar3 clean egraph

### Clean all 

    ./rebar3 clean -a

### Release build

    ./rebar3 release

### Prod build

    ./rebar3 as prod tar
    
## Running app in shell mode

    ./rebar3 shell --apps egraph

## Running shell will all the code

    erl -pa _build/default/lib/*/ebin
    
## Testing and Creating Code Coverage

**TODO**
    
### EUnit Testing

**TODO**

## Generating Code Documentation

The code documentation is generated via [edoc](http://erlang.org/doc/apps/edoc/chapter.html) as follows:

    ./rebar3 edoc

The output is generated in doc/ subfolder.

## observer OMS erlang node

> cookiename is mentioned in vm.args

    erl -name observer@127.0.0.1 -setcookie 'SomeCookie' -run observer

## Code Style

The code style must be validated by [elvis](https://github.com/inaka/elvis),
which does a good job at style reviewing. The repository will be setup (in the
future) such that each of the commit must be automatically reviewed by
elvis before it can be submitted.

### To run elvis for project

    ./elvis rock

### To run elvis for single file

    ./elvis rock <filename>

## References

* <http://egraphdb.org>


