
DROP DATABASE egraph_db;
DROP USER 'egraph_user';
DROP USER 'egraph_ro_user';

-- Setting timezone using SQL does not work in RDS. Ensure that it is set in parameter group
SET GLOBAL time_zone = '+0:00';  -- ensure that timezone of db is in UTC

CREATE USER 'egraph_user'@'%' IDENTIFIED BY 'abc123';
CREATE USER 'egraph_ro_user'@'%' IDENTIFIED BY 'abc123';

CREATE DATABASE IF NOT EXISTS egraph_db CHARACTER SET utf8 COLLATE utf8_general_ci;

GRANT ALL PRIVILEGES ON egraph_db.* TO 'egraph_user'@'%' WITH GRANT OPTION;
GRANT SELECT ON egraph_db.* TO 'egraph_ro_user'@'%';

USE egraph_db;


-- Store dictionary for custom compression
--
-- IMPORTANT: DONT update the entry onces created, else
--            content compressed with old dictionary will
--            fail.
CREATE TABLE `egraph_compression_dict` (
  `id` int NOT NULL,
  `creation_datetime` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Datetime when the entry was created',
  `dictionary` blob NOT NULL,
  PRIMARY KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


-- This is a template table which will be used to create shard as follows:
-- Note that xxhash64 has a size of 8 octets
-- Additionally, multiple entries with same `key_data` but different `id` can
-- would exist.
--
-- SHARDING: A sharding policy would be applied for this table,
--           wherein the first suffix is key_data index name.
--
CREATE TABLE `egraph_lookup_base` (
  `key_data` binary(8) NOT NULL,
  `id` binary(8) NOT NULL,
  CONSTRAINT pkey PRIMARY KEY (`id`, `key_data`),
  KEY `key_data` (`key_data`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_lookup_base_KEYINDEXNAME LIKE egraph_lookup_base;
-- Note that the KEYINDEXNAME is the name of the index in text which
-- can be something like 'age' or any other index field name.

-- This is a template table to store secondary integer indices
CREATE TABLE `egraph_lookup_int_base` (
  `key_data` bigint NOT NULL,
  `id` binary(8) NOT NULL,
  CONSTRAINT pkey PRIMARY KEY (`id`, `key_data`),
  KEY `key_data` (`key_data`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_lookup_int_base_KEYINDEXNAME LIKE egraph_lookup_int_base;
-- Note that the KEYINDEXNAME is the name of the index in text which
-- can be something like 'age' or any other integer index field name.


-- This is a template table to store secondary geospatial indices
--
-- Notice that size is provided for `key_data` because it acts like
-- blob or text.
-- The geometry can practically be more than just a POINT and can
-- be a polygon (in future), so plan for it and give a higher value
-- for length when indexing. This will cause indexes to be slower
-- but will be better.
CREATE TABLE `egraph_lookup_geo_base` (
  `key_data` geometry NOT NULL,
  `id` binary(8) NOT NULL,
  CONSTRAINT pkey PRIMARY KEY (`id`, `key_data`(255)),
  SPATIAL INDEX `key_data` (`key_data`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- This is a template table to store secondary float indices
--
-- Note: double is approximate and looses precision.
-- see: https://dev.mysql.com/doc/refman/5.5/en/problems-with-float.html
-- see: https://dev.mysql.com/doc/refman/5.5/en/fixed-point-types.html
-- see: https://dev.mysql.com/doc/refman/8.0/en/storage-requirements.html
CREATE TABLE `egraph_lookup_double_base` (
  `key_data` double NOT NULL,
  `id` binary(8) NOT NULL,
  CONSTRAINT pkey PRIMARY KEY (`id`, `key_data`),
  KEY `key_data` (`key_data`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_lookup_double_base_KEYINDEXNAME LIKE egraph_lookup_double_base;
-- Note that the KEYINDEXNAME is the name of the index in text which
-- can be something like 'amount' or any other floating point index field name.

-- This is a template table to store secondary datetime indices
CREATE TABLE `egraph_lookup_datetime_base` (
  `key_data` datetime NOT NULL,
  `id` binary(8) NOT NULL,
  CONSTRAINT pkey PRIMARY KEY (`id`, `key_data`),
  KEY `key_data` (`key_data`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_lookup_datetime_base_KEYINDEXNAME LIKE egraph_lookup_datetime_base;
-- Note that the KEYINDEXNAME is the name of the index in text which
-- can be something like 'dateofbirth' or any other datetime index field name.


-- This is a template table to store secondary date indices
CREATE TABLE `egraph_lookup_date_base` (
  `key_data` date NOT NULL,
  `id` binary(8) NOT NULL,
  CONSTRAINT pkey PRIMARY KEY (`id`, `key_data`),
  KEY `key_data` (`key_data`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_lookup_date_base_KEYINDEXNAME LIKE egraph_lookup_date_base;
-- Note that the KEYINDEXNAME is the name of the index in text which
-- can be something like 'dateofbirth' or any other date index field name.

-- This is a template table to store secondary text indices
CREATE TABLE `egraph_lookup_text_base` (
  `key_data` varbinary(255) NOT NULL,
  `id` binary(8) NOT NULL,
  CONSTRAINT pkey PRIMARY KEY (`id`, `key_data`),
  KEY `key_data` (`key_data`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_lookup_text_base_KEYINDEXNAME LIKE egraph_lookup_text_base;
-- Note that the KEYINDEXNAME is the name of the index in text which
-- can be something like 'name' or any other text index field name.


-- This is a template table which will be used to create shard as follows:
-- SHARDING: The sharding suffix is last 11 bits of `source` which is
--           actually a 64bit number but stored in binary(8) since bigint
--           can only store 63bit while 1 bit is used as sign bit.
--           So a total of 2^11 or 2048 shards are possible with this approach.
--
CREATE TABLE `egraph_details_base` (
  `source` binary(8) NOT NULL,
  `version` int(4) NOT NULL DEFAULT '0' COMMENT 'contention resolution and for data etag',
  `details_hash` binary(8) DEFAULT '0' COMMENT 'xxhash64 of details',
  `details` blob DEFAULT NULL COMMENT 'business specific details',
  `updated_datetime` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Datetime when the entry was last updated',
  `indexes` blob DEFAULT NULL COMMENT 'indexes created within details reside here',
  PRIMARY KEY (`source`),
  KEY `updated_datetime` (`updated_datetime`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_details_base_<shardsuffix> LIKE egraph_details_base;

-- This is a template table which will be used to create shard as follows:
-- SHARDING: The sharding suffix is last 11 bits of `source` which is
--           actually a 64bit number but stored in binary(8) since bigint
--           can only store 63bit while 1 bit is used as sign bit.
--           So a total of 2^8 or 2048 shards are possible with this approach.
--
-- IMPORTANT: For bidirectional link there shall be two rows in this table,
--            one for each source and destination combination.
CREATE TABLE `egraph_link_base` (
  `source` binary(8) NOT NULL,
  `destination` binary(8) NOT NULL,
  `version` int(4) NOT NULL DEFAULT '0' COMMENT 'contention resolution and for data etag',
  `details_hash` binary(8) DEFAULT '0' COMMENT 'xxhash64 of details',
  `details` blob DEFAULT NULL COMMENT 'link specific details',
  CONSTRAINT pkey PRIMARY KEY (`source`, `destination`),
  KEY `source` (`source`),
  KEY `destination` (`destination`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- CREATE TABLE IF NOT EXISTS egraph_link_base_<shardsuffix> LIKE egraph_link_base;

-- This table is not sharded
CREATE TABLE `egraph_function` (
  `name` varbinary(255) NOT NULL,
  `arity` int(2) NOT NULL COMMENT 'number of arguments passed to function',
  `lang` varbinary(255) NOT NULL,
  `version` int(4) NOT NULL DEFAULT '0' COMMENT 'content resolution and version tracking',
  `details` blob NOT NULL COMMENT 'anonymous function source code',
  `details_hash` binary(8) DEFAULT '0' COMMENT 'xxhash64 of details',
  `test_validator_function` blob NOT NULL COMMENT 'anonymous function to validate test vectors',
  `test_vectors` blob NOT NULL COMMENT 'Erlang serialized map of test vectors',
  `updated_datetime` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Datetime when the entry was last updated',
   CONSTRAINT pkey PRIMARY KEY (`name`, `arity`),
   KEY `lang` (`lang`),
   KEY `updated_datetime` (`updated_datetime`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


-- This table is NOT sharded
CREATE TABLE `egraph_reindex_status` (
  `shard_id` bigint NOT NULL,
  `is_reindexing` int(1) NOT NULL DEFAULT '0' COMMENT '0 when no-reindexing job running and 1 otherwise',
  `details` blob NOT NULL COMMENT 'additional details',
  `version` int(4) NOT NULL DEFAULT '0' COMMENT 'contention resolution and for data',
  `updated_datetime` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Datetime when the entry was last updated',
  PRIMARY KEY (`shard_id`),
  KEY `updated_datetime` (`updated_datetime`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


-- -------------------------- EXPERIMENTAL ---------------------------

-- This table is NOT sharded
--
-- When the value of `updated_datetime` is a lot in past compared to
-- the current datetime (in UTC), then it is an indicator that there
-- is no background job for reindexing which is running. This check
-- must be performed when the value of `is_reindexing` is 1. In
-- which case the agent must fix then and validate whether reindexing
-- is complete (by looking for data prior to `min_data_updated_datetime`).
-- If there is no such data then it is a clear indicator that reindexing
-- can be marked complete.
--
-- It is important to note that when reindexing is in progress then
-- any changes in index values for details (or `egraph_details_base_...`)
-- must be parked for later replay, so as to not interfere with
-- reindexing. As an exception to this rule the client can check for
-- current reindexing `min_data_updated_datetime` to validate whether
-- the old data `updated_datetime` is prior to that. If so then park
-- the event for later, but apply it otherwise without parking it
-- since there the change can be safely recorded.
--
-- Once the reindexing is complete then all the parked events are first
-- replayed (where index values have changed) and then later based on
-- the `max_data_updated_datetime` resume indexing of latest data.
--
-- The above solution will reindex newly updated data twice (because
-- the changes would have been applied already), but it is alright
-- as long as it takes a bounded amount of time to reindex the complete
-- set of data. This also opens up an important observation that as
-- data grows then the cost of reindexing goes up dramatically and
-- must be avoided at all cost. In fact it is better to specify
-- reindexing till a given minimum rather than forever via setting
-- `limit_min_data_updated_datetime` to value till the point when
-- the system will reindex old data.
--
--
-- `min_sec_per_run` is a bit more than the sql read timeout set
-- for clients when using the sql pool. This will ensure that
-- clients will not have stale information about this table
-- while trying to modify older data in `egraph_details_base`
-- which is being reindexed as well (and has changes in indexed value).
-- This allows lock-free mutation to be possible with the help of
-- timing information. It is assumed that the clock at reader and
-- reindexer do not vary to the extent to cause an issue. Having said
-- that it is important for both reader and reindexer to rely on
-- monotonic clock while computing time duration for absolute
-- guarantee. Additionally, the value of `min_sec_per_run` must always be
-- higher compared to the timeout set for reader when waiting to
-- perform read or write operation via sql pool.
--
CREATE TABLE `egraph_reindex_status_experimental` (
  `index_table_name` text NOT NULL,
  `index_name` text NOT NULL,
  `index_type` text NOT NULL,
  `is_reindexing` int(1) NOT NULL DEFAULT '0' COMMENT '0 when no-reindexing job running and 1 otherwise',
  `updated_datetime` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Datetime when the entry was last updated',
  `min_data_updated_datetime` datetime NOT NULL COMMENT 'Min datetime of the last entry reindexed',
  `max_data_updated_datetime` datetime NOT NULL COMMENT 'Max datetime of the last entry reindexed',
  `limit_min_data_updated_datetime` datetime NOT NULL COMMENT 'Datetime of the last entry reindexed',
  `num_rows_per_run` bigint NOT NULL DEFAULT '100000' COMMENT 'Number of rows to reindex per run',
  `min_sec_per_run` bigint NOT NULL DEFAULT '20' COMMENT 'Minimum duration in seconds ensured for a single run, if completed faster then reindexer sleeps',
  `version` int(4) NOT NULL DEFAULT '0' COMMENT 'contention resolution and for data',
  PRIMARY KEY (`index_table_name`),
  KEY `index_name` (`index_name`),
  KEY `updated_datetime` (`updated_datetime`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

