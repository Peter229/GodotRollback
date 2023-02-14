extends CharacterBody2D

var my_inputs = NetworkManager.Inputs.new();

const RIGHT_FLAG 	= 0b00000001;
const LEFT_FLAG 	= 0b00000010;
const CROUCH_FLAG	= 0b00010000;
const ATTACK_FLAG 	= 0b00100000;
const JUMP_FLAG 	= 0b01000000;

var max_speed = 60;
var acceleration_speed = 10;
var friction = 5;
var i_velocity = Vector2i(0, 0);
var i_position = Vector2i(0, 0);

var grounded = false;
var hitstun = 0;

var previous_inputs = [];
var previous_states = [];

func _ready():
	previous_inputs.resize(NetworkManager.MAX_INPUT_BUFFER);
	previous_states.resize(NetworkManager.MAX_INPUT_BUFFER);
	var dummy_input = NetworkManager.Inputs.new();
	dummy_input.input = 0;
	dummy_input.tick = 0;
	dummy_input.type = NetworkManager.INPUTS_TYPE;
	for i in range(NetworkManager.MAX_INPUT_BUFFER):
		previous_inputs[i] = NetworkManager.dupe_inputs(dummy_input);
	my_inputs.type = NetworkManager.INPUTS_TYPE;

func _process(delta):
	if Input.is_action_pressed("move_right"):
		my_inputs.input |= RIGHT_FLAG;
	
	if Input.is_action_pressed("move_left"):
		my_inputs.input |= LEFT_FLAG;
	
	if Input.is_action_pressed("jump"):
		my_inputs.input |= JUMP_FLAG;
	
	if Input.is_action_pressed("light_attack"):
		my_inputs.input |= ATTACK_FLAG;

func p_store_input():
	var tick = NetworkManager.current_tick + NetworkManager.DELAY;
	my_inputs.tick = tick;
	previous_inputs[tick % NetworkManager.MAX_INPUT_BUFFER] = NetworkManager.dupe_inputs(my_inputs);
	my_inputs.input = 0;

func tick(tick):
	
	if i_position.y > 10000:
		i_position.x = 0;
		i_position.y = 0;
	
	var inputs = previous_inputs[tick % NetworkManager.MAX_INPUT_BUFFER];
	
	var accel_speed = acceleration_speed;
	if !grounded:
		accel_speed = 5;
	if inputs.input & RIGHT_FLAG:
		i_velocity.x += accel_speed;
	if inputs.input & LEFT_FLAG:
		i_velocity.x -= accel_speed;
	
	var apply_friction = friction;
	if hitstun > 0:
		apply_friction = 1;
	elif !grounded:
		apply_friction = 2;
	
	var sign = signi(i_velocity.x)
	i_velocity.x -= sign * apply_friction;
	if signi(i_velocity.x) != sign:
		i_velocity.x = 0;
	
	if absi(i_velocity.x) > max_speed && hitstun == 0:
		i_velocity.x = signi(i_velocity.x) * max_speed;
	
	collision_check(inputs);

func act_on_tick(tick, opponent):
	if opponent.hitstun != 0:
		return;
	var inputs = previous_inputs[tick % NetworkManager.MAX_INPUT_BUFFER];
	if inputs.input & ATTACK_FLAG:
		#print(NetworkManager.is_server, " ", tick, " ", i_position, " ", i_velocity, " op ", opponent.i_position, " ", opponent.i_velocity);
		if absi(opponent.i_position.x - i_position.x) < 400:
			#print(NetworkManager.is_server, " Applying on tick: ", tick);
			opponent.i_velocity += Vector2i(100.0 * signi(opponent.i_position.x - i_position.x), -50.0);
			opponent.hitstun = 50;
			opponent.grounded = false;

func final(tick):
	var inputs = previous_inputs[tick % NetworkManager.MAX_INPUT_BUFFER];
	#Final
	$Label.text = str(i_position);
	$Label.text += "\n" + str(i_velocity);
	$Label.text += "\n" + str(tick);
	
	global_position = i_position;
	previous_states[tick % NetworkManager.MAX_INPUT_BUFFER] = get_state(tick, inputs.tick == tick);

func collision_check(inputs):
	if hitstun == 0:
		check_ground();
	else:
		hitstun -= 1;
	if !grounded:
		i_velocity.y += 1;
	else:
		i_velocity.y = 0;
	
	if inputs.input & JUMP_FLAG && grounded:
		i_velocity.y = -50;
	
	#Optimize these functions	
	horizontal_check();
	vertical_check();

func dda_move():
	var step_size = Vector2(sqrt(1 + (i_velocity.y / i_velocity.x) * (i_velocity.y / i_velocity.x)), sqrt(1 + (i_velocity.x / i_velocity.y) * (i_velocity.x / i_velocity.y)));
	var pos = i_position;
	
	var step = Vector2i(0, 0);
	
	step.x = signi(i_velocity.x);
	step.y = signi(i_velocity.y);
	
	#while true:
		

func horizontal_check():
	var params = PhysicsTestMotionParameters2D.new();
	for i in range(absi(i_velocity.x)):
		var move_dir = 1 * sign(i_velocity.x);
		params.from = Transform2D(0.0, i_position);
		params.motion = Vector2i(move_dir, 0);
		var out = PhysicsTestMotionResult2D.new();
		if PhysicsServer2D.body_test_motion(self, params, out):
			break;
		else:
			i_position.x += move_dir;

func vertical_check():
	var params = PhysicsTestMotionParameters2D.new();
	for i in range(absi(i_velocity.y)):
		var move_dir = 1 * sign(i_velocity.y);
		params.from = Transform2D(0.0, i_position);
		params.motion = Vector2i(0, move_dir);
		var out = PhysicsTestMotionResult2D.new();
		if PhysicsServer2D.body_test_motion(self, params, out):
			break;
		else:
			i_position.y += move_dir;

func check_ground():
	var params = PhysicsTestMotionParameters2D.new();
	params.from = Transform2D(0.0, i_position);
	params.motion = Vector2i(0.0,  1.0);
	var out = PhysicsTestMotionResult2D.new();
	if PhysicsServer2D.body_test_motion(self, params, out):
		grounded = true;
	else:
		grounded = false;

func get_state(tick, verified) -> NetworkManager.Player:
	var player = NetworkManager.Player.new();
	player.type = NetworkManager.PLAYER_TYPE;
	player.tick = tick;
	player.id = int(verified);
	player.x = i_position.x;
	player.y = i_position.y;
	player.vx = i_velocity.x;
	player.vy = i_velocity.y;
	player.grounded = int(grounded);
	player.hitstun = hitstun;
	return player;

func set_state(tick):
	var player = previous_states[tick % NetworkManager.MAX_INPUT_BUFFER];
	i_position.x = player.x;
	i_position.y = player.y;
	i_velocity.x = player.vx;
	i_velocity.y = player.vy;
	grounded = bool(player.grounded);
	hitstun = player.hitstun;
