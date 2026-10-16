-- Docker-entrypoint bootstrap used only by the local validation harness.
-- Production creates the business database and login roles through the platform.
CREATE DATABASE scopeledger;
\connect scopeledger
\ir /opt/scopeledger/001_schema.sql
\ir /opt/scopeledger/002_authorization_and_execution.sql
\ir /opt/scopeledger/003_least_privilege_roles.sql
