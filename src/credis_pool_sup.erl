-module(credis_pool_sup).
-behaviour(supervisor).

%% Include
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start_link/0, start_link/2]).
-export([create_pool/3, delete_pool/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(SupFlags, {one_for_one, 10, 10}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    start_link(none, local).
start_link(Pools, GlobalOrLocal) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Pools, GlobalOrLocal]).

%% ===================================================================
%% @doc create new pool.
%% @end
%% ===================================================================
-spec(create_pool(PoolName::atom(), Size::integer(), Options::[tuple()]) ->
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(PoolName, Size, Options) ->
    create_pool(local, PoolName, Size, Options).

%% ===================================================================
%% @doc create new pool, selectable name zone global or local.
%% @end
%% ===================================================================
-spec(create_pool(GlobalOrLocal::atom(), PoolName::atom(), Size::integer(), Options::[tuple()]) ->
             {ok, pid()} | {error,{already_started, pid()}}).

create_pool(GlobalOrLocal, PoolName, Size, Options) 
  when GlobalOrLocal =:= local;
       GlobalOrLocal =:= global ->

    SizeArgs = [{size, Size}, {max_overflow, 10}],
    PoolArgs = [{name, {GlobalOrLocal, PoolName}}, {worker_module, eredis}],
    PoolSpec = poolboy:child_spec(PoolName, PoolArgs ++ SizeArgs, Options),

    supervisor:start_child(?MODULE, PoolSpec).

%% ===================================================================
%% @doc delet pool and disconnected to Redis.
%% @end
%% ===================================================================
-spec(delete_pool(PoolName::atom()) -> ok | {error,not_found}).

delete_pool(PoolName) ->
    supervisor:terminate_child(?MODULE, PoolName),
    supervisor:delete_child(?MODULE, PoolName).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([none, _]) ->
    {ok, {?SupFlags, []}}
;
init([Pools, GlobalOrLocal]) ->
    PoolSpecs = lists:map(fun({Name, SizeArgs, WorkerArgs}) ->
        PoolArgs = [{name, {GlobalOrLocal, Name}},
                    {worker_module, eredis}] ++ SizeArgs,
        poolboy:child_spec(Name, PoolArgs, WorkerArgs)
    end, Pools),

    {ok, {?SupFlags, PoolSpecs}}
.

