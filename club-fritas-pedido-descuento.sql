-- CLUB FRITAS: canje automático atómico al registrar pedido.
-- Ejecutar solo después de club-fritas-cotizacion-segura.sql.
-- No reemplaza create_public_order; pedidos sin descuento siguen intactos.
alter table public.club_reward_claims alter column redeemed_by drop not null;
alter table public.club_reward_claims add column if not exists order_number_id bigint;
create unique index if not exists club_reward_claims_order_number_unique
 on public.club_reward_claims(order_number_id) where order_number_id is not null;

create or replace function public.club_create_discount_order(
 p_token text,p_customer_name text,p_order_type text,p_table_number integer,
 p_address text,p_location_url text,p_items jsonb,p_notes text,
 p_payment_method text,p_delivery_fee integer default 0
)
returns jsonb language plpgsql security definer
set search_path=public,extensions,pg_temp as $$
declare
 v_customer public.club_customers%rowtype;
 v_item jsonb; v_quote jsonb; v_items jsonb:='[]'::jsonb;
 v_subtotal bigint:=0; v_discount bigint; v_total bigint;
 v_qty int; v_price int; v_name text; v_extra_names text[];
 v_id bigint; v_tracking uuid; v_cycle int; v_n int;
 v_phone text; v_claim_cycle int;
begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'Tarjeta Club Fritas inválida'; end if;
 select * into v_customer from public.club_customers
 where card_token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for update;
 if not found then raise exception 'Tarjeta no encontrada'; end if;
 v_phone:=substring(coalesce(p_notes,'') from 'CLUB_FRITAS_PHONE:([+]569[0-9]{8})');
 if v_phone is distinct from v_customer.phone then raise exception 'El WhatsApp no coincide con el socio'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 50 then
  raise exception 'Pedido sin productos válidos';
 end if;
 if p_delivery_fee not in (0,2000) then raise exception 'Costo de delivery inválido'; end if;
 if p_order_type not in ('Delivery','Retiro en local','Consumo en local') then raise exception 'Tipo de pedido inválido'; end if;
 if p_order_type<>'Delivery' and p_delivery_fee<>0 then raise exception 'Delivery inválido'; end if;
 if length(coalesce(p_customer_name,''))<1 then raise exception 'Falta nombre'; end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  if coalesce(v_item->>'quantity','') !~ '^[1-9][0-9]{0,2}$' then raise exception 'Cantidad inválida'; end if;
  v_qty:=(v_item->>'quantity')::int;
  if coalesce(v_item->>'product_id','') !~ '^[0-9]+-[0-9]+$' and
     coalesce(v_item->>'promotion_id','') !~ '^[0-9]+$' then raise exception 'Producto sin identificador'; end if;
  select coalesce(array_agg(e.value order by e.ordinality),'{}'::text[])
  into v_extra_names from jsonb_array_elements_text(coalesce(v_item->'extras','[]'::jsonb))
    with ordinality as e(value,ordinality);
  v_quote:=public.club_quote_product(
   case when v_item ? 'promotion_id' then null else v_item->>'product_id' end,
   v_extra_names,
   case when v_item ? 'promotion_id' then (v_item->>'promotion_id')::bigint else null end
  );
  v_price:=(v_quote->>'unit_price')::int; v_name:=v_quote->>'name';
  if v_item ? 'price' and (v_item->>'price')::int<>v_price then
   raise exception 'El precio cambió. Actualiza tu carrito';
  end if;
  v_subtotal:=v_subtotal+v_price::bigint*v_qty;
  if v_subtotal>10000000 then raise exception 'Pedido excede límite'; end if;
  v_items:=v_items||jsonb_build_array(jsonb_build_object(
   'name',v_name,'quantity',v_qty,'price',v_price,
   'details',coalesce(v_item->'details','[]'::jsonb)));
 end loop;
 select count(*) into v_n from public.club_stamps where customer_id=v_customer.id;
 select c into v_claim_cycle from generate_series(1,greatest(1,(greatest(v_n,1)-1)/10+1)) c
 where v_n >= (c-1)*10+5 and not exists(
  select 1 from public.club_reward_claims cl
  where cl.customer_id=v_customer.id and cl.cycle_number=c and cl.reward_type='discount_10')
 order by c limit 1;
 if v_claim_cycle is null then raise exception 'No tienes un descuento disponible'; end if;
 v_discount:=round(v_subtotal*0.10)::bigint;
 v_total:=v_subtotal-v_discount+p_delivery_fee;
 insert into public.orders(
  customer_name,order_type,table_number,address,location_url,items,
  notes,payment_method,total,status
 ) values(
  p_customer_name,p_order_type,p_table_number,p_address,p_location_url,v_items,
  concat_ws(' | ',nullif(p_notes,''),'CLUB FRITAS 10%: -$'||v_discount::text),
  p_payment_method,v_total::int,'nuevo'
 ) returning id,tracking_token into v_id,v_tracking;
 insert into public.club_reward_claims(
  customer_id,cycle_number,reward_type,redeemed_by,order_number_id
 ) values(v_customer.id,v_claim_cycle,'discount_10',null,v_id);
 return jsonb_build_object('order_id',v_id,'tracking_token',v_tracking,
  'product_subtotal',v_subtotal,'discount',v_discount,'delivery_fee',p_delivery_fee,
  'total',v_total);
end $$;
revoke all on function public.club_create_discount_order(text,text,text,integer,text,text,jsonb,text,text,integer) from public;
grant execute on function public.club_create_discount_order(text,text,text,integer,text,text,jsonb,text,text,integer) to anon,authenticated;

-- IMPORTANTE: solo canjea cuando se llame expresamente desde el carrito.
-- No ejecutar la función de pedido manualmente para probarla: crea pedido real.
