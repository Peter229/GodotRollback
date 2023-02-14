extends Node

var frontend = preload("res://Frontend/Frontend.tscn");

var stage = preload("res://Stages/Stage.tscn");

enum { FRONTEND, LOAD_STAGE, WAIT_FOR_PLAYERS, FIGHT, OPPONENT_DISCONNECTED }

var current_state = FRONTEND;

var current_node = null;

func _ready():
	request_master_state_switch(FRONTEND);

func _process(delta):
	pass

func request_master_state_switch(desired_state):
	match desired_state:
		FRONTEND:
			get_tree().change_scene_to_file("res://Frontend/Frontend.tscn");
		LOAD_STAGE:
			get_tree().change_scene_to_file("res://Stages/Stage.tscn");
			NetworkManager.reset();
			request_master_state_switch(WAIT_FOR_PLAYERS);
		WAIT_FOR_PLAYERS:
			var t = 1;
		FIGHT:
			var t = 1;
		OPPONENT_DISCONNECTED:
			request_master_state_switch(FRONTEND);
	current_state = desired_state;

func remove_current_node():
	if current_node:
		remove_child(current_node);

func get_current_state():
	return current_state;
