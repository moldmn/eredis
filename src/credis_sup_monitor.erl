-module(credis_sup_monitor).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(ETS_REDIS, cthulhu).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    ets:new(?ETS_REDIS, [public, named_table]),
    [ets:insert(?ETS_REDIS, {X, undefined}) || X<- lists:seq(0,16535)],
    {ok, { {one_for_one, 5, 10}, [?CHILD(credis_srv_monitor, worker)]} }.

