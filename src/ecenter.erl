-module(ecenter).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 3000).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) ->
  %% 

  {ok, Args, 0}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(timeout, State) ->
  %% Get myself
  %% Get Leader
  %% Is Me
  %% Is sup started

  case etcd:get_self() of
    {ok, Response} ->
      _Name  = ej:get({<<"name">>}, Response),
      Id     = ej:get({<<"id">>}, Response),
      _State = ej:get({<<"state">>}, Response),
      Leader = ej:get({<<"leaderInfo">>, <<"leader">>}, Response),

      case Id =:= Leader of
        true ->
          %% Leader is me
          safe_service_start();
        false ->
          ignore
      end;
    Error ->
      lager:error("etcd get self info error:~p", [Error]),
  end,
  {noreply, State, ?DEFAULT_TIMEOUT};
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
safe_service_start() ->
  %% get services
  Services          = [],
  %% Already start do not to start it
  AlreadyStarted    = filter_already_start(Servics, []),
  NeedStartServices = Services -- AlreadyStarted,
  start_services(NeedStartServices).

start_services([Service|Tail]) ->
  try
    start_service(Service)
  catch Error:Reason ->
          lager:error("ecenter error:~p Response:~p tracestack:~p", [
                                                                     Error,
                                                                     Reason,
                                                                     erlang:get_stacktrace()
                                                                    ]),
          error
  end;
start_service([]) -> ok.
