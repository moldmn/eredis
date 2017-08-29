-module(credis_srv).
-define(SERVER, ?MODULE).
-define(ETS_REDIS, cthulhu).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).
-export([getkey/1, getkey/3]).
-export([q/1, q/2]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
start_link()->
    {ok, self()}
.

q(_, Command)->
    q(Command)
.
q([_] = Command) ->
    [{0, Pool}] = ets:lookup(?ETS_REDIS, 0),
    credis_pool:q(Pool, Command)
;
q([_, Param | _] = Command) ->
    Key = getkey(Param),
    SlotNum = crc16acorn:calc(Key) rem 16384,
    [{SlotNum, Pool}] = ets:lookup(?ETS_REDIS, SlotNum),
    credis_pool:q(Pool, Command)
    %%TODO: добавить анализ ответов.
.

%Составные ключи. redis.io/topics/cluster-spec  (Keys hash tags)
getkey(Binary) when is_binary(Binary)->  
   getkey(binary_to_list(Binary))
;
getkey(String)->
   getkey(String, [], String)
.

getkey([], _, FullKey)->
     FullKey
;
getkey([ ${, $} |_], [], FullKey)->
     FullKey
;
getkey([ ${, $} |_], [${], _FullKey)->
     ${
;
getkey([ ${ , F | Tail], [], FullKey)->
    getkey(Tail, [F], FullKey)
;
getkey([ $} | _], Token, _FullKey)->
    Token
;
getkey([ _Key | Tail], [], FullKey)->
    getkey(Tail, [], FullKey)
;
getkey([ Key | Tail], Token, FullKey)->
    getkey(Tail, Token ++ [Key], FullKey)
.

