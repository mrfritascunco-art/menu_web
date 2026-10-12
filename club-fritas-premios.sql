-- Club Fritas: recompensas verificadas por servidor. Ejecutar en SQL Editor.
-- Cada bloque de 10 sellos constituye un ciclo. Los sellos históricos no se borran.
create table if not exists public.club_reward_claims (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references public.club_customers(id),
 cycle_number integer not null check (cycle_number >= 1),
 reward_type text not null check (reward_type in ('discount_10','free_item')),
 reward_choice text,
 redeemed_at timestamptz not null default now(),
 redeemed_by uuid not null,
 unique(customer_id,cycle_number,reward_type)
);
alter table public.club_reward_claims enable row level security;
revoke all on public.club_reward_claims from anon,authenticated;
grant select on public.club_reward_claims to authenticated;
drop policy if exists club_reward_claims_admin_read on public.club_reward_claims;
create policy club_reward_claims_admin_read on public.club_reward_claims
for select to authenticated using (public.has_staff_role('admin'));

create or replace function public.club_reward_state(p_customer_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare n int; c int; d boolean; f boolean;
begin
 select count(*) into n from public.club_stamps where customer_id=p_customer_id;
 c := greatest(1, (greatest(n,1)-1)/10+1);
 select exists(select 1 from public.club_reward_claims where customer_id=p_customer_id and cycle_number=c and reward_type='discount_10') into d;
 select exists(select 1 from public.club_reward_claims where customer_id=p_customer_id and cycle_number=c and reward_type='free_item') into f;
 return jsonb_build_object('total_stamps',n,'cycle',c,'cycle_stamps',least(10,n-(c-1)*10),
 'discount_available',n >= (c-1)*10+5 and not d,
 'free_item_available',n >= c*10 and not f,
 'discount_redeemed',d,'free_item_redeemed',f);
end $$;
revoke all on function public.club_reward_state(uuid) from public,anon,authenticated;

create or replace function public.club_redeem_reward(p_customer_id uuid,p_reward_type text,p_reward_choice text default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v jsonb; c int; choice text;
begin
 if auth.uid() is null or not public.has_staff_role('admin') then raise exception 'Solo administración'; end if;
 perform 1 from public.club_customers where id=p_customer_id for update;
 if not found then raise exception 'Socio no encontrado'; end if;
 v := public.club_reward_state(p_customer_id); c := (v->>'cycle')::int;
 if p_reward_type='discount_10' then
   if not (v->>'discount_available')::boolean then raise exception 'Descuento no disponible'; end if;
   if p_reward_choice is not null then raise exception 'El descuento no requiere elección'; end if;
 elsif p_reward_type='free_item' then
   if not (v->>'free_item_available')::boolean then raise exception 'Premio no disponible'; end if;
   choice := p_reward_choice;
   if choice is null or choice not in ('papas_1_topping','smash_whopper','cuarto_libra','cheese_burger') then
      raise exception 'Selecciona un premio válido';
   end if;
 else raise exception 'Tipo de premio inválido';
 end if;
 insert into public.club_reward_claims(customer_id,cycle_number,reward_type,reward_choice,redeemed_by)
 values(p_customer_id,c,p_reward_type,choice,auth.uid());
 return public.club_reward_state(p_customer_id);
end $$;
revoke all on function public.club_redeem_reward(uuid,text,text) from public,anon;
grant execute on function public.club_redeem_reward(uuid,text,text) to authenticated;

-- Actualiza la consulta privada de tarjeta para mostrar recompensas.
create or replace function public.club_view_card(p_token text)
returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare v_customer public.club_customers%rowtype; v_state jsonb;
begin
 if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
 select * into v_customer from public.club_customers
 where card_token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
 if not found then return null; end if;
 v_state:=public.club_reward_state(v_customer.id);
 return jsonb_build_object('name',v_customer.customer_name,'stamps',v_state->'total_stamps','rewards',v_state);
end $$;
revoke all on function public.club_view_card(text) from public;
grant execute on function public.club_view_card(text) to anon,authenticated;
