-- Sondas de aislamiento de esquemas (US3, SC-005). Ejecutar como el administrador (superusuario o master RDS).
--
--   psql -v ON_ERROR_STOP=1 -v owner_role=solventa_backend -v other_role=ms_prueba \
--        -v schema=cotizacion -v table=cotizaciones -f scripts/sql/verificar-aislamiento.sql
--
-- I1: otro rol obtiene "permission denied" al leer un esquema que no posee.
-- I2: el número de filas de la tabla se conserva tras mover el esquema (compare las salidas antes/después).
-- I3: un esquema solo se elimina si no tiene dueño y se listó en drop_schemas.
\set ON_ERROR_STOP off
\pset pager off

\echo '== Contexto'
SELECT current_user AS administrador, current_database() AS base_de_datos;

\echo '== Propietarios actuales de los esquemas gestionados'
SELECT n.nspname AS esquema, pg_get_userbyid(n.nspowner) AS propietario
  FROM pg_namespace n
 WHERE n.nspname NOT LIKE 'pg\_%' AND n.nspname <> 'information_schema'
 ORDER BY 1;

\echo '== I2: filas en :schema.:table (anotar antes y después de mover el esquema)'
SELECT count(*) AS filas FROM :"schema".:"table";

\echo '== I1: el rol propietario puede leer :schema.:table'
SET ROLE :"owner_role";
SELECT count(*) AS filas_visibles_para_el_propietario FROM :"schema".:"table";
RESET ROLE;

\echo '== I1: otro rol debe recibir "permission denied" (error esperado a continuación)'
SET ROLE :"other_role";
SELECT count(*) FROM :"schema".:"table";
RESET ROLE;

\echo '== I1: otro rol tampoco puede crear objetos en el esquema (error esperado)'
SET ROLE :"other_role";
CREATE TABLE :"schema".sonda_aislamiento (id int);
RESET ROLE;

\echo '== I3: esquemas sin dueño de servicio (candidatos a drop_schemas)'
SELECT n.nspname AS esquema
  FROM pg_namespace n
 WHERE n.nspname NOT LIKE 'pg\_%'
   AND n.nspname NOT IN ('information_schema', 'public')
   AND coalesce(shobj_description(n.nspowner, 'pg_authid'), '') <> 'managed-by=solventa-platform'
 ORDER BY 1;
