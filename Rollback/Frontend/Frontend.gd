extends Control

func _ready():
	pass

func _process(delta):
	pass

func _on_player_1_join_pressed():
	if NetworkManager.create_server():
		MasterScene.request_master_state_switch(MasterScene.LOAD_STAGE);

func _on_player_2_join_pressed():
	if NetworkManager.create_client("127.0.0.1"):
		MasterScene.request_master_state_switch(MasterScene.LOAD_STAGE);
