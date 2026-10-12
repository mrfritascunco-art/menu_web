-- Ejecutar en Supabase SQL Editor antes de usar Mis Sellos.
create extension if not exists pgcrypto with schema extensions;
alter table public.club_customers add column if not exists card_token_hash text;
create unique index if not exists club_customers_card_token_hash_unique on public.club_customers(card_token_hash);

create or replace function public.club_issue_card_link(p_customer_id uuid)
returns text language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare v_token text;
begin
 if auth.uid() is null or not public.has_staff_role('admin') then
  raise exception 'No autorizado';
 end if;
 if not exists(select 1 from public.club_customers where id=p_customer_id) then
  raise exception 'Socio no encontrado';
 end if;
 v_token := encode(extensions.gen_random_bytes(32),'hex');
 update public.club_customers
 set card_token_hash=encode(extensions.digest(v_token,'sha256'),'hex')
 where id=p_customer_id;
 return v_token;
end $$;
revoke all on function public.club_issue_card_link(uuid) from public,anon;
grant execute on function public.club_issue_card_link(uuid) to authenticated;

create or replace function public.club_view_card(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare v_customer public.club_customers%rowtype; v_count integer;
begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
 select * into v_customer from public.club_customers
 where card_token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if not found then return null; end if;
 select count(*) into v_count from public.club_stamps where customer_id=v_customer.id;
 return jsonb_build_object('name',v_customer.customer_name,'stamps',v_count);
end $$;
revoke all on function public.club_view_card(text) from public;
grant execute on function public.club_view_card(text) to anon,authenticated;
