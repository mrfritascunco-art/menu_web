-- Club Fritas: precios vigentes para cálculo seguro de descuentos.
-- Consulta de lectura: no altera los pedidos existentes.
-- Los productos normales toman el precio actual de menu_control o club_menu_prices.
-- Los extras se toman de sus tablas, sin duplicar tarifas.
create or replace function public.club_quote_product(
 p_product_id text,
 p_extra_names text[] default '{}'::text[],
 p_promotion_id bigint default null
)
returns jsonb language plpgsql security definer
set search_path=public,pg_temp as $$
declare v_base integer; v_name text; v_extra text; v_price integer; v_sum integer:=0; v_kind text;
begin
 if p_promotion_id is not null then
  if p_product_id is not null or cardinality(coalesce(p_extra_names,'{}'::text[]))>0 then
   raise exception 'Promoción no admite extras en esta cotización';
  end if;
  select price,name into v_base,v_name from public.menu_promotions
  where id=p_promotion_id and active=true;
  if not found then raise exception 'Promoción no disponible'; end if;
 else
  if p_product_id is null then raise exception 'Falta producto'; end if;
  select coalesce(m.price,c.price),coalesce(m.product_name,c.product_name)
    into v_base,v_name
  from public.club_menu_prices c
  left join public.menu_control m on m.product_id=c.product_id
  where c.product_id=p_product_id and coalesce(m.available,true)=true;
  if not found then raise exception 'Producto no disponible'; end if;
  if cardinality(coalesce(p_extra_names,'{}'::text[]))>30 then raise exception 'Demasiados extras'; end if;
  foreach v_extra in array coalesce(p_extra_names,'{}'::text[]) loop
   if p_product_id like '2-%' then
    select price into v_price from public.menu_papas_extras where name=v_extra and available=true;
   else
    select price into v_price from public.menu_extras where name=v_extra and available=true;
   end if;
   if not found then
    if v_extra='Papas fritas' and p_product_id like '0-%' then v_price:=1500;
    else raise exception 'Extra no disponible: %',v_extra;
    end if;
   end if;
   v_sum:=v_sum+v_price;
  end loop;
 end if;
 return jsonb_build_object('name',v_name,'base_price',v_base,'extras_price',v_sum,'unit_price',v_base+v_sum);
end $$;
revoke all on function public.club_quote_product(text,text[],bigint) from public;
grant execute on function public.club_quote_product(text,text[],bigint) to anon,authenticated;

-- Pruebas de lectura. Deben mostrar el precio actual, incluso después de una subida.
select public.club_quote_product('0-1') as cheese_burger,
       public.club_quote_product('2-0') as papas_base;
