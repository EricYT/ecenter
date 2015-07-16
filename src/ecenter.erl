-module(ecenter).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 3000).
-define(SERVICE_DIR, "/ecenter/services/").
-define(ALIVE_SERVICE_DIR, "/ecenter/alive_services/").

-record(state, { services=maps:new() }).

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
  lager:info("ecenter start"),
  process_flag(trap_exit, true),
  check_service(),
  check_service_alive(),
  {ok, #state{}, 0}.

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({service_check_alive}, State) ->
  Services = State#state.services,
  NewServices = filter_alive_services(Services),
  lager:info("service_check alive_services :~p", [maps:to_list(NewServices)]),
  check_service_alive(),
  {noreply, State#state{ services=NewServices }};

handle_info({'DOWN', MonitorRef, Type, Object, Info}=Down, State) ->
  lager:error("handle_info process down:~p", [Down]),
  OriServices = State#state.services,
  NewServices =
  try
    {Service, _Pid} = maps:get(MonitorRef, OriServices),
    {ok, _} = etcd:delete(?ALIVE_SERVICE_DIR++atom_to_list(Service)),
    maps:remove(MonitorRef, OriServices)
  catch Error:Reason ->
          lager:error("handle_info down ~p", [{Error, Reason, erlang:get_stacktrace()}]),
          OriServices
  end,
  {noreply, State#state{ services=NewServices }};

handle_info({service_check}, State) ->
  %% Get myself
  %% Get Leader
  %% Is Me
  %% Is sup started
  lager:info("ecenter timeout"),
  AddServices =
  case etcd:self() of
    {ok, Response} ->
      Id     = ej:get({<<"id">>}, Response),
      Leader = ej:get({<<"leaderInfo">>, <<"leader">>}, Response),
%%      lager:info("self:~p", [Response]),
      case Id =:= Leader of
        true ->
          %% Leader is me
          lager:info("ecenter leader is me"),
          safe_service_start();
        false ->
          []
      end;
    Error ->
      lager:error("etcd get self info error:~p", [Error]),
      []
  end,
  OriServices = State#state.services,
  lager:info("+++++++++++++ AddServices:~p OriServices:~p", [maps:to_list(AddServices), maps:to_list(OriServices)]),
  check_service(),
  {noreply, State#state{ services=maps:merge(OriServices, AddServices) }};
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
  %%TODO: the struct of serice
  Services = get_all_services(),
  %% Filter Already start
  NeedStartServices = filter_already_started(Services),
  lager:info("safe_service_start need start services:~p", [NeedStartServices]),
  start_services(NeedStartServices, maps:new()).

start_services([Service|Tail], Acc) ->
  try
    lager:info("start_services :~p", [Service]),
    {Ref, ServiceAndPid} = start_service(Service),
    start_services(Tail, maps:put(Ref, ServiceAndPid, Acc))
  catch
    Error:Reason ->
      lager:error("ecenter error:~p Response:~p tracestack:~p", [
                                                                 Error,
                                                                 Reason,
                                                                 erlang:get_stacktrace()
                                                                ]),
      error
  end;
start_services([], Acc) -> Acc.

start_service({Module, Function, Args}) ->
  io:format("-----------> start services:~p~n", [Module]),
  {ok, Pid} = Module:Function(Args),
  Ref = erlang:monitor(process, Pid),
  {ok, _} = etcd:insert(?ALIVE_SERVICE_DIR++atom_to_list(Module), pid_to_list(Pid), 5),
  {Ref, {Module, Pid}}.

get_all_services() ->
  case etcd:read(?SERVICE_DIR, true) of
    {ok, Response} ->
      lager:info("-------------> Services:~p", [Response]),
      %%TODO: services
      %% Can not put args into etcd
      [{test, start_link, ["hello, world"]}];
    Error ->
      lager:error("ecenter get services error:~p", [Error]),
      []
  end.

filter_already_started(Services) ->
  case etcd:read(?ALIVE_SERVICE_DIR, true) of
    {ok, Response} ->
      lager:info("-----------> already_started:~p", [Response]),
      AlreadyStarted = ej:get({<<"node">>, <<"nodes">>}, Response, []),
      AlreadyStarted_= filter_services(AlreadyStarted, []),
      lager:info("-----------> already_started:~p", [AlreadyStarted_]),
      lists:filter(fun({Service, _Type, _Args}=Service_) -> not lists:member(Service, AlreadyStarted_) end, Services);
    {error, Error} ->
      lager:error("ecenter get already services error:~p", [Error]),
      []
  end.

filter_services([Service|Tail], Acc) ->
  Keys     = ej:get({<<"key">>}, Service),
  KeyPart  = binary_to_atom(lists:last(binary:split(Keys, [<<"/">>], [global])), utf8),
  filter_services(Tail, [KeyPart|Acc]);
filter_services([], Acc) -> Acc.

check_service_alive() ->
  erlang:send_after(?DEFAULT_TIMEOUT, ?MODULE, {service_check_alive}).

check_service() ->
  erlang:send_after(?DEFAULT_TIMEOUT, ?MODULE, {service_check}).

filter_alive_services(Services) ->
  ServiceList  = maps:to_list(Services),
  AliveServices= filter_alive_services(ServiceList, []),
  maps:from_list(AliveServices).

filter_alive_services([{_Ref, {Service, Pid}}=S|Tail], Acc) ->
  case erlang:is_process_alive(Pid) of
    true ->
      {ok, _} = etcd:set(?ALIVE_SERVICE_DIR++atom_to_list(Service), pid_to_list(Pid), 5),
      filter_alive_services(Tail, [S|Acc]);
    false ->
      {ok, _} = etcd:delete(?ALIVE_SERVICE_DIR++atom_to_list(Service)),
      filter_alive_services(Tail, Acc)
  end;
filter_alive_services([], Acc) -> Acc.

