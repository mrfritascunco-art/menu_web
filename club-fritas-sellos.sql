-- Club Fritas: sellos por pedido entregado. Ejecutar una vez en SQL Editor.
-- Conserva order_id UUID histórico y agrega una referencia bigint compatible.
alter table public.club_stamps add column if not exists order_number_id bigint;
-- El antiguo order_id UUID no corresponde a orders.id bigint.
-- Mantener la columna histórica, pero permitir NULL en sellos nuevos.
alter table public.club_stamps alter column order_id drop not null;
create unique index if not exists club_stamps_order_number_id_unique
  on public.club_stamps(order_number_id)
  where order_number_id is not null;

create or replace function public.club_stamp_on_delivery()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text;
  v_customer uuid;
  v_product_total bigint;
begin
  if new.status is distinct from 'entregado'
     or old.status is not distinct from 'entregado' then
    return new;
  end if;
  -- No se acreditan pedidos de prueba.
  if coalesce(new.notes,'') like '%PEDIDO DE PRUEBA%' then return new; end if;
  v_phone := substring(coalesce(new.notes,'') from 'CLUB_FRITAS_PHONE:([+]569[0-9]{8})');
  if v_phone is null then return new; end if;
  select id into v_customer from public.club_customers where phone = v_phone;
  if v_customer is null then return new; end if;

  -- Total de productos desde items JSON; nunca usa orders.total (incluye delivery).
  select coalesce(sum(
    (case when (x->>'quantity') ~ '^[0-9]+$' then (x->>'quantity')::bigint else 0 end)
    * (case when (x->>'price') ~ '^[0-9]+$' then (x->>'price')::bigint else 0 end)
  ),0) into v_product_total
  from jsonb_array_elements(
    case when jsonb_typeof(new.items) = 'array' then new.items else '[]'::jsonb end
  ) as x;
  if v_product_total < 15000 then return new; end if;

  insert into public.club_stamps(customer_id, order_number_id, product_total)
  values(v_customer, new.id, v_product_total::integer)
  on conflict do nothing;
  return new;
end $$;

drop trigger if exists club_stamp_delivery_trigger on public.orders;
create trigger club_stamp_delivery_trigger
after update of status on public.orders
for each row execute function public.club_stamp_on_delivery();

-- Solo el servidor acredita sellos. No abrir permisos públicos de escritura.
