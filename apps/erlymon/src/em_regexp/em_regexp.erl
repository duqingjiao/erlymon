%%%-------------------------------------------------------------------
%%% @author Sergey Penkovsky
%%% @copyright (C) 2015, Sergey Penkovsky <sergey.penkovsky@gmail.com>
%%% @doc
%%%    Erlymon is an open source GPS tracking system for various GPS tracking devices.
%%%
%%%    Copyright (C) 2015, Sergey Penkovsky <sergey.penkovsky@gmail.com>.
%%%
%%%    This file is part of Erlymon.
%%%
%%%    Erlymon is free software: you can redistribute it and/or  modify
%%%    it under the terms of the GNU Affero General Public License, version 3,
%%%    as published by the Free Software Foundation.
%%%
%%%    Erlymon is distributed in the hope that it will be useful,
%%%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%%%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%%    GNU Affero General Public License for more details.
%%%
%%%    You should have received a copy of the GNU Affero General Public License
%%%    along with this program.  If not, see <http://www.gnu.org/licenses/>.
%%% @end
%%%-------------------------------------------------------------------
-module(em_regexp).
-author("Sergey Penkovsky <sergey.penkovsky@gmail.com>").

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([match/2]).
-export([test/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {cache}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(match(Data :: string(), Pattern :: string) ->
  {ok, Result :: string()} | {error, Reason :: term()}).
match(Data, Pattern) ->
  gen_server:call(?SERVER, {match, Data, Pattern}).

test() ->
  Pattern = list_to_binary([
      "(\\d{2})(\\d{2})(\\d{2});" ++
      "(\\d{2})(\\d{2})(\\d{2});" ++
      "(\\d{2})(\\d{2}.\\d+);" ++
      "([NS]);" ++
      "(\\d{3})(\\d{2}.\\d+);" ++
      "([EW]);" ++
      "(\\d+.?\\d*)?;" ++
      "(\\d+.?\\d*)?;" ++
      "(?:NA|(\\d+.?\\d*));" ++
      "(?:NA|(\\d+))" ++
      ";" ++
      "(?:NA|(\\d+.?\\d*));" ++
      "(?:NA|(\\d+));" ++
      "(?:NA|(\\d+));" ++
      "(?:NA|([^;]*));" ++
      "(?:NA|([^;]*));" ++
      "(?:NA|(.*))" ++
      "?"
  ]),
  Packet = <<"#D#110816;142342;5354.33140;N;02730.14582;E;0;0;0;NA;NA;NA;NA;;NA;NA\r\n">>,
  match(Packet, Pattern).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  em_logger:info("Init regexp service"),
  Cache = ets:new(regexp, [set, private]),
  {ok, #state{cache = Cache}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_call({match, Data, Pattern}, _From, State) ->
  do_match(State, Data, Pattern);
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
do_match(State, Data, Pattern) ->
  case do_compile_pattern(Pattern) of
    {ok, PatternCompile} ->
      case re:run(Data, PatternCompile) of
        {match, List} ->
          Res = lists:reverse(lists:foldl(fun(Param, Res) ->
            [do_read_param(Param, Data) | Res]
                                          end, [], List)),
          {reply, {ok, Res}, State};
        _ ->
          {reply, {error, <<"No match">>}, State}
      end;
    {error, Reason} ->
      {reply, {error, Reason}, State}
  end.

do_compile_pattern(Pattern) ->
  re:compile(Pattern).

do_read_param({-1, 0}, _) ->
  void;
do_read_param({Pos, Len}, Data) ->
  binary:part(Data, Pos, Len).
