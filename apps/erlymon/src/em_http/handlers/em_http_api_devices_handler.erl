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
-module(em_http_api_devices_handler).
-author("Sergey Penkovsky <sergey.penkovsky@gmail.com>").

%% API

-export([init/2]).

-include("em_http.hrl").
-include("em_records.hrl").

-record(get_devices_params, {all = false, userId = 0}).
%% GET http://demo.traccar.org/api/device/get?_dc=1436251203853&page=1&start=0&limit=25
%% {"success":true,"data":[]}
-spec init(Req :: cowboy_req:req(), Opts :: any()) -> {ok, cowboy_req:req(), any()}.
init(Req, Opts) ->
  em_logger:info("SESSION: ~w", [cowboy_session:get(user, Req)]),
  case cowboy_session:get(user, Req) of
    {undefined, Req2} ->
      {ok, cowboy_req:reply(?STATUS_NOT_FOUND, Req2), Opts};
    {User, Req2} ->
      Method = cowboy_req:method(Req2),
      {ok, request(Method, Req2, User), Opts}
  end.

-spec request(Method :: binary(), Opts :: any(), User :: map()) -> cowboy_req:req().
request(?GET, Req, User) ->
  get_devices(Req, User);
request(?POST, Req, User) ->
  add_device(Req, User);
request(?PUT, Req, User) ->
  update_device(Req, User);
request(?DELETE, Req, User) ->
  remove_device(Req, User);
request(_, Req, _) ->
  %% Method not allowed.
  cowboy_req:reply(?STATUS_METHOD_NOT_ALLOWED, [], <<"Allowed GET,POST,PUT,DELETE requests.">>, Req).

-spec get_devices(Req :: cowboy_req:req(), User :: map()) -> cowboy_req:req().
get_devices(Req, User) ->
  Qs = cowboy_req:parse_qs(Req),
  Result = emodel:from_proplist(Qs, #get_devices_params{}, [
    {<<"all">>, optional, boolean, #get_devices_params.all, []},
    {<<"userId">>, optional, integer, #get_devices_params.userId, []}
  ]),
  case Result of
    {ok, #get_devices_params{all = true}} ->
      case em_permissions_manager:check_admin(User#user.id) of
        false ->
          cowboy_req:reply(?STATUS_FORBIDDEN, [], <<"Admin access required">>, Req);
        _ ->
          {ok, Devices} = em_data_manager:get_all_devices(),
          cowboy_req:reply(?STATUS_OK, ?HEADERS, em_model_device:to_str(Devices), Req)
      end;
    {ok, #get_devices_params{all = false, userId = UserId}} ->
      case em_permissions_manager:check_user(User#user.id, get_user_id(UserId, User)) of
        false ->
          cowboy_req:reply(?STATUS_FORBIDDEN, Req);
        _ ->
          {ok, Devices} = em_data_manager:get_devices(get_user_id(UserId, User)),
          cowboy_req:reply(?STATUS_OK, ?HEADERS, em_model_device:to_str(Devices), Req)
      end;
    _Reason ->
      cowboy_req:reply(?STATUS_UNKNOWN, [], <<"Invalid format.">>, Req)
  end.

get_user_id(0, User) ->
  User#user.id;
get_user_id(UserId, _) ->
  UserId.

-spec add_device(Req :: cowboy_req:req(), User :: map()) -> cowboy_req:req().
add_device(Req, User) ->
  {ok, [{JsonBin, true}], Req2} = cowboy_req:body_qs(Req),
  DeviceModel = em_json:decode(JsonBin),
  Device = em_data_manager:create_device(DeviceModel),
  em_data_manager:link_device(maps:get(<<"id">>, User), maps:get(<<"id">>, Device)),
  cowboy_req:reply(?STATUS_OK, ?HEADERS, em_json:encode(maps:remove(<<"_id">>, Device)), Req2).

-spec update_device(Req :: cowboy_req:req(), User :: map()) -> cowboy_req:req().
update_device(Req, User) ->
  {ok, [{JsonBin, true}], Req2} = cowboy_req:body_qs(Req),
  Device = em_json:decode(JsonBin),
  case em_permissions_manager:check_device(maps:get(<<"id">>, User), maps:get(<<"id">>, Device)) of
    false ->
      cowboy_req:reply(?STATUS_FORBIDDEN, [], <<"Device access denied">>, Req2);
    true ->
      em_data_manager:update_device(Device),
      cowboy_req:reply(?STATUS_OK, ?HEADERS, em_json:encode(Device), Req2)
  end.

-spec remove_device(Req :: cowboy_req:req(), User :: map()) -> cowboy_req:req().
remove_device(Req, User) ->
  {ok, [{JsonBin, true}], Req2} = cowboy_req:body_qs(Req),
  Device = em_json:decode(JsonBin),
  case em_permissions_manager:check_device(maps:get(<<"id">>, User), maps:get(<<"id">>, Device)) of
    false ->
      cowboy_req:reply(?STATUS_FORBIDDEN, [], <<"Device access denied">>, Req2);
    true ->
      em_data_manager:delete_device(Device),
      em_data_manager:unlink_device(maps:get(<<"id">>, Device)),
      cowboy_req:reply(?STATUS_OK, ?HEADERS, em_json:encode(maps:remove(<<"_id">>, Device)), Req2)
  end.