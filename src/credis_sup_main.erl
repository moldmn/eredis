-module(credis_sup_main).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {one_for_one, 5, 10}, []}}.
    %{ok, { {one_for_one, 5, 10}, [?CHILD(credis_sup_monitor, supervisor), ?CHILD(credis_pool_sup, supervisor)]}}.

