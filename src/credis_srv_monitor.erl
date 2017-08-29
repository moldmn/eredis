-module(credis_srv_monitor).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-define(DATABASE, 0).
-define(ETS_REDIS, cthulhu).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, add_node/3, del_node/3, manualinit/1]).
-export([eredis_start/2, eredis_start/3]).

-record(rstate, {nodes=[]}).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
  gen_server:start_link(?MODULE, [], [])
.

add_node(Host, Port, Password) when is_list(Host)->
   add_node(list_to_binary(Host), Port, Password)
;
add_node(Host, Port, Password) when is_list(Port)->
   add_node(Host, list_to_binary(Port), Password)
;
add_node(Host, Port, Password) when is_list(Password)->
   add_node(Host, Port, list_to_binary(Password))
;
add_node(Host, Port, Password) when is_integer(Port)->
   add_node(Host, integer_to_binary(Port), Password)
;
add_node(Host, Port, Password)->
   {ok, Config} = application:get_env(eredis, cluster),
   NewConfig = (Config -- [{Host, Port, 0, Password}]) ++ [{Host, Port, 0, Password}],
   application:set_env(eredis, cluster, NewConfig)
.

del_node(Host, Port, Password) when is_list(Host)->
   del_node(list_to_binary(Host), Port, Password)
;
del_node(Host, Port, Password) when is_list(Port)->
   del_node(Host, list_to_binary(Port), Password)
;
del_node(Host, Port, Password) when is_list(Password)->
   del_node(Host, Port, list_to_binary(Password))
;
del_node(Host, Port, Password) when is_integer(Port)->
   del_node(Host, integer_to_binary(Port), Password)
;
del_node(Host, Port, Password)->
   {ok, Config} = application:get_env(eredis, cluster),
   NewConfig = Config -- [{Host, Port, 0, Password}],
   application:set_env(eredis, cluster, NewConfig)
.

manualinit(Pid)->
   Pid ! autoinit,
   ok
.

eredis_start(Host, Port) ->
    eredis_start(Host, Port, "")
.
eredis_start(Host, Port, Password) when is_binary(Host)-> eredis_start(binary_to_list(Host), Port, Password);
eredis_start(Host, Port, Password) when is_binary(Password)-> eredis_start(Host, Port, binary_to_list(Password));
eredis_start(Host, Port, Password) when is_binary(Port)-> eredis_start(Host, binary_to_integer(Port), Password);
eredis_start(Host, Port, Password) when is_list(Port)-> eredis_start(Host, list_to_integer(Port), Password);
eredis_start(Host, Port, Password) -> 
      OldState = process_flag(trap_exit, true),
      Result = eredis:start_link(Host, Port, ?DATABASE, Password),
      process_flag(trap_exit, OldState),
      Result
.

send_init(State)->
     case {application:get_env(eredis, coldstart), application:get_env(eredis, allredisdisabled, 200)} of
     {{ok, true}, Timeout} ->
          TimeoutSec = Timeout * 1000,
          error_logger:error_report([{?MODULE, handle_info}, {error, all_redis_disable}, {next, TimeoutSec}]),
          erlang:send_after(TimeoutSec, self(), autoinit),
          {noreply, #rstate{}}
     ;
     _->
         error_logger:error_report([{?MODULE, handle_info}, {error, all_redis_disable}, {coldstart,false}]),
         {stop, all_redis_disable, State}
     end
.
%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([]) ->
  self() ! autoinit,
  {ok, #rstate{}}
.

handle_call(_, _, State)->
  {reply, ok, State}
.
handle_cast(_Msg, State) ->
  {noreply, State}
.

handle_info(autoinit, State) ->
  {ok, ConfigNodes} = application:get_env(eredis, cluster),

  %%Избавляемся от доменных имен. Поддерживает только ipv4
  NormalNodes =   [ case inet:gethostbyname(binary_to_list(Host)) of
               {error, _}->
                   error_logger:error_report([{?MODULE, handle_info}, {error, <<"Bad hostname">>, Host}]),
                   []
               ;
               %%{ok,{hostent,"8.8.8.8",[],inet,4,[{8,8,8,8}]}}
               {ok, {hostent, _, [], inet, 4, [{Oct1, Oct2, Oct3, Oct4} | _]}} -> 
                   Oct1Bin = integer_to_binary(Oct1),
                   Oct2Bin = integer_to_binary(Oct2),
                   Oct3Bin = integer_to_binary(Oct3),
                   Oct4Bin = integer_to_binary(Oct4),
                   {<<Oct1Bin/binary, ".", Oct2Bin/binary, ".", Oct3Bin/binary, ".", Oct4Bin/binary>>, Port, Db, Password}
               end
             ||{Host, Port, Db, Password} <- ConfigNodes],

  NewState1 = [ { << Host/binary, ":", Port/binary>> , eredis_start(Host, Port, Password)} || {Host, Port, _, Password} <- NormalNodes ],
  %% И даляем неудачные запуски
  NewState = [ NSOK || {_HostPort, {ok, XPid}} = NSOK  <- NewState1, is_pid(XPid)],
  
  case NewState of
  []->
     send_init(State)
  ;
  [{_, {ok, PidSlots}}|_] ->
	 {ok, P1} = eredis:q(PidSlots, ["CLUSTER", "SLOTS"]),

         SlotNumber = [ 
                     {binary_to_integer(Start), binary_to_integer(Stop), <<MasterHost/binary, ":", MasterPort/binary>>} 
                     || [Start, Stop, [MasterHost, MasterPort] | _Slaves]  <- P1
         ],
    
         WorkerNodes = lists:sort([ 
                     <<MasterHost/binary, ":", MasterPort/binary>> 
                     || [_Start, _Stop, [MasterHost, MasterPort] | _Slaves]  <- P1
         ]),

         %%Секция остановки и запуска пулбоев
         WorkerCount = application:get_env(eredis, size_worker, 100),
         case WorkerNodes -- State#rstate.nodes of
         [] ->
             none %ничего не изменилось, ничего не делаем
         ;
         NewNodes when is_list(NewNodes)->
             error_logger:error_report([{?MODULE, handle_info}, {start_new_redis_poolboy, NewNodes}]),
             [
              begin 
                  [NewHost, NewPort] = binary:split(X, <<":">>),
                  credis_pool:create_pool(binary_to_atom(X, latin1), WorkerCount, binary_to_list(NewHost), binary_to_integer(NewPort)) 
              end || X <- NewNodes
             ]
         end,
         case State#rstate.nodes -- WorkerNodes of
         [] ->
             none %ничего не изменилось, ничего не делаем
         ;
         OldNodes when is_list(OldNodes)->
             error_logger:error_report([{?MODULE, handle_info}, {stop_old_redis_poolboy, OldNodes}]),
             [credis_pool:delete_pool(binary_to_atom(X, latin1)) || X <- OldNodes]
         end,

         [[ ets:insert(?ETS_REDIS, {X, binary_to_atom(Names, latin1)})  ||X <-lists:seq(Start, Stop) ] || {Start, Stop, Names} <- SlotNumber],

         TimeoutSec = application:get_env(eredis, ping_timeout, 500),
         erlang:send_after(TimeoutSec, self(), autoinit),
         {noreply, #rstate{ nodes = WorkerNodes }}
  end %%case NewState
;
handle_info(_Info, State) ->
  {noreply, State}
.

terminate(_Reason, _State) ->
  ok
.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}
.

