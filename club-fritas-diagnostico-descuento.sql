-- Consulta de diagnóstico: NO modifica datos.
-- Ejecutar en Supabase SQL Editor y compartir el resultado.
select p.proname as funcion,
       pg_get_function_arguments(p.oid) as argumentos,
       pg_get_functiondef(p.oid) as definicion
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('create_public_order','club_redeem_reward','club_stamp_on_delivery')
order by p.proname;
