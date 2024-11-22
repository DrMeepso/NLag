extends Node

enum CHANNELS{
	ACTOR_UPDATE, 
	ACTOR_ACTION, 
	GAME_STATE, 
	CHALK, 
	GUITAR, 
	ACTOR_ANIMATION, 
	SPEECH, 
}
enum LOBBY_TYPES{
	PUBLIC, CODE_ONLY, FRIENDS_ONLY, OFFLINE
}

const KNOWN_DEVELOPERS = [156659485]
const KNOWN_CONTRIBUTORS = [
	115049888, 
	149647659, 
	147860108, 
	338666471, 
	88153235, 
	97469728, 
	856075122, 
	127201761, 
	865913658, 
	255221212, 
	392795922, 
]

const MAX_OWNED_ACTOR_LIMIT = 32
const MAX_PACKET_TIMEOUT_LIMIT = 1500
const MAX_MAJOR_PACKET_TIMEOUT_LIMIT = 3000
const PACKET_READ_LIMIT = 42
const TICKRATE = 16.0
const COMPRESSION_TYPE = File.COMPRESSION_GZIP

var STEAM_ENABLED = true
var PLAYING_OFFLINE = false
var IS_OWNED = false
var IS_ONLINE = false
var GAME_MASTER = false
var STEAM_ID = 0
var STEAM_USERNAME = ""
var PACK
var JOIN_ID_PROMPT = - 1

var STEAM_LOBBY_ID = 0
var LOBBY_CODE = ""
var LOBBY_MEMBERS = []
var OWNED_ACTORS = []
var ACTOR_ACTIONS = {}
var ACTOR_DATA = {}
var ACTOR_ANIMATION_DATA = {}
var SERVER_CREATION_TYPE = 0
var PING_DICTIONARY = {}
var LOBBY_CHUNK_SIZE = 50

var GAMECHAT = ""
var GAMECHAT_COLLECTIONS = []
var LOCAL_GAMECHAT = ""
var LOCAL_GAMECHAT_COLLECTIONS = []

var SERVER_SETUP_TAGS = []
var SERVER_SETUP_TITLE = ""
var SERVER_SETUP_CAP = 0
var SERVER_AGE_LIMIT = false
var CODE_ENABLED = false

var BULK_PACKET_READ_TIMER = 0

var KNOWN_GAME_MASTER = - 1

var MESSAGE_ORIGIN = Vector3.ZERO
var MESSAGE_ZONE = ""

var CONNECTED_TO_LOBBY_PROPER = false
var SESSIONS_ACCEPTED = []
var REPLICATIONS_RECIEVED = []

var PACKET_INFORMATION = {}
var FLUSH_PACKET_INFORMATION = {}
var PACKET_TIMEOUTS = []
var FORCE_DISCONNECT_PLAYERS = []
var MESSAGE_COUNT_TRACKER = {}

var NETWORK_TIMER
signal _network_tick

signal _connected_to_lobby
signal _actors_recieved
signal _user_disconnected(id)
signal _user_connected(id)
signal _all_user_data_obtained
signal _instance_actor
signal _members_updated
signal _tent_update
signal _chat_update
signal _new_player_join(id)
signal _new_player_join_empty
signal _webfishing_lobbies_returned(lobbies)

func _init():
	
	
	if not STEAM_ENABLED: return 
	OS.set_environment("SteamAppId", str(3146520))
	OS.set_environment("SteamGameId", str(3146520))

func _ready():
	if not STEAM_ENABLED: return 
	var INIT = Steam.steamInit()
	
	if INIT["status"] != 1:
		print("Failed to initialize Steam. Shutting down. %s" % INIT["status"])
		get_tree().quit()
	
	IS_OWNED = Steam.isSubscribed()
	IS_ONLINE = Steam.loggedOn()
	STEAM_ID = Steam.getSteamID()
	STEAM_USERNAME = Steam.getPersonaName()
	print("Steam Active under username: ", STEAM_USERNAME, " ID: ", STEAM_ID)
	
	if IS_OWNED == false:
		print("User does not own game.")
		get_tree().quit()
	
	Steam.connect("lobby_created", self, "_on_Lobby_Created")
	Steam.connect("lobby_joined", self, "_on_Lobby_Joined")
	Steam.connect("join_requested", self, "_on_Lobby_Join_Requested")
	Steam.connect("p2p_session_request", self, "_on_P2P_Session_Request")
	Steam.connect("persona_state_change", self, "_on_Persona_Change")
	Steam.connect("lobby_chat_update", self, "_on_Lobby_Chat_Update")
	
	_check_command_line()
	
	NETWORK_TIMER = Timer.new()
	add_child(NETWORK_TIMER)
	NETWORK_TIMER.wait_time = 1.0 / TICKRATE
	NETWORK_TIMER.connect("timeout", self, "emit_signal", ["_network_tick"])
	NETWORK_TIMER.start()
	
	var PACKET_FLUSH_TIMER = Timer.new()
	add_child(PACKET_FLUSH_TIMER)
	PACKET_FLUSH_TIMER.wait_time = 5.0
	PACKET_FLUSH_TIMER.connect("timeout", self, "_packet_flush")
	PACKET_FLUSH_TIMER.start()
	
	var MESSAGE_COUNT_TIMER = Timer.new()
	add_child(MESSAGE_COUNT_TIMER)
	MESSAGE_COUNT_TIMER.wait_time = 1.5
	MESSAGE_COUNT_TIMER.connect("timeout", self, "_message_flush")
	MESSAGE_COUNT_TIMER.start()


func _check_command_line():
	var these_arguments: Array = OS.get_cmdline_args()
	if these_arguments.size() > 0:
		if these_arguments[0] == "+connect_lobby":
			if int(these_arguments[1]) > 0:
				print("Command line lobby ID: %s" % these_arguments[1])
				JOIN_ID_PROMPT = int(these_arguments[1])

------------------------------------------------------------------------------------------------
func _process(delta):
	if not STEAM_ENABLED: return 
	Steam.run_callbacks()
	
	if STEAM_LOBBY_ID <= 0: return 
	for channel in CHANNELS.size():
		_read_all_P2P_packets(channel)
-------------------------------------------------------------------------------------------------
func _read_all_P2P_packets(channel = 0, read_count = 0):
	if read_count >= PACKET_READ_LIMIT:
		return 
	
	if Steam.getAvailableP2PPacketSize(channel) > 0:
		_read_P2P_Packet(channel)
		_read_all_P2P_packets(channel, read_count + 1)
------------------------------------------------------------------------------------------------
func _update_chat(text, local = false):
	var max_message_length = 512
	var max_chat_length = 128
	
	text = text.left(max_message_length)
	
	var final_text = ""
	
	if not local:
		text = "\n" + text
		GAMECHAT_COLLECTIONS.append(text)
		if GAMECHAT_COLLECTIONS.size() > max_chat_length:
			GAMECHAT_COLLECTIONS.remove(0)
		
		GAMECHAT = ""
		for msg in GAMECHAT_COLLECTIONS:
			GAMECHAT = GAMECHAT + msg
		
	else :
		text = "\n" + "[color=#a4756a][​local​] [/color]" + text
		LOCAL_GAMECHAT_COLLECTIONS.append(text)
		if LOCAL_GAMECHAT_COLLECTIONS.size() > max_chat_length:
			LOCAL_GAMECHAT_COLLECTIONS.remove(0)
		
		LOCAL_GAMECHAT = ""
		for msg in LOCAL_GAMECHAT_COLLECTIONS:
			LOCAL_GAMECHAT = LOCAL_GAMECHAT + msg
	
	emit_signal("_chat_update")

func _recieve_safe_message(user_id, color, message, local = false):
	
	var username = _get_username_from_id(user_id)
	username = username.replace("[", "")
	username = username.replace("]", "")
	
	
	var filter_message = message
	filter_message = filter_message.replace("[", "")
	filter_message = filter_message.replace("]", "")
	
	if OptionsMenu.chat_filter:
		filter_message = SwearFilter._filter_string(filter_message)
	
	var final_message = filter_message.replace("%u", "[color=#" + str(color) + "]" + username + "[/color]")
	_update_chat(final_message, local)





func _unlock_achievement(id):
	var achievement = Steam.getAchievement(id)
	if not achievement.ret:
		print("Achievement ", id, " does not exist.")
		return 
	if achievement.achieved:
		print("Achievement ", id, " already obtained.")
		return 
	Steam.setAchievement(id)
	Steam.storeStats()

func _update_stat(id, new):
	Steam.setStatInt(id, int(new))
	Steam.storeStats()





func set_rich_presence(token):
	
	var setting_presence = Steam.setRichPresence("steam_display", token)





func _reset_lobby_status():
	print("Resetting Lobby Status...")
	PlayerData.players_banned.clear()
	STEAM_LOBBY_ID = 0
	GAME_MASTER = false
	SESSIONS_ACCEPTED.clear()
	REPLICATIONS_RECIEVED.clear()
	LOBBY_MEMBERS.clear()
	OWNED_ACTORS.clear()
	FLUSH_PACKET_INFORMATION.clear()
	PACKET_TIMEOUTS.clear()
	MESSAGE_COUNT_TRACKER = {}
	SERVER_AGE_LIMIT = false
	
	FORCE_DISCONNECT_PLAYERS.clear()
	for i in PlayerData.players_hidden:
		FORCE_DISCONNECT_PLAYERS.append(i)
	
	_wipe_chat()

func _wipe_chat():
	GAMECHAT = ""
	GAMECHAT_COLLECTIONS.clear()
	LOCAL_GAMECHAT = ""
	LOCAL_GAMECHAT_COLLECTIONS.clear()

func _create_Lobby(type, player_limit = 12, tags = [], display_name = ""):
	_leave_lobby()
	_reset_lobby_status()
	
	if STEAM_LOBBY_ID > 0: return 
	GAME_MASTER = true
	
	var lobby_type = Steam.LOBBY_TYPE_PUBLIC
	match type:
		LOBBY_TYPES.PUBLIC: lobby_type = Steam.LOBBY_TYPE_PUBLIC
		LOBBY_TYPES.CODE_ONLY: lobby_type = Steam.LOBBY_TYPE_INVISIBLE
		LOBBY_TYPES.FRIENDS_ONLY: lobby_type = Steam.LOBBY_TYPE_FRIENDS_ONLY
	
	SERVER_CREATION_TYPE = type
	SERVER_SETUP_TAGS = tags
	SERVER_SETUP_CAP = player_limit
	SERVER_SETUP_TITLE = display_name
	SERVER_AGE_LIMIT = tags.has("18+")
	Steam.createLobby(lobby_type, player_limit)
	print("Creating Lobby with a ", player_limit, " player cap.")

func _join_Lobby(lobby_id):
	_leave_lobby()
	_reset_lobby_status()
	Steam.joinLobby(lobby_id)

func _connect_to_lobby(id):
	var ver = Steam.getLobbyData(id, "version")
	print("GAME VER: ", ver)
	
	if ver:
		if ver != str(Globals.GAME_VERSION):
			_update_chat("Game version does not match host!")
			PopupMessage._show_popup("Game Version: " + str(Globals.GAME_VERSION) + ", does not match lobby's version: " + str(ver))
			Globals._exit_game()
			return 
	
	
	var blocked_players = Steam.getLobbyData(id, "banned_players")
	var split = blocked_players.split(",")
	for i in split:
		if int(i) == STEAM_ID:
			_update_chat("You have been banned from this lobby.")
			PopupMessage._show_popup("You have been banned from this lobby.")
			Globals._exit_game()
			return 
	
	PLAYING_OFFLINE = false
	
	_join_Lobby(id)
	Globals._enter_game()

func _leave_lobby():
	if STEAM_LOBBY_ID > 0:
		if GAME_MASTER:
			_host_left_lobby()
			yield (get_tree().create_timer(1.0), "timeout")
		
		_update_chat("Leaving lobby.")
		Steam.leaveLobby(STEAM_LOBBY_ID)
		STEAM_LOBBY_ID = 0
		
		for MEMBER in LOBBY_MEMBERS:
			Steam.closeP2PSessionWithUser(MEMBER["steam_id"])
		LOBBY_MEMBERS.clear()

func _on_Lobby_Created(connect, lobby_id):
	if connect != 1: return 
	
	randomize()
	var code = ""
	var characters = "abcdefghijklmnopqrstuvwxyz1234567890"
	for i in 6:
		code += characters[randi() % characters.length()]
	code = code.to_upper()
	LOBBY_CODE = code
	
	
	var lobby_type = ["public", "code_only", "friends_only", "offline"][SERVER_CREATION_TYPE]
	var joinable = lobby_type == "public"
	var public = "true" if lobby_type == "public" else "false"
	var age_limit = "true" if SERVER_SETUP_TAGS.has("18+") else ""
	
	CODE_ENABLED = lobby_type == "code_only" or lobby_type == "public"
	PLAYING_OFFLINE = false
	
	STEAM_LOBBY_ID = lobby_id
	_update_chat("Created Lobby.")
	Steam.setLobbyJoinable(lobby_id, true)
	Steam.setLobbyData(lobby_id, "name", str(STEAM_USERNAME))
	Steam.setLobbyData(lobby_id, "lobby_name", str(SERVER_SETUP_TITLE))
	Steam.setLobbyData(lobby_id, "ref", "webfishing_gamelobby")
	Steam.setLobbyData(lobby_id, "version", str(Globals.GAME_VERSION))
	Steam.setLobbyData(lobby_id, "code", code)
	Steam.setLobbyData(lobby_id, "type", lobby_type)
	Steam.setLobbyData(lobby_id, "age_limit", age_limit)
	Steam.setLobbyData(lobby_id, "public", public)
	Steam.setLobbyData(lobby_id, "cap", str(SERVER_SETUP_CAP))
	Steam.setLobbyData(lobby_id, "banned_players", "")
	Steam.allowP2PPacketRelay(true)
	
	
	Steam.setLobbyData(lobby_id, "server_browser_value", str(0))

func _on_Lobby_Joined(lobby_id, _perms, _locked, response):
	if response == 1:
		STEAM_LOBBY_ID = lobby_id
		LOBBY_CODE = Steam.getLobbyData(lobby_id, "code")
		
		PlayerData.player_saved_position = Vector3.ZERO
		PlayerData.player_saved_zone = ""
		if Network.GAME_MASTER: Network.KNOWN_GAME_MASTER = Network.STEAM_ID
		else : Network.KNOWN_GAME_MASTER = Steam.getLobbyOwner(lobby_id)
		
		var lobby_type = Steam.getLobbyData(STEAM_LOBBY_ID, "type")
		CODE_ENABLED = lobby_type == "code_only" or lobby_type == "public"
		SERVER_AGE_LIMIT = Steam.getLobbyData(STEAM_LOBBY_ID, "age_limit") == "true"
		
		_update_chat("Joined Lobby.")
		_get_lobby_members(true)
		_make_P2P_handshake()
		emit_signal("_connected_to_lobby")
	else :
		_update_chat("Error Joining Lobby!")

func _get_lobby_members(chat = false):
	LOBBY_MEMBERS.clear()
	
	
	var user_count = 0
	
	var MEMBERS = Steam.getNumLobbyMembers(Network.STEAM_LOBBY_ID)
	for MEMBER in range(0, MEMBERS):
		var MEMBER_ID = Steam.getLobbyMemberByIndex(Network.STEAM_LOBBY_ID, MEMBER)
		var MEMBER_NAME = Steam.getFriendPersonaName(MEMBER_ID)
		_add_lobby_member(MEMBER_ID, MEMBER_NAME)
		
		if MEMBER_ID == STEAM_ID: user_count += 1
	emit_signal("_members_updated")
	
	if user_count >= 2:
		PlayerData._send_notification("Duplicate Steam ID Found. Returning to Menu.", 1)
		Globals._exit_game()
	
	if chat:
		if LOBBY_MEMBERS.size() > 1: _update_chat(str(LOBBY_MEMBERS.size() - 1) + " other player(s) found.")

func _add_lobby_member(steam_id, steam_name):
	LOBBY_MEMBERS.append({"steam_id": steam_id, "steam_name": steam_name, "ping": - 1})

func _on_Lobby_Join_Requested(lobby_id, friend_id):
	JOIN_ID_PROMPT = lobby_id
	Globals._exit_game()

func _on_P2P_Session_Request(remoteID):
	
	var ACTIVE_MEMBERS = []
	var MEMBERS = Steam.getNumLobbyMembers(Network.STEAM_LOBBY_ID)
	for MEMBER in range(0, MEMBERS):
		var MEMBER_ID = Steam.getLobbyMemberByIndex(Network.STEAM_LOBBY_ID, MEMBER)
		ACTIVE_MEMBERS.append(MEMBER_ID)
	
	if not ACTIVE_MEMBERS.has(remoteID):
		print("P2P Session Denied- user is no longer in Lobby.")
		return 
	
	if FORCE_DISCONNECT_PLAYERS.has(int(remoteID)):
		print("P2P Session Denied- player is no longer allowed in lobby.")
		var state = Steam.getP2PSessionState(remoteID)
		if not state.empty() and state != null:
			if Steam.getP2PSessionState(remoteID).connection_active == true: Steam.closeP2PSessionWithUser(remoteID)
		return 
	
	var success = Steam.acceptP2PSessionWithUser(remoteID)
	if success and not SESSIONS_ACCEPTED.has(remoteID): SESSIONS_ACCEPTED.append(remoteID)
	print("Accepted Session Request from ", remoteID, ": ", success)
	_make_P2P_handshake()

func _make_P2P_handshake():
	_send_P2P_Packet({"type": "handshake", "user_id": STEAM_ID}, "all", 0, CHANNELS.GAME_STATE)

func _on_Persona_Change(steam_id, _flag):
	_get_lobby_members()

func _on_Lobby_Chat_Update(lobby_id, changed_id, making_change_id, chat_state):
	print("[STEAM] Lobby ID: " + str(lobby_id) + ", Changed ID: " + str(changed_id) + ", Making Change: " + str(making_change_id) + ", Chat State: " + str(chat_state))
	
	if chat_state == 1:
		_delayed_chat_update_message(making_change_id, "%u joined the game.", 1.5)
		emit_signal("_user_connected", making_change_id)
	elif chat_state == 2:
		_recieve_safe_message(making_change_id, "ffeed5", "%u left the game.", false)
		emit_signal("_user_disconnected", making_change_id)
		
		Steam.closeP2PSessionWithUser(making_change_id)
	
	_get_lobby_members()

func _delayed_chat_update_message(user_id, message, delay):
	yield (get_tree().create_timer(delay), "timeout")
	_recieve_safe_message(user_id, "ffeed5", message, false)

func _search_for_lobby(code):
	var lobby_found = - 1
	
	code = code.to_upper()
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("code", str(code), Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()
	var lobbies = yield (Steam, "lobby_match_list")
	if lobbies.size() > 0:
		var LOBBY = lobbies[0]
		
		var LOBBY_PLAYERS = Steam.getNumLobbyMembers(LOBBY)
		var LOBBY_MAX_PLAYERS = Steam.getLobbyData(LOBBY, "cap")
		var LOBBY_VERSION = Steam.getLobbyData(LOBBY, "version")
		
		lobby_found = LOBBY
		if LOBBY_PLAYERS >= int(LOBBY_MAX_PLAYERS): lobby_found = - 2
		if str(LOBBY_VERSION) != str(Globals.GAME_VERSION): lobby_found = - 3
	
	if lobby_found != - 1:
		Network._connect_to_lobby(lobby_found)
		yield (Network, "_connected_to_lobby")
		Globals._enter_game()
		print("Joining Lobby ", lobby_found)
		return true
	elif lobby_found == - 2:
		PopupMessage._show_popup("Lobby " + str(code) + " is full")
		Globals._exit_game()
		return false
	elif lobby_found == - 3:
		PopupMessage._show_popup("Lobby " + str(code) + "'s version does not match your version")
		Globals._exit_game()
		return false
	else :
		PopupMessage._show_popup("No server found with code " + str(code))
		Globals._exit_game()
		return false

func _create_custom_lobby(type, player_limit, tags, display_name):
	Network.GAME_MASTER = true
	
	_reset_lobby_status()
	
	if type != LOBBY_TYPES.OFFLINE:
		PLAYING_OFFLINE = false
		Network._create_Lobby(type, player_limit, tags, display_name)
		yield (Network, "_connected_to_lobby")
	else :
		PLAYING_OFFLINE = true
	
	Globals._enter_game()
	print("Creating Lobby")

func _get_username_from_id(id):
	if PLAYING_OFFLINE:
		return STEAM_USERNAME
	
	for member in LOBBY_MEMBERS:
		if member["steam_id"] == id:
			return member["steam_name"]
	return "null"

func _closing_app():
	if GAME_MASTER: _host_left_lobby()

func _kick_player(id):
	_send_P2P_Packet({"type": "kick"}, str(id), 2, Network.CHANNELS.GAME_STATE)

func _ban_player(id):
	PlayerData._ban_player(id)
	_send_P2P_Packet({"type": "ban"}, str(id), 2, Network.CHANNELS.GAME_STATE)
	_send_P2P_Packet({"type": "force_disconnect_player", "user_id": str(id)}, "all", 2, Network.CHANNELS.GAME_STATE)

func _force_close_id(id):
	if int(id) == STEAM_ID: return 
	
	FORCE_DISCONNECT_PLAYERS.append(int(id))
	emit_signal("_user_disconnected", id)
	PlayerData._send_notification("Connection closed with player.")
	Steam.closeP2PSessionWithUser(id)
	
	for actor in get_tree().get_nodes_in_group("actor"):
		if actor.owner_id == id: actor.queue_free()

func _reopen_closed_id(id):
	if int(id) == STEAM_ID: return 
	
	FORCE_DISCONNECT_PLAYERS.erase(int(id))
	PlayerData._send_notification("Connection re-opened with player.")
	Steam.acceptP2PSessionWithUser(id)



func _find_all_webfishing_lobbies(version_match = false, age_limit = false, slots_open = false):
	var total_lobbies = []
	
	var nulls = 0
	for search_filter in 20:
		print("Searching filter ", search_filter)
		Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
		Steam.addRequestLobbyListStringFilter("public", "true", Steam.LOBBY_COMPARISON_EQUAL)
		
		if version_match: Steam.addRequestLobbyListStringFilter("version", str(Globals.GAME_VERSION), Steam.LOBBY_COMPARISON_EQUAL)
		if age_limit: Steam.addRequestLobbyListStringFilter("age_limit", "", Steam.LOBBY_COMPARISON_EQUAL)
		if slots_open: Steam.addRequestLobbyListFilterSlotsAvailable(1)
		
		search_filter -= 1
		if search_filter != - 1: Steam.addRequestLobbyListStringFilter("server_browser_value", str(search_filter), Steam.LOBBY_COMPARISON_EQUAL)
		
		Steam.requestLobbyList()
		var lobbies = yield (Steam, "lobby_match_list")
		print(lobbies.size(), " Lobbies found for Filter ", search_filter)
		
		if lobbies.size() <= 0:
			nulls += 1
			if nulls > 3: break
		
		total_lobbies.append_array(lobbies)
	
	print(total_lobbies.size(), " servers found.")
	emit_signal("_webfishing_lobbies_returned", total_lobbies)
	return total_lobbies

func _set_server_browser_value():
	randomize()
	var value = randi() % 20
	print("Setting Server Browser Value to: ", value)
	Steam.setLobbyData(STEAM_LOBBY_ID, "server_browser_value", str(value))





func _request_actors():
	if PLAYING_OFFLINE or STEAM_LOBBY_ID <= 0: return 
	_send_P2P_Packet({"type": "request_actors", "user_id": str(STEAM_ID)}, "peers", 2, CHANNELS.GAME_STATE)

func _create_replication_data(id):
	var data = []
	
	for actor in OWNED_ACTORS:
		if not is_instance_valid(actor): continue
		var new_data = actor._request_saved_data()
		data.append(new_data)
	
	print("Sending all owned Actors to ", str(id), " data: ", data)
	_send_P2P_Packet({"type": "actor_request_send", "list": data}, str(id), 2, CHANNELS.GAME_STATE)

func _replicate_actors(list, from):
	if REPLICATIONS_RECIEVED.has(from):
		print("Replication Failed")
		return 
	
	print("Recieved actors: ", list)
	
	var existing_actor_ids = []
	for actor in get_tree().get_nodes_in_group("actor"):
		existing_actor_ids.append(actor.actor_id)
	REPLICATIONS_RECIEVED.append(from)
	
	for actor in list:
		if existing_actor_ids.has(actor["id"]):
			print("Actor Already Exists, skipping!")
			continue
		
		var dict = {"actor_type": actor["type"], "at": Vector3.ZERO, "rot": Vector3.ZERO, "zone": "", "zone_owner": - 1, "actor_id": actor["id"], "creator_id": actor["owner"], "data": {}}
		emit_signal("_instance_actor", dict, from)

func _sync_create_actor(actor_type, at, zone, id = - 1, creator = STEAM_ID, rotation = Vector3.ZERO, zone_owner = - 1):
	randomize()
	if id == - 1: id = randi()
	var dict = {"actor_type": actor_type, "at": at, "zone": zone, "actor_id": id, "creator_id": creator, "rot": rotation, "zone_owner": zone_owner}
	_send_P2P_Packet({"type": "instance_actor", "params": dict}, "peers", 2, CHANNELS.GAME_STATE)
	emit_signal("_instance_actor", dict)
	return id

func _send_actor_animation_update(actor_id, data):
	_send_P2P_Packet({"type": "actor_animation_update", "actor_id": actor_id, "data": data}, "peers", 0, CHANNELS.ACTOR_ANIMATION)

func _send_actor_action(id, action, params = [], all = true, channel = CHANNELS.ACTOR_ACTION):
	var target = "all" if all else "peers"
	_send_P2P_Packet({"type": "actor_action", "actor_id": id, "action": action, "params": params}, target, 2, channel)

func _send_message(message, color, local = false):
	if not _message_cap(STEAM_ID):
		_update_chat("Sending too many messages too quickly!", false)
		_update_chat("Sending too many messages too quickly!", true)
		return 
	
	var msg_pos = MESSAGE_ORIGIN.round()
	
	_recieve_safe_message(STEAM_ID, color, message, local)
	_send_P2P_Packet({"type": "message", "message": message, "color": color, "local": local, "position": MESSAGE_ORIGIN, "zone": MESSAGE_ZONE, "zone_owner": PlayerData.player_saved_zone_owner}, "peers", 2, CHANNELS.GAME_STATE)

func _host_left_lobby():
	_send_P2P_Packet({"type": "server_close"}, "peers", 2, CHANNELS.GAME_STATE)

func _replication_check():
	for lobby_member in LOBBY_MEMBERS:
		if not REPLICATIONS_RECIEVED.has(lobby_member["steam_id"]):
			print("Missing Replication from: ", lobby_member["steam_id"])
			_send_P2P_Packet({"type": "request_actors", "user_id": str(STEAM_ID)}, str(lobby_member["steam_id"]), 2, CHANNELS.GAME_STATE)





func _send_P2P_Packet(packet_data, target = "all", type = 0, channel = 0):
	if PLAYING_OFFLINE or STEAM_LOBBY_ID <= 0: return 
	
	var SEND_TYPE: int = type
	var CHANNEL: int = channel
	var PACKET_DATA: PoolByteArray = []
	
	PACKET_DATA.append_array(var2bytes(packet_data).compress(COMPRESSION_TYPE))
	
	if target == "all":
		for MEMBER in LOBBY_MEMBERS:
			Steam.sendP2PPacket(MEMBER["steam_id"], PACKET_DATA, SEND_TYPE, CHANNEL)
	elif target == "peers":
		if LOBBY_MEMBERS.size() > 1:
			for MEMBER in LOBBY_MEMBERS:
				if MEMBER["steam_id"] != STEAM_ID and not FORCE_DISCONNECT_PLAYERS.has(MEMBER["steam_id"]):
					Steam.sendP2PPacket(MEMBER["steam_id"], PACKET_DATA, SEND_TYPE, CHANNEL)
	else :
		Steam.sendP2PPacket(int(target), PACKET_DATA, SEND_TYPE, CHANNEL)

func _read_P2P_Packet(channel = 0):
	if PLAYING_OFFLINE or STEAM_LOBBY_ID <= 0: return 
	
	var PACKET_SIZE: int = Steam.getAvailableP2PPacketSize(channel)
	
	if PACKET_SIZE > 0:
		var PACKET: Dictionary = Steam.readP2PPacket(PACKET_SIZE, channel)
		var PACKET_SENDER: int = PACKET["steam_id_remote"]
		
		if not PACKET_TIMEOUTS.empty() and PACKET_TIMEOUTS.has(PACKET_SENDER):
			print("Packet Disregarded! User is in timeout babyjail!")
			return 
		
		if FORCE_DISCONNECT_PLAYERS.has(PACKET_SENDER):
			print("Packet Disregarded! User is in SUPER babyjail!")
			return 
		
		if PACKET.empty(): print("Error! Empty Packet!")
		
		var DATA: Dictionary = bytes2var(PACKET.data.decompress_dynamic( - 1, COMPRESSION_TYPE))
		var type: String = DATA["type"]
		
		var from_host = Steam.getLobbyOwner(STEAM_LOBBY_ID) == PACKET_SENDER
		
		if not FLUSH_PACKET_INFORMATION.keys().has(PACKET_SENDER):
			FLUSH_PACKET_INFORMATION[PACKET_SENDER] = 1
		FLUSH_PACKET_INFORMATION[PACKET_SENDER] += 1
		
		
		
		
		match type:
			
			"handshake":
				print("Handshake Recieved! :3 P2P Connection has been proc'd")
			
			
			"server_close":
				if not from_host: return 
				PopupMessage._show_popup("Host left the game.")
				Globals._exit_game()
			
			
			"kick":
				if Steam.getLobbyOwner(STEAM_LOBBY_ID) == STEAM_ID and PACKET_SENDER != STEAM_ID:
					print("Player attempted to kick host. Kicking them.")
					_kick_player(PACKET_SENDER)
					return 
				if not from_host: return 
				
				PopupMessage._show_popup("You were kicked from the game.")
				if not DebugScreen.ban_evasion: Globals._exit_game()
			"ban":
				if Steam.getLobbyOwner(STEAM_LOBBY_ID) == STEAM_ID and PACKET_SENDER != STEAM_ID:
					print("Freak Player attempted to kick host. Kicking them.")
					_kick_player(PACKET_SENDER)
					return 
				if not from_host: return 
				
				PopupMessage._show_popup("You were banned from this lobby.")
				if not DebugScreen.ban_evasion: Globals._exit_game()
			"force_disconnect_player":
				if not from_host: return 
				if not _validate_packet_information(DATA, ["user_id"], [TYPE_STRING]): return 
				_force_close_id(int(DATA["user_id"]))
			
			"request_actors":
				if not _validate_packet_information(DATA, ["user_id"], [TYPE_STRING]): return 
				_create_replication_data(int(DATA["user_id"]))
			"actor_request_send":
				if not _validate_packet_information(DATA, ["list"], [TYPE_ARRAY]): return 
				_replicate_actors(DATA["list"], int(PACKET_SENDER))
			
			"instance_actor":
				if not _validate_packet_information(DATA, ["params"], [TYPE_DICTIONARY]): return 
				
				
				var amt = 0
				for actor in get_tree().get_nodes_in_group("actor"):
					if actor.owner_id == PACKET_SENDER: amt += 1
				
				if amt > MAX_OWNED_ACTOR_LIMIT:
					print("Actor disregarded, too many actors owned under ID")
					return 
				
				DATA["params"]["owner_id"] = PACKET_SENDER
				emit_signal("_instance_actor", DATA["params"], PACKET_SENDER)
			
			
			"actor_update":
				if not _validate_packet_information(DATA, ["actor_id", "pos", "rot"], [TYPE_INT, TYPE_VECTOR3, TYPE_VECTOR3]): return 
				ACTOR_DATA[DATA["actor_id"]] = {"pos": DATA["pos"], "rot": DATA["rot"]}
			"actor_animation_update":
				if not _validate_packet_information(DATA, ["actor_id", "data"], [TYPE_INT, TYPE_ARRAY]): return 
				ACTOR_ANIMATION_DATA[DATA["actor_id"]] = DATA["data"]
			"actor_action":
				if not _validate_packet_information(DATA, ["actor_id", "action", "params"], [TYPE_INT, TYPE_STRING, TYPE_ARRAY]): return 
				if PACKET_SENDER == STEAM_ID: return 
				
				if not ACTOR_ACTIONS.keys().has(DATA["actor_id"]):
					ACTOR_ACTIONS[DATA["actor_id"]] = []
				if ACTOR_ACTIONS[DATA["actor_id"]].size() > 128:
					print(DATA["actor_id"], " Too many actor actions queued. Disregarding.")
					print("Packet Dump: ", ACTOR_ACTIONS[DATA["actor_id"]])
					return 
				ACTOR_ACTIONS[DATA["actor_id"]].append([DATA["action"], DATA["params"], PACKET_SENDER])
			
			"message":
				if PlayerData.players_muted.has(PACKET_SENDER) or PlayerData.players_hidden.has(PACKET_SENDER): return 
				
				if not _validate_packet_information(DATA, ["message", "color", "local", "position", "zone", "zone_owner"], [TYPE_STRING, TYPE_STRING, TYPE_BOOL, TYPE_VECTOR3, TYPE_STRING, TYPE_INT]): return 
				
				if not _message_cap(PACKET_SENDER): return 
				
				var user_id: int = PACKET_SENDER
				var user_color: String = DATA["color"].left(12).replace("[", "")
				var user_message: String = DATA["message"]
				
				if not DATA["local"]:
					_recieve_safe_message(user_id, user_color, user_message, false)
				else :
					var dist = DATA["position"].distance_to(MESSAGE_ORIGIN)
					if DATA["zone"] == MESSAGE_ZONE and DATA["zone_owner"] == PlayerData.player_saved_zone_owner:
						if dist < 25.0: _recieve_safe_message(user_id, user_color, user_message, true)
			
			"letter_recieved":
				if PlayerData.players_muted.has(PACKET_SENDER) or PlayerData.players_hidden.has(PACKET_SENDER): return 
				
				if str(STEAM_ID) == DATA["to"]:
					if not _validate_packet_information(DATA["data"], ["letter_id", "header", "closing", "body", "items", "to", "from"], [TYPE_INT, TYPE_STRING, TYPE_STRING, TYPE_STRING, TYPE_ARRAY, TYPE_STRING, TYPE_STRING]): return 
					PlayerData._recieved_letter(DATA["data"])
			"letter_was_accepted":
				PlayerData._letter_was_accepted()
			"letter_was_denied":
				PlayerData._letter_was_denied()
			
			"chalk_packet":
				if PlayerData.players_muted.has(PACKET_SENDER) or PlayerData.players_hidden.has(PACKET_SENDER): return 
				if not _validate_packet_information(DATA, ["data", "canvas_id"], [TYPE_ARRAY, TYPE_INT]): return 
				
				PlayerData.emit_signal("_chalk_recieve", DATA["data"], DATA["canvas_id"])
			"new_player_join":
				emit_signal("_new_player_join", PACKET_SENDER)
				emit_signal("_new_player_join_empty")
			
			"player_punch":
				if not _validate_packet_information(DATA, ["from_pos", "punch_type"], [TYPE_VECTOR3, TYPE_INT]): return 
				
				if PlayerData.players_hidden.has(PACKET_SENDER): return 
				PlayerData.emit_signal("_punched", DATA["from_pos"], DATA["punch_type"])
			
			"request_ping":
				_send_P2P_Packet({"type": "send_ping", "time": str(Time.get_unix_time_from_system()), "from": str(STEAM_ID)}, str(DATA["sender"]), 0, Network.CHANNELS.GAME_STATE)
			"send_ping":
				if not _validate_packet_information(DATA, ["time", "from"], [TYPE_STRING, TYPE_STRING]): return 
				
				for member in LOBBY_MEMBERS:
					if member["steam_id"] == int(DATA["from"]):
						var ping = abs(Time.get_unix_time_from_system() - int(DATA["time"])) * 10
						PING_DICTIONARY[member["steam_id"]] = floor(ping)
						break



func _validate_packet_information(data: Dictionary, information_keys: Array, information_types: Array):
	var valid = true
	
	var index = 0
	for key in information_keys:
		if data.keys().has(key):
			if typeof(data[key]) != information_types[index]:
				valid = false
				break
		else :
			valid = false
			break
		index += 1
	
	if not valid:
		print(data)
		print("Packet is invalid.")
	
	return valid





func _packet_flush():
	PACKET_TIMEOUTS.clear()
	for key in FLUSH_PACKET_INFORMATION.keys():
		if FLUSH_PACKET_INFORMATION[key] >= MAX_PACKET_TIMEOUT_LIMIT:
			PACKET_TIMEOUTS.append(key)
		if FLUSH_PACKET_INFORMATION[key] >= MAX_MAJOR_PACKET_TIMEOUT_LIMIT:
			if GAME_MASTER and Steam.getLobbyOwner(STEAM_LOBBY_ID) == STEAM_ID:
				PlayerData._send_notification("player sending too far many packets, kicking them.")
				_kick_player(int(key))
			else :
				PlayerData._send_notification("player sending too far many packets, blocking them.")
				_force_close_id(int(key))
		FLUSH_PACKET_INFORMATION[key] = 0

func _message_flush():
	for key in MESSAGE_COUNT_TRACKER.keys():
		MESSAGE_COUNT_TRACKER[key] -= 1
		if MESSAGE_COUNT_TRACKER[key] <= 0:
			MESSAGE_COUNT_TRACKER.erase(key)

func _message_cap(id):
	if not MESSAGE_COUNT_TRACKER.keys().has(id):
		MESSAGE_COUNT_TRACKER[id] = 0
	if MESSAGE_COUNT_TRACKER[id] > 10: return false
	MESSAGE_COUNT_TRACKER[id] += 1
	
	return true
