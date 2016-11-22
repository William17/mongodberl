%%%-------------------------------------------------------------------
%%% @author yunba
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Jul 2015 5:58 PM
%%%-------------------------------------------------------------------
-module(mongodberl).
-author("yunba").

-behaviour(supervisor).

%% API
-export([start_link/1, get_value_from_mongo/3, get_doc_from_mongo/2, make_sure_binary/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

-compile({parse_transform, lager_transform}).
-include_lib("elog/include/elog.hrl").

%%%===================================================================
%%% API functions
%%%===================================================================
get_value_from_mongo(PoolPid, Item, Key) ->
    execute(PoolPid, {get, Item, Key}).

get_doc_from_mongo(PoolPid, Key) ->
    execute(PoolPid, {get, Key}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Args :: term()) ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Args) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [Args]).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
        MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
        [ChildSpec :: supervisor:child_spec()]
    }} |
    ignore |
    {error, Reason :: term()}).
%%-----------------------------------------------
%%change Args to contain a Replset
%%------------------------------------------------
init([{replset, Param}] = [_Args]) ->
    {PoolName, ReplSet, MongoDbDatabase, MongodbConnNum} = Param,
    RestartStrategy = one_for_one,
    MaxRestarts = 1000,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    Pools = [
        {PoolName, [
            {size, MongodbConnNum},
            {max_overflow, 30}
        ],
            [{replset, ReplSet, MongoDbDatabase}]
        }
    ],

    PoolSpecs = lists:map(fun({Name, SizeArgs, WorkerArgs}) ->
        PoolArgs = [{name, {local, Name}},
            {worker_module, mongodberl_worker}] ++ SizeArgs,
        poolboy:child_spec(Name, PoolArgs, WorkerArgs)
                          end, Pools),

    {ok, {SupFlags, PoolSpecs}};
init([{single, Param}] = [_Args]) ->
    {PoolName, MongodbArg, MongoDbDatabase, MongodbConnNum} = Param,
    RestartStrategy = one_for_one,
    MaxRestarts = 1000,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    Pools = [
        {PoolName, [
            {size, MongodbConnNum},
            {max_overflow, 30}
        ],
            [{single, MongodbArg, MongoDbDatabase}]
        }
    ],

    PoolSpecs = lists:map(fun({Name, SizeArgs, WorkerArgs}) ->
        PoolArgs = [{name, {local, Name}},
            {worker_module, mongodberl_worker}] ++ SizeArgs,
        poolboy:child_spec(Name, PoolArgs, WorkerArgs)
                          end, Pools),

    {ok, {SupFlags, PoolSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

execute(PoolPid, Cmd) ->
    poolboy:transaction(PoolPid, fun(Worker) ->
        Req = case gen_server:call(Worker, get_connection_type) of
                  {ok, replset} ->
                      rs_connect;
                  {ok, single} ->
                      connect
              end,
        case gen_server:call(Worker, Req) of
            {ok, Mongo} ->
                case Cmd of
                    {get, Item, Key} ->
                        try
                            Mongo:set_encode_style(mochijson),
                            {ok, Doc} = Mongo:findOne("apps", [{"_id", {oid, make_sure_binary(Key)}}]),
                            case proplists:get_value(make_sure_binary(Item), Doc) of
                                undefined ->
                                    ?ERROR("find ~p from mongodb failed when appkey is ~p, reason ~p, find Doc ~p~n", [Item, Key, seckey_undefined, Doc]),
                                    {false, undefined};
                                Value ->
                                    ?DEBUG("worker: ~p~n", [Value]),
                                    {true, Value}
                            end
                        catch _:X ->
                            {false, <<"fail">>, X}
                        end;
                    {get, Key} ->
                        try
                            Mongo:set_encode_style(mochijson),
                            {ok, Doc} = Mongo:findOne("apps", [{"_id", {oid, make_sure_binary(Key)}}]),
                            {true, Doc}
                        catch _:X ->
                            {false, <<"fail">>, X}
                        end;
                    _ ->
                        {false, <<"cmd_not_supported">>}
                end;
            Error ->
                Error
        end
                                 end).

make_sure_binary(Data) ->
    if
        is_list(Data) ->
            list_to_binary(Data);
        is_integer(Data) ->
            integer_to_binary(Data);
        is_atom(Data) ->
            atom_to_binary(Data, latin1);
        true ->
            Data
    end.

