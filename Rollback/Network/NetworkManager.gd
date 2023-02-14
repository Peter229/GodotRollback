extends Node

var is_server = false;
var is_connected = false; 

var time = 0.0;
var server_tick_rate = 0.015;
var current_tick = 0;

var loaded_character = preload("res://Characters/Character.tscn");

const CHANGE_TYPE: int = 0;
const INPUTS_TYPE: int = 1;
const ARRAY_TYPE: int = 2;
const PLAYER_TYPE: int = 3;
const GAME_STATE_TYPE: int = 4;

#Use type to index to get size
const SIZE_TABLE = [32, 32, 16, 72, 8];

class SArray:
	var type: int
	var size: int
	var array: Array

class GameState:
	var type: int
	var players: SArray

class Player:
	var type: int
	var id: int
	var tick: int
	var x: int
	var y: int
	var vx: int
	var vy: int
	var grounded: int
	var hitstun: int

class Change:
	var type: int
	var tick: int
	var change: int
	var id: int 

class Inputs:
	var type: int
	var tick: int
	var input: int
	var tick_delta: int

var sv_active_game_state = GameState.new();

const MAX_INPUT_BUFFER = 32;
const MAX_ROLLBACK_FRAMES = 16;
const DELAY = 0;

var stage = "/root/Stage/";

var opponent_id = 0;

var pause = false;

var latest_confirmed_opponent_tick = 0;

var local_tick_delta = 0;
var opponent_tick_delta = 0;

var syncing = false;

var player_inst = null;
var opponent_inst = null;

func reset():
	latest_confirmed_opponent_tick = 0;
	local_tick_delta = 0;
	opponent_tick_delta = 0;
	syncing = false;
	opponent_id = 0;
	current_tick = 0;
	time = 0.0;
	player_inst = null;
	opponent_inst = null;

func _ready():
	sv_active_game_state.type = GAME_STATE_TYPE;
	sv_active_game_state.players = SArray.new();
	sv_active_game_state.players.type = ARRAY_TYPE;
	multiplayer.peer_connected.connect(self._player_connected);
	multiplayer.connected_to_server.connect(self._connect_to_server);
	multiplayer.peer_disconnected.connect(self._disconnect_from_server);

func _process(delta):
	if MasterScene.get_current_state() == MasterScene.FIGHT:
		if !syncing:
			time += delta;
			while time >= server_tick_rate:
				time -= server_tick_rate;
				tick();
				current_tick += 1;

func tick():
	client_tick();

func client_tick():
	p_send_player_input();
	update_game_state(current_tick);

func update_oppenont(tick):
	var opp_input = opponent_inst.previous_inputs[tick % MAX_INPUT_BUFFER];
	if opp_input.tick == tick:
		opponent_inst.tick(tick);
	else:
		predict(tick);

func predict(tick):
	var last_tick = tick - 1;
	var opp_input = opponent_inst.previous_inputs[last_tick % MAX_INPUT_BUFFER];
	opponent_inst.previous_inputs[tick % MAX_INPUT_BUFFER] = dupe_inputs(opp_input);
	opponent_inst.tick(tick);

func update_game_state(tick):
	player_inst.tick(tick);
	update_oppenont(tick);
	player_inst.act_on_tick(tick, opponent_inst);
	opponent_inst.act_on_tick(tick, player_inst);
	player_inst.final(tick);
	opponent_inst.final(tick);

func p_send_player_input():
	player_inst.p_store_input();
	player_inst.previous_inputs[(current_tick + DELAY) % MAX_INPUT_BUFFER].tick_delta = local_tick_delta;
	rpc_id(opponent_id, "recieve_inputs", serialize_b(player_inst.previous_inputs[(current_tick + DELAY) % MAX_INPUT_BUFFER]));
	if current_tick > 15:
		rpc_id(opponent_id, "recieve_player", serialize_b(player_inst.previous_states[(current_tick - 15) % MAX_INPUT_BUFFER]));

@rpc(any_peer, unreliable)
func recieve_player(in_player):
	var opponent = deserialize_b(in_player);
	var opponent_state = opponent_inst.previous_states[opponent.tick % MAX_INPUT_BUFFER];
	if opponent_state:
		if opponent.tick == opponent_state.tick:
			if opponent_state.id && opponent.id:
				if opponent.x == opponent_state.x && opponent.y == opponent_state.y && opponent.vx == opponent_state.vx && opponent.vy == opponent_state.vy:
					pass
				else:
					print(is_server, " Desync occured");
					print(opponent.x, " ",opponent.y, " ",opponent.vx, " ", opponent.vy);
					print(opponent_state.x, " ",opponent_state.y, " ",opponent_state.vx, " ", opponent_state.vy);
			else:
				pass
				#print(is_server, " ", player_state.id, " ", player.id);
		else:
			print("ERROR: recieve_player");

@rpc(any_peer, reliable)
func recieve_inputs(in_inputs):
	var inputs = deserialize_b(in_inputs);
	handle_sync(inputs);
	if inputs.tick < current_tick - MAX_ROLLBACK_FRAMES:
		print("ERROR: Opponent very far behind");
	
	if inputs.tick <= current_tick:
		check_prediction(opponent_inst, inputs);
	else:
		opponent_inst.previous_inputs[inputs.tick % MAX_INPUT_BUFFER] = inputs;

func handle_sync(inputs):
	if inputs.tick > latest_confirmed_opponent_tick:
		latest_confirmed_opponent_tick = inputs.tick;
		
		#Get opponent local_tick_delta aswell, swap then sync
		local_tick_delta = (current_tick + DELAY) - latest_confirmed_opponent_tick;
		
		opponent_tick_delta = inputs.tick_delta;
		
		var tick_offset: int = (local_tick_delta - opponent_tick_delta) / 2;
		
		if tick_offset >= 1 && !syncing:
			syncing = true;
			print("BEGIN SYNC")
		
		if syncing:
			if tick_offset < 1:
				syncing = false;
				print("END SYNC");

func check_prediction(player, in_inputs):
	if player.previous_inputs[in_inputs.tick % MAX_INPUT_BUFFER].input == in_inputs.input:
		player.previous_inputs[in_inputs.tick % MAX_INPUT_BUFFER] = in_inputs;
	else:
		player.previous_inputs[in_inputs.tick % MAX_INPUT_BUFFER] = in_inputs;
		for i in range(in_inputs.tick + 1, in_inputs.tick + MAX_ROLLBACK_FRAMES):
			if player.previous_inputs[i % MAX_INPUT_BUFFER].tick != i:
				player.previous_inputs[i % MAX_INPUT_BUFFER] = dupe_inputs(in_inputs);
			else:
				break;
		var prev_tick = in_inputs.tick - 1;
		var prev_inp = player.previous_inputs[prev_tick % MAX_INPUT_BUFFER];
		if prev_inp:
			if prev_inp.tick == prev_tick:
				rollback(player, prev_tick);

func rollback(opponent, tick):
	opponent.set_state(tick);
	player_inst.set_state(tick);
	for i in range(tick + 1, current_tick + DELAY):
		update_game_state(i);

func _player_connected(id):
	opponent_id = id;
	spawn_player(id);
	spawn_player(multiplayer.get_unique_id());
	MasterScene.request_master_state_switch(MasterScene.FIGHT);

func _connect_to_server():
	is_connected = true;

func _disconnect_from_server(id):
	
	MasterScene.request_master_state_switch(MasterScene.OPPONENT_DISCONNECTED);
	
func create_server() -> bool:
	var network = ENetMultiplayerPeer.new();
	var error = network.create_server(9999);
	if error != OK:
		printerr("Error: ", error);
		return false;
	multiplayer.multiplayer_peer = network;
	is_server = true;
	is_connected = true;
	return true;

func create_client(server_ip) -> bool:
	var network = ENetMultiplayerPeer.new();
	var error = network.create_client(server_ip, 9999);
	if error != OK:
		printerr("Error: ", error);
		return false;
	multiplayer.multiplayer_peer = network;
	is_server = false;
	return true;

func spawn_player(id):
	var character = loaded_character.instantiate();
	character.set_name(str(id));
	var get_spawn_loc = "PlayerSpawn" + str(int(id != 1));
	character.i_position = Vector2i(get_node(stage).find_child(get_spawn_loc).global_position);
	if id != multiplayer.get_unique_id():
		opponent_inst = character;
	else:
		player_inst = character;
	get_node(stage).add_child(character);

func serialize_b(item) -> PackedByteArray:
	var s_s = PackedByteArray();
	s_s.resize(SIZE_TABLE[item.type]);
	s_s.encode_s64(0, item.type)
	match item.type:
		CHANGE_TYPE:
			s_s.encode_s64(8, item.tick);
			s_s.encode_s64(16, item.change);
			s_s.encode_s64(24, item.id);
		INPUTS_TYPE:
			s_s.encode_s64(8, item.tick);
			s_s.encode_s64(16, item.input);
			s_s.encode_s64(24, item.tick_delta);
		PLAYER_TYPE:
			s_s.encode_s64(8, item.id);
			s_s.encode_s64(16, item.tick);
			s_s.encode_s64(24, item.x);
			s_s.encode_s64(32, item.y);
			s_s.encode_s64(40, item.vx);
			s_s.encode_s64(48, item.vy);
			s_s.encode_s64(56, item.grounded);
			s_s.encode_s64(64, item.hitstun);
		ARRAY_TYPE:
			s_s.encode_s64(8, item.array.size());
			for array_element in item.array:
				s_s.append_array(serialize_b(array_element));
		GAME_STATE_TYPE:
			s_s.append_array(serialize_b(item.players));
	return s_s;

func deserialize_b(item) -> Variant:
	var type = item.decode_s64(0);
	match type:
		CHANGE_TYPE:
			var change = Change.new();
			change.type = CHANGE_TYPE;
			change.tick = item.decode_s64(8);
			change.change = item.decode_s64(16);
			change.id = item.decode_s64(24);
			return change;
		INPUTS_TYPE:
			var inputs = Inputs.new();
			inputs.type = INPUTS_TYPE;
			inputs.tick = item.decode_s64(8);
			inputs.input = item.decode_s64(16);
			inputs.tick_delta = item.decode_s64(24);
			return inputs;
		PLAYER_TYPE:
			var player = Player.new();
			player.type = PLAYER_TYPE;
			player.id = item.decode_s64(8);
			player.tick = item.decode_s64(16);
			player.x = item.decode_s64(24);
			player.y = item.decode_s64(32);
			player.vx = item.decode_s64(40);
			player.vy = item.decode_s64(48);
			player.grounded = item.decode_s64(56);
			player.hitstun = item.decode_s64(64);
			return player;
		ARRAY_TYPE:
			var array = SArray.new();
			array.type = ARRAY_TYPE;
			array.size  = item.decode_s64(8);
			var byte_index = 16;
			for i in range(array.size):
				var item_type = item.decode_s64(byte_index);
				var last_index = byte_index + SIZE_TABLE[item_type];
				var full_item = item.slice(byte_index, last_index);
				byte_index = last_index;
				array.array.append(deserialize_b(full_item));
			return array;
		GAME_STATE_TYPE:
			var game_state = GameState.new();
			game_state.type = GAME_STATE_TYPE;
			var slice_size = item.decode_s64(16) * SIZE_TABLE[PLAYER_TYPE];
			game_state.players = deserialize_b(item.slice(8, 8 + 16 + slice_size));
			return game_state;
	return -1;

func array_to_sarray(array) -> SArray:
	var sarray = SArray.new();
	sarray.type = ARRAY_TYPE;
	sarray.size = array.size();
	sarray.array = array;
	return sarray;

func dupe_inputs(in_inputs) -> Inputs:
	var inputs = Inputs.new();
	inputs.type = in_inputs.type;
	inputs.tick = in_inputs.tick;
	inputs.input = in_inputs.input;
	inputs.tick_delta = in_inputs.tick_delta;
	return inputs;
