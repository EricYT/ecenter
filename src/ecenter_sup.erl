-module(ecenter_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_service/3]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(CHILD_WITH_ARGS(I, TYPE, ARGS), {I, {I, start_link, [ARGS]}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_service(Serivce, Type, Args) ->
  ServiceSpec = ?CHILD_WITH_ARGS(Serivce, Type, Args),
  case supervisor:start_child(?MODULE, ServiceSpec) of
    {ok, SerivcePid}        -> {ok, SerivcePid};
    {ok, SerivcePid, _Info} -> {ok, SerivcePid};
    {error, Reason}         -> lager:error("ecenter_sup start service error:~p", [Reason]), {error, Reason}
  end.

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
  lager:info("ecenter_sup start"),
  %% center server
  CenterServer = ?CHILD(ecenter, worker),
  {ok, { {one_for_one, 5, 10}, [CenterServer]} }.

