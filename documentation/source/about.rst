.. _about:

=====
About
=====

Introduction
============

.. note:: Documentation and testing is lacking, but you will see some
          action both of these fronts. Till then happy hacking around.
          Additionally, you are most welcome to make contributions.

Motivations
===========

Architecture
============

The client uses HTTP interface to interract with EGraph and
which in turns interract with the backend (in this case MySQL).

.. graphviz::

    digraph {
        client -> egraph [label="HTTP 1.1\n JSON or x-erlang-binary"];
        egraph -> mysql [label="Pool of\n MySQL connections"];

        client -> egraph2;
        egraph2 -> mysql2;

        client -> egraph3;
        egraph3 -> mysql3;

        // egraph -> egraph2 -> egraph3;
        // egraph2-> egraph -> egraph3;
        // egraph3-> egraph2 -> egraph;
    }

The basic construct of *id* which you would see in hexadecimal
notation within the examples further below is basically
xxhash64 of **key_data** (passed in HTTP POST). Given the fact
that **key_data** passed in the HTTP POST body while creating
a node must be globally unique, the hash (xxhash64) of the same
must be unique as well. This also allows in avoiding id
generation at the database along with giving a unique key to
the client to refer to any node in the graph. This can then be
used as a KV store as well.

.. graphviz::

    digraph {
        key_data -> "f(xxhash64, input)" -> id;
    }

Components
----------

The framework has the following components:

* core - The database supports node, link (a->b) and secondary indexes.
* json and x-erlang-binary - The database supports both *application/json* and
  *application/x-erlang-binary* HTTP content type.
* storage - MySQL datbase is used as backend storage for quick time to market
  and data consistency and reliability.

Quick Usage
===========

A sample data about india, where the primary key to this data
is stored in *key_data*. Note that the value specified in
*key_data* (which is "country-india") must be globally unique.

file: country-india.json
------------------------

.. code-block:: json
   :linenos:
   :emphasize-lines: 2,3,17

    {
        "key_data" : "country-india",
        "details" : {
            "capital": "new delhi",
            "largest_city": "mumbai",
            "population": 1324171354,
            "gdp": {
                "total": "$10.385 trillion",
                "per_capita": "$7783"
            },
            "timezone": "IST (UTC+05:30)",
            "date-format": "dd-mm-yyyy",
            "calling_code": "+91",
            "ISO 3166 code": "IN",
            "internet_TLD": ".in"
        },
        "indexes" : [
            ["capital"],
            ["population"],
            ["gdp", "total"]
        ]
    }

Lets save the

.. code-block:: bash

    $ curl -X POST -H 'content-type: application/json' \
      -d@country-india.json -v "http://localhost:8001/detail"

The curl output (verbose with headers) is as follows:

.. code-block:: bash
   :linenos:
   :emphasize-lines: 15

    *   Trying 127.0.0.1...
    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /detail HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/json
    > Content-Length: 268
    >
    * upload completely sent off: 268 out of 268 bytes
    < HTTP/1.1 201 Created
    < content-length: 0
    < content-type: application/json
    < date: Wed, 22 Aug 2018 06:06:26 GMT
    < location: /detail/f81591550e03c743
    < server: Cowboy
    <
    * Connection #0 to host localhost left intact


Lets now try reading it back based on the location returned
in the previous curl POST.

.. code-block:: bash

    $ curl "http://localhost:8001/detail/f81591550e03c743?keytype=rawhex" | python -m json.tool

The content returned is as follows:

.. code-block:: json

    [
        {
            "details": {
                "__indexes": [
                    [
                        "view",
                        "name"
                    ],
                    [
                        "view",
                        "fare"
                    ]
                ],
                "__key": "neeraj",
                "view": {
                    "fare": 200.4,
                    "name": "neeraj",
                    "seats": [
                        "s1",
                        "s2"
                    ],
                    "surname": "sharma"
                }
            },
            "details_hash": "6bce2aa2a1f4cc9e",
            "source": "f81591550e03c743",
            "updated_datetime": "2018-08-22 06:06:26",
            "version": 0
        }
    ]


.. code-block:: bash

    $ curl "http://localhost:8001/index/neeraj?keytype=text&indexname=name" | python -m json.tool

The returned output is the following JSON.

.. code-block:: json

    [
        "f81591550e03c743"
    ]


Compression
-----------

file: compress_dict_post.json
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: json

    {
        "id" : 1,
        "dictionary" : "nameageneerajsharma200.4"
    }


.. code-block:: bash

    $ curl -X POST -H 'content-type: application/json' \
      -d@compress_dict_post.json -v \
      "http://localhost:8001/compression/dict"

.. code-block:: bash

    *   Trying 127.0.0.1...
    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /compression/dict HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/json
    > Content-Length: 60
    > 
    * upload completely sent off: 60 out of 60 bytes
    < HTTP/1.1 400 Bad Request
    < content-length: 0
    < content-type: application/json
    < date: Wed, 22 Aug 2018 10:29:14 GMT
    < server: Cowboy
    < 
    * Connection #0 to host localhost left intact


Link
----

file: india_usa_link_post.json
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: json

    {
        "source" : "india",
        "destination" : "usa",
        "details" : {
            "distance": 10000.0,
            "flight_time_hours": 21.0,
            "daily_tourists": 10000000
        }
    }


.. code-block:: bash

    $ curl -X POST -H 'content-type: application/json' \
      -d@test/artifacts/sample_link_post.json -v \
      "http://localhost:8001/link"

.. code-block:: bash

    *   Trying 127.0.0.1...
    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /link HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/json
    > Content-Length: 169
    > 
    * upload completely sent off: 169 out of 169 bytes
    < HTTP/1.1 201 Created
    < content-length: 0
    < content-type: application/json
    < date: Thu, 23 Aug 2018 05:39:11 GMT
    < location: /link/19181447080c72c9?destination=ccf364f81fc02db9&keytype=rawhex
    < server: Cowboy
    < 
    * Connection #0 to host localhost left intact


.. code-block:: bash

    $ curl \
      "http://localhost:8001/link/19181447080c72c9?destination=ccf364f81fc02db9&keytype=rawhex" \
      | python -m json.tool

.. code-block:: json

    [
        {
            "destination": "ccf364f81fc02db9",
            "details": {
                "__destination": "usa",
                "__source": "india",
                "daily_tourists": 10000000,
                "distance": 10000.0,
                "flight_time_hours": 21.0
            },
            "source": "19181447080c72c9",
            "version": 4
        }
    ]

# Lets add another link from india

file: india_japan_link_post.json
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: json

    {
        "source" : "india",
        "destination" : "japan",
        "details" : {
            "distance": 5000.0,
            "flight_time_hours": 15.0,
            "daily_tourists": 100000
        }
    }


.. code-block:: bash

    $ curl -X POST -H 'content-type: application/json' \
      -d@test/artifacts/sample_link2_post.json -v \
      "http://localhost:8001/link"

.. code-block:: bash

    *   Trying 127.0.0.1...
    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /link HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/json
    > Content-Length: 168
    > 
    * upload completely sent off: 168 out of 168 bytes
    < HTTP/1.1 201 Created
    < content-length: 0
    < content-type: application/json
    < date: Thu, 23 Aug 2018 05:40:44 GMT
    < location: /link/19181447080c72c9?destination=42c774ffc8c05dd1&keytype=rawhex
    < server: Cowboy
    < 
    * Connection #0 to host localhost left intact

Lets use the url returned in location and see what we get back.

.. code-block:: bash

    $ curl \
      "http://localhost:8001/link/19181447080c72c9?destination=42c774ffc8c05dd1&keytype=rawhex"
      | python -m json.tool

.. code-block:: json

    [
        {
            "destination": "42c774ffc8c05dd1",
            "details": {
                "__destination": "japan",
                "__source": "india",
                "daily_tourists": 100000,
                "distance": 5000.0,
                "flight_time_hours": 15.0
            },
            "source": "19181447080c72c9",
            "version": 0
        }
    ]

Lets remove the 'destination' query parameter and see what happens next.

.. code-block:: bash

    $ curl "http://localhost:8001/link/19181447080c72c9?keytype=rawhex" | python -m json.tool

.. code-block:: json

    [
        {
            "destination": "ccf364f81fc02db9",
            "details": {
                "__destination": "usa",
                "__source": "india",
                "daily_tourists": 10000000,
                "distance": 10000.0,
                "flight_time_hours": 21.0
            },
            "source": "19181447080c72c9",
            "version": 4
        },
        {
            "destination": "42c774ffc8c05dd1",
            "details": {
                "__destination": "japan",
                "__source": "india",
                "daily_tourists": 100000,
                "distance": 5000.0,
                "flight_time_hours": 15.0
            },
            "source": "19181447080c72c9",
            "version": 0
        }
    ]

We get result from india to both usa and japan.

x-erlang-binary
---------------

# Lets test x-erlang-binary interface

file: sample_details_post.json
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: json

    {
        "key_data" : "neeraj",
        "details" : {
            "view": {
                "name": "neeraj",
                "surname": "sharma",
                "seats": ["s1", "s2"],
                "fare": 200.4
            }
        },
        "indexes" : [
            ["view", "name"],
            ["view", "surname"],
            ["view", "fare"]
        ]
    }

# Create erlang encoded request body

.. code-block:: bash

    $ erl -pa _build/default/lib/*/ebin
    Erlang/OTP 21 [erts-10.0] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [hipe]

    Eshell V10.0  (abort with ^G)
    1> {ok, Content} = file:read_file("test/artifacts/sample_details_post.json").
    {ok,<<"{\n    \"key_data\" : \"neeraj\",\n    \"details\" : {\n        \"view\": {\n            \"name\": \"neeraj\",\n            \""...>>}
    2> M = jiffy:decode(Content, [return_maps]).
    #{<<"details">> =>
          #{<<"view">> =>
                #{<<"fare">> => 200.4,<<"name">> => <<"neeraj">>,
                  <<"seats">> => [<<"s1">>,<<"s2">>],
                  <<"surname">> => <<"sharma">>}},
      <<"indexes">> =>
          [[<<"view">>,<<"name">>],
           [<<"view">>,<<"surname">>],
           [<<"view">>,<<"fare">>]],
      <<"key_data">> => <<"neeraj">>}
    3> file:write_file("test/artifacts/sample_details_post.x-erlang-binary", erlang:term_to_binary(M)).
    ok
    4> q().
    ok

# Now post the file as data binary with correct content-type

.. code-block:: bash

    $ curl -X POST -H 'content-type: application/x-erlang-binary' \
      --data-binary @test/artifacts/sample_details_post.x-erlang-binary \
      -v "http://localhost:8001/detail"

.. code-block:: bash

    *   Trying 127.0.0.1...
    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /detail HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/x-erlang-binary
    > Content-Length: 245
    > 
    * upload completely sent off: 245 out of 245 bytes
    < HTTP/1.1 201 Created
    < content-length: 0
    < content-type: application/json
    < date: Fri, 24 Aug 2018 09:23:30 GMT
    < location: /detail/f81591550e03c743?keytype=rawhex
    < server: Cowboy
    < vary: accept
    < 
    * Connection #0 to host localhost left intact

# lets look at read now with x-erlang-binary

.. code-block:: bash

    $ curl -v -H 'Accept: application/x-erlang-binary' \
      "http://localhost:8001/detail/f81591550e03c743?keytype=rawhex" \
      | od -tx1

    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > GET /detail/f81591550e03c743?keytype=rawhex HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: application/x-erlang-binary
    > 
    < HTTP/1.1 200 OK
    < content-length: 379
    < content-type: application/x-erlang-binary
    < date: Fri, 24 Aug 2018 09:25:15 GMT
    < server: Cowboy
    < vary: accept
    < 
    { [379 bytes data]
    100   379  100   379    0     0  46107      0 --:--:-- --:--:-- --:--:-- 54142
    * Connection #0 to host localhost left intact
    0000000 83 6c 00 00 00 01 74 00 00 00 05 6d 00 00 00 07
    0000020 64 65 74 61 69 6c 73 74 00 00 00 03 6d 00 00 00
    0000040 09 5f 5f 69 6e 64 65 78 65 73 6c 00 00 00 03 6c
    0000060 00 00 00 02 6d 00 00 00 04 76 69 65 77 6d 00 00
    0000100 00 04 6e 61 6d 65 6a 6c 00 00 00 02 6d 00 00 00
    0000120 04 76 69 65 77 6d 00 00 00 07 73 75 72 6e 61 6d
    0000140 65 6a 6c 00 00 00 02 6d 00 00 00 04 76 69 65 77
    0000160 6d 00 00 00 04 66 61 72 65 6a 6a 6d 00 00 00 05
    0000200 5f 5f 6b 65 79 6d 00 00 00 06 6e 65 65 72 61 6a
    0000220 6d 00 00 00 04 76 69 65 77 74 00 00 00 04 6d 00
    0000240 00 00 04 66 61 72 65 46 40 69 0c cc cc cc cc cd
    0000260 6d 00 00 00 04 6e 61 6d 65 6d 00 00 00 06 6e 65
    0000300 65 72 61 6a 6d 00 00 00 05 73 65 61 74 73 6c 00
    0000320 00 00 02 6d 00 00 00 02 73 31 6d 00 00 00 02 73
    0000340 32 6a 6d 00 00 00 07 73 75 72 6e 61 6d 65 6d 00
    0000360 00 00 06 73 68 61 72 6d 61 6d 00 00 00 0c 64 65
    0000400 74 61 69 6c 73 5f 68 61 73 68 6d 00 00 00 10 65
    0000420 61 35 32 38 35 61 63 61 39 66 37 36 39 38 62 6d
    0000440 00 00 00 06 73 6f 75 72 63 65 6d 00 00 00 10 66
    0000460 38 31 35 39 31 35 35 30 65 30 33 63 37 34 33 6d
    0000500 00 00 00 10 75 70 64 61 74 65 64 5f 64 61 74 65
    0000520 74 69 6d 65 6d 00 00 00 13 32 30 31 38 2d 30 38
    0000540 2d 32 34 20 30 39 3a 32 33 3a 33 31 6d 00 00 00
    0000560 07 76 65 72 73 69 6f 6e 61 12 6a
    0000573

# Lets save the content and decode to validate

.. code-block:: bash

    $ curl -v -H 'Accept: application/x-erlang-binary' \
      "http://localhost:8001/detail/f81591550e03c743?keytype=rawhex" \
      > test.x-erlang-binary

.. code-block:: bash

    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > GET /detail/f81591550e03c743?keytype=rawhex HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: application/x-erlang-binary
    > 
    < HTTP/1.1 200 OK
    < content-length: 379
    < content-type: application/x-erlang-binary
    < date: Fri, 24 Aug 2018 09:25:51 GMT
    < server: Cowboy
    < vary: accept
    < 
    { [379 bytes data]
    100   379  100   379    0     0  45248      0 --:--:-- --:--:-- --:--:-- 47375
    * Connection #0 to host localhost left intact

.. code-block:: bash

    $ erl -pa _build/default/lib/*/ebin
    Erlang/OTP 21 [erts-10.0] [source] [64-bit] [smp:8:8] [ds:8:8:10] [async-threads:1] [hipe]

    Eshell V10.0  (abort with ^G)
    1> {ok, Content} = file:read_file("test.x-erlang-binary").
    {ok,<<131,108,0,0,0,1,116,0,0,0,5,109,0,0,0,7,100,101,
          116,97,105,108,115,116,0,0,0,...>>}
    2> erlang:binary_to_term(Content).
    [#{<<"details">> =>
           #{<<"__indexes">> =>
                 [[<<"view">>,<<"name">>],
                  [<<"view">>,<<"surname">>],
                  [<<"view">>,<<"fare">>]],
             <<"__key">> => <<"neeraj">>,
             <<"view">> =>
                 #{<<"fare">> => 200.4,<<"name">> => <<"neeraj">>,
                   <<"seats">> => [<<"s1">>,<<"s2">>],
                   <<"surname">> => <<"sharma">>}},
       <<"details_hash">> => <<"ea5285aca9f7698b">>,
       <<"source">> => <<"f81591550e03c743">>,
       <<"updated_datetime">> => <<"2018-08-24 09:23:31">>,
       <<"version">> => 18}]
    3> q().
    ok

Running Function
----------------

# Lets save a function and run it.

file: sample_function_post.json 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: json

    {
        "name": "add",
        "arity": 2,
        "lang": "erlang",
        "function": "fun(A, B) -> log_info(\"A = ~p, B = ~p\", [A, B]), A + B end.",
        "test_vectors": [
            [10, 20],
            [-1, 1]
        ],
        "test_validator_function": "fun([A, B], C) -> R = ((A + B) == C), log_info(\"R = ~p\", [R]), R end."
    }


.. code-block:: bash

    $ curl -X POST -H 'content-type: application/json' -d@test/artifacts/sample_function_post.json -v "http://localhost:8001/f"


.. code-block:: bash

    *   Trying 127.0.0.1...
    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /f HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/json
    > Content-Length: 299
    > 
    * upload completely sent off: 299 out of 299 bytes
    < HTTP/1.1 201 Created
    < content-length: 0
    < content-type: application/json
    < date: Sun, 26 Aug 2018 12:46:16 GMT
    < location: /f/add?arity=2
    < server: Cowboy
    < vary: accept
    < 
    * Connection #0 to host localhost left intact


.. code-block:: bash

    $ curl -v "http://localhost:8001/f/add?arity=2" | python -m json.tool

.. code-block:: bash

    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > GET /f/add?arity=2 HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > 
    < HTTP/1.1 200 OK
    < content-length: 335
    < content-type: application/json
    < date: Sun, 26 Aug 2018 12:46:59 GMT
    < server: Cowboy
    < vary: accept
    < 
    { [335 bytes data]
    100   335  100   335    0     0  35676      0 --:--:-- --:--:-- --:--:-- 37222
    * Connection #0 to host localhost left intact

.. code-block:: json

    [
        {
            "arity": 2,
            "details": "fun(A, B) -> log_info(\"A = ~p, B = ~p\", [A, B]), A + B end.",
            "details_hash": "c2b9a733c7915f63",
            "lang": "erlang",
            "name": "add",
            "test_validator_function": "fun([A, B], C) -> R = ((A + B) == C), log_info(\"R = ~p\", [R]), R end.",
            "test_vectors": [
                [
                    10,
                    20
                ],
                [
                    -1,
                    1
                ]
            ],
            "updated_datetime": "2018-08-26 12:46:16",
            "version": 1
        }
    ]


# lest run the saved function

file: sample_fquery_post.json 
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: json

    {
        "name": "add",
        "arguments": [1, 2]
    }

.. code-block:: bash

    $ curl -X POST -H 'content-type: application/json' -d@test/artifacts/sample_fquery_post.json -v "http://localhost:8001/fquery" | python -m json.tool

.. code-block:: bash

    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /fquery HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/json
    > Content-Length: 43
    > 
    } [43 bytes data]
    * upload completely sent off: 43 out of 43 bytes
    < HTTP/1.1 200 OK
    < content-length: 31
    < content-type: application/json
    < date: Sun, 26 Aug 2018 12:47:57 GMT
    < server: Cowboy
    < vary: accept
    < 
    { [31 bytes data]
    100    74  100    31  100    43   4433   6149 --:--:-- --:--:-- --:--:--  7166
    * Connection #0 to host localhost left intact

.. code-block:: json

    {
        "result": 3,
        "status": "success"
    }

# lest run a bad query

file: sample_fquery2_post.json
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code-block:: json

    {
        "name": "add",
        "arguments": [1, "true"]
    }

.. code-block:: bash

    $ curl -X POST -H 'content-type: application/json' \
      -d@sample_fquery2_post.json -v \
      "http://localhost:8001/fquery" | python -m json.tool

.. code-block:: bash

    * Connected to localhost (127.0.0.1) port 8001 (#0)
    > POST /fquery HTTP/1.1
    > Host: localhost:8001
    > User-Agent: curl/7.47.0
    > Accept: */*
    > content-type: application/json
    > Content-Length: 48
    > 
    } [48 bytes data]
    * upload completely sent off: 48 out of 48 bytes
    < HTTP/1.1 200 OK
    < content-length: 1411
    < content-type: application/json
    < date: Sun, 26 Aug 2018 12:48:38 GMT
    < server: Cowboy
    < vary: accept
    < 
    { [1411 bytes data]
    100  1459  100  1411  100    48   229k   8000 --:--:-- --:--:-- --:--:--  275k
    * Connection #0 to host localhost left intact

.. code-block:: json

    {
        "exception": {
            "class": "error",
            "error": "badarith",
            "stacktrace": "[{erlang,'+',[1,<<\"true\">>],[]},\n {egraph_fquery_model,create_or_update_info,2,\n                      [{file,\"/home/neerajsharma/work/egraph/_build/default/lib/egraph/models/egraph_fquery_model.erl\"},\n                       {line,152}]},\n {egraph_generic_handler,handle_http_post_request,10,\n                         [{file,\"/home/neerajsharma/work/egraph/_build/default/lib/egraph/handlers/egraph_generic_handler.erl\"},\n                          {line,238}]},\n {cowboy_rest,call,3,\n              [{file,\"/home/neerajsharma/work/egraph/_build/default/lib/cowboy/src/cowboy_rest.erl\"},\n               {line,1182}]},\n {cowboy_rest,process_content_type,3,\n              [{file,\"/home/neerajsharma/work/egraph/_build/default/lib/cowboy/src/cowboy_rest.erl\"},\n               {line,986}]},\n {cowboy_rest,upgrade,4,\n              [{file,\"/home/neerajsharma/work/egraph/_build/default/lib/cowboy/src/cowboy_rest.erl\"},\n               {line,260}]},\n {cowboy_stream_h,execute,3,\n                  [{file,\"/home/neerajsharma/work/egraph/_build/default/lib/cowboy/src/cowboy_stream_h.erl\"},\n                   {line,272}]},\n {cowboy_stream_h,request_process,3,\n                  [{file,\"/home/neerajsharma/work/egraph/_build/default/lib/cowboy/src/cowboy_stream_h.erl\"},\n                   {line,250}]}]"
        },
        "status": "error"
    }






The Future
==========

Similar Projects
================

Deployment
==========

Software Dependencies
---------------------

This framework supports *Gnu/Linux* and *MacOSX* operating system, but with
little change it can be made to build on any of the POSIX compliant
operating system when Erlang/OTP is available. This project depends upon
a lot of open source dependencies, which are listed in rebar.config.

Development Environment Setup
-----------------------------

Although the installation for various GNU/Linux distributions differ but
the dependencies are easily available on any one of them.

Ubuntu or Debian
~~~~~~~~~~~~~~~~

The following commands were tested on Ubuntu 16.04 and Debian 9
but things should be similar (if not same) on other releases and Debian.

The following commands needs to be as a system administrator or with sudo
(as shown below) so that the relavent packages are installed in the
system.

If your system is not updated then probably it is a good idea to do that
before installing anything else.

    sudo apt-get update

Install the build essential and deps for Erlang/OTP

    sudo apt-get install -y wget build-essentials libsctp1 libwxgtk3.0

Get Erlang/OTP 21+ from ErlangSolutions at
https://www.erlang-solutions.com/resources/download.html

Say you downloaded Erlang/OTP 21.0 then install it for ubuntu
as follows:

    wget https://packages.erlang-solutions.com/erlang/esl-erlang/FLAVOUR_1_general/esl-erlang_21.0-1~ubuntu~xenial_amd64.deb
    sudo dpkg -i esl-erlang_21.0-1~ubuntu~xenial_amd64.deb

Alternatively, you can install the erlang from Ubuntu or Debian repo as well.

Build and Test
--------------

After you are done setting up the development environment the build is
pretty straight-forward (see below).

    git clone https://github.com/neeraj9/egraph
    cd egraph 
    make release

In case you want to build a package then use the deb-package makefile
target towards the same (see below).

    make deb-package

Thanks
======

Thanks for evaluating and contributing to this project. Hope you
find it useful. Feel free to create issues for bugs or new features.

A special note of thanks to `redBus <http://www.redbus.com>`_ for
being the first in integrating it within its production environment.

Authors
=======

* Neeraj Sharma (neeraj.sharma@alumni.iitg.ernet.in)

