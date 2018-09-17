# EGraphDB

Graph Database for building massively scalable and fault tolerant
systems.

## Overview

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

    erl -pa _build/default/lib/*/ebin/* 
    
## Testing and Creating Code Coverage

The testing is powered with property based testing via proper.
The -c option will generate the coverage data as well.

    ./rebar3 proper -c

The coverage report on console and in html can now be generated
via the following:

    ./rebar3 cover -v
    
### EUnit Testing

The eunit tests for the entire app can be run using:

    ./rebar3 eunit --app egraph
    
The eunit tests for a particular module <erlang_module> can be run using:

    ./rebar3 eunit -m <erlang_module>

The [eunit user manual](http://erlang.org/documentation/doc-8.3/lib/eunit-2.3.2/doc/html/users_guide.html) can be referred to get started and to learn to write eunit tests.

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

* <http://egraph.org>


