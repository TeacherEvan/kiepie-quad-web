-- 0002_time_limit.sql
-- Host-authoritative match time limit. Client calls game.time_up() once the
-- lobby's match_seconds have elapsed; the server verifies the clock and writes
-- the winner. Safe to re-run.

create or replace function game.time_up()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid uuid := auth.uid();
    v_lobby public.lobbies;
    v_winner uuid;
    v_leader integer := -1;
    r record;
begin
    if v_uid is null then
        raise exception 'not_authenticated' using errcode = '42501';
    end if;

    select * into v_lobby
      from public.lobbies l
     where l.host_id = v_uid
       and l.status = 'playing'
       for update;
    if not found then
        raise exception 'not_host_or_not_playing' using errcode = '55000';
    end if;

    if coalesce((v_lobby.settings ->> 'match_seconds')::integer, 0) <= 0 then
        raise exception 'no_time_limit' using errcode = '55000';
    end if;
    if now() < v_lobby.started_at
        + ((v_lobby.settings ->> 'match_seconds')::integer || ' seconds')::interval then
        raise exception 'time_not_up' using errcode = '55000';
    end if;

    for r in
        select lp.user_id, lp.score
          from public.lobby_players lp
         where lp.lobby_id = v_lobby.id
         order by lp.score desc, lp.joined_at asc
    loop
        if r.score > v_leader then
            v_leader := r.score;
            v_winner := r.user_id;
        end if;
    end loop;

    update public.lobbies
       set status = 'finished', winner_id = v_winner
     where id = v_lobby.id
     returning * into v_lobby;

    return to_jsonb(v_lobby);
end;
$$;

revoke all on function game.time_up() from public, anon;
grant execute on function game.time_up() to authenticated;

comment on function game.time_up() is
    'Host-only: finish a timed match and declare the score leader the winner.';
