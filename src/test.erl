-module(test).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-define(ALIVE_SERVICE_DIR, "/ecenter/alive_services/").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Args) ->
  lager:info("test server start with args:~p", [Args]),
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) ->
  
  put(service_key, ?ALIVE_SERVICE_DIR++atom_to_list(?MODULE)),
  {ok, 0, 3000}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(timeout, Count) ->
  lager:info("test handle_info timeout"),
  if
    Count =:= 5 ->
      {stop, "crash", Count};
    true ->
     {noreply, Count+1, 3000}
  end;
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

