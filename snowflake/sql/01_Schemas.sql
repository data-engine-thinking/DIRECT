/*
 * DIRECT Framework - Snowflake edition
 * 01 Schemas
 *
 * The repository lives in the database that the deployment passes as the
 * `database` variable (Snowflake CLI: snow sql -f <file> -D database=<name>).
 * Every object is fully qualified, so the scripts do not depend on the session
 * context. The schema names follow the SQL Server edition: OMD for the
 * repository, OMD_METADATA for the reference data and settings, OMD_PROCESSING
 * for the processing views and OMD_REPORTING for the reporting views.
 */

CREATE DATABASE IF NOT EXISTS <% database %>;

CREATE SCHEMA IF NOT EXISTS <% database %>.OMD
  COMMENT = 'DIRECT Framework repository: Batches, Modules, their instances, events and load windows.';

CREATE SCHEMA IF NOT EXISTS <% database %>.OMD_METADATA
  COMMENT = 'DIRECT Framework reference data and settings.';

CREATE SCHEMA IF NOT EXISTS <% database %>.OMD_PROCESSING
  COMMENT = 'DIRECT Framework processing views (queues, hierarchy).';

CREATE SCHEMA IF NOT EXISTS <% database %>.OMD_REPORTING
  COMMENT = 'DIRECT Framework reporting views (execution logs, exceptions).';
