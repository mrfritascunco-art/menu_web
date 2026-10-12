-- Fase 1: catálogo oficial sincronizado con el panel de precios actual.
-- No altera pedidos ni descuentos. Ejecutar en Supabase SQL Editor.
create table if not exists public.club_menu_prices (
 product_id text primary key,
 product_name text not null,
 price integer not null check(price>=0),
 updated_at timestamptz not null default now()
);
alter table public.club_menu_prices enable row level security;
revoke all on public.club_menu_prices from anon,authenticated;
grant select on public.club_menu_prices to anon,authenticated;
drop policy if exists club_menu_prices_read on public.club_menu_prices;
create policy club_menu_prices_read on public.club_menu_prices for select to anon,authenticated using(true);
insert into public.club_menu_prices(product_id,product_name,price) values
('0-0','Smash Peanut',8990),
('0-1','Cheese Burger',4990),
('0-2','Smash Bacon',9500),
('0-3','Smash Champi',7500),
('0-4','Smash Italiana',7500),
('0-5','Smash Fresh',7500),
('0-6','Mr ¼ de Kilo',13500),
('0-7','Oklahoma Burger',7490),
('0-8','Cuarto de Libra',5990),
('0-9','Smash Whopper',5990),
('0-10','Smash Clásica',6900),
('0-11','Smash Doble',8900),
('1-0','Base Smash',5500),
('2-0','Arma tus Papas Base',3000),
('2-1','Arma tus Papas Grande',5000),
('3-0','6 Empanadas de queso',2500),
('3-1','4 Nuggets de pollo',2500),
('3-2','4 Aros de cebolla',2500),
('4-0','Bebida en lata',2000),
('5-0','Combo para 2',17900)
on conflict(product_id) do nothing;
-- Respetar los precios que ya fueron cambiados desde administración.
update public.club_menu_prices c set price=m.price,updated_at=now()
from public.menu_control m where m.product_id=c.product_id and m.price is not null
and c.price is distinct from m.price;
-- Cada edición futura desde el panel actual sincroniza el precio automáticamente.
create or replace function public.club_sync_menu_price()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.price is not null then
  insert into public.club_menu_prices(product_id,product_name,price,updated_at)
  values(new.product_id,coalesce((select product_name from public.club_menu_prices where product_id=new.product_id),new.product_id),new.price,now())
  on conflict(product_id) do update set price=excluded.price,updated_at=now();
 end if;
 return new;
end $$;
drop trigger if exists club_sync_menu_price_trigger on public.menu_control;
create trigger club_sync_menu_price_trigger after insert or update of price
on public.menu_control for each row execute function public.club_sync_menu_price();
-- Comprobación: catálogo de productos del menú.
select product_id,product_name,price from public.club_menu_prices order by product_id;
