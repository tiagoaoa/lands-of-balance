extends Node
class_name NetworkManager

## UDP Multiplayer Network Manager
## Handles communication with the game server

signal connected_to_server
signal disconnected_from_server
signal player_joined(player_id: int, player_data: Dictionary)
signal player_left(player_id: int)
signal world_state_received(players: Array)

const DEFAULT_SERVER_IP = "scherbius.vitorpy.com"
const DEFAULT_SERVER_PORT = 7777

# Packet types (must match server)
const PKT_JOIN = 1
const PKT_LEAVE = 2
const PKT_UPDATE = 3
const PKT_WORLD_STATE = 4
const PKT_PING = 5
const PKT_PONG = 6

# Player states
const STATE_IDLE = 0
const STATE_WALKING = 1
const STATE_RUNNING = 2
const STATE_ATTACKING = 3
const STATE_BLOCKING = 4
const STATE_JUMPING = 5

var socket: PacketPeerUDP
var server_ip: String = DEFAULT_SERVER_IP
var server_port: int = DEFAULT_SERVER_PORT
var is_connected: bool = false
var my_player_id: int = 0
var player_name: String = "Player"
var sequence: int = 0

var remote_players: Dictionary = {}  # player_id -> RemotePlayer node
var local_player: Node3D = null

var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.05  # 20 updates per second


func _ready() -> void:
	# Generate random player name
	player_name = "Player_%d" % (randi() % 10000)


func _process(delta: float) -> void:
	if not is_connected:
		return

	# Receive packets
	_receive_packets()

	# Send position updates
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_send_update()


func connect_to_server(ip: String = "", port: int = 0) -> bool:
	if ip.is_empty():
		ip = server_ip
	if port == 0:
		port = server_port

	server_ip = ip
	server_port = port

	socket = PacketPeerUDP.new()
	var err = socket.connect_to_host(ip, port)

	if err != OK:
		print("NetworkManager: Failed to connect to %s:%d - Error: %d" % [ip, port, err])
		return false

	print("NetworkManager: Connecting to %s:%d" % [ip, port])

	# Send join packet
	_send_join()
	is_connected = true
	connected_to_server.emit()

	return true


func disconnect_from_server() -> void:
	if not is_connected:
		return

	_send_leave()
	socket.close()
	is_connected = false
	my_player_id = 0

	# Clear remote players
	for player_id in remote_players.keys():
		var remote = remote_players[player_id]
		if is_instance_valid(remote):
			remote.queue_free()
	remote_players.clear()

	disconnected_from_server.emit()
	print("NetworkManager: Disconnected from server")


func set_local_player(player: Node3D) -> void:
	local_player = player


func _send_join() -> void:
	var buffer = PackedByteArray()
	buffer.resize(41)  # 1 + 4 + 4 + 32 = 41 bytes

	buffer.encode_u8(0, PKT_JOIN)
	buffer.encode_u32(1, 0)  # player_id (0 for new player)
	buffer.encode_u32(5, sequence)
	sequence += 1

	# Encode player name (32 bytes, null-padded)
	var name_bytes = player_name.to_utf8_buffer()
	for i in range(min(name_bytes.size(), 31)):
		buffer.encode_u8(9 + i, name_bytes[i])

	socket.put_packet(buffer)
	print("NetworkManager: Sent join request as '%s'" % player_name)


func _send_leave() -> void:
	var buffer = PackedByteArray()
	buffer.resize(9)

	buffer.encode_u8(0, PKT_LEAVE)
	buffer.encode_u32(1, my_player_id)
	buffer.encode_u32(5, sequence)
	sequence += 1

	socket.put_packet(buffer)


func _send_update() -> void:
	if local_player == null or my_player_id == 0:
		return

	var buffer = PackedByteArray()
	buffer.resize(9 + 30)  # Header + PlayerData

	# Header
	buffer.encode_u8(0, PKT_UPDATE)
	buffer.encode_u32(1, my_player_id)
	buffer.encode_u32(5, sequence)
	sequence += 1

	# PlayerData
	var offset = 9
	buffer.encode_u32(offset, my_player_id)
	offset += 4
	buffer.encode_float(offset, local_player.global_position.x)
	offset += 4
	buffer.encode_float(offset, local_player.global_position.y)
	offset += 4
	buffer.encode_float(offset, local_player.global_position.z)
	offset += 4
	buffer.encode_float(offset, local_player.rotation.y)
	offset += 4

	# State
	var state = STATE_IDLE
	if local_player.has_method("get_network_state"):
		state = local_player.get_network_state()
	elif "is_attacking" in local_player:
		if local_player.is_attacking:
			state = STATE_ATTACKING
		elif local_player.is_blocking:
			state = STATE_BLOCKING
		elif local_player.velocity.length() > 0.5:
			if local_player.is_running:
				state = STATE_RUNNING
			else:
				state = STATE_WALKING
	buffer.encode_u8(offset, state)
	offset += 1

	# Combat mode
	var combat_mode = 1  # Armed by default
	if "combat_mode" in local_player:
		combat_mode = local_player.combat_mode
	buffer.encode_u8(offset, combat_mode)
	offset += 1

	# Health
	var health = 100.0
	if "health" in local_player:
		health = local_player.health
	buffer.encode_float(offset, health)

	socket.put_packet(buffer)


func _receive_packets() -> void:
	while socket.get_available_packet_count() > 0:
		var packet = socket.get_packet()
		if packet.size() < 9:
			continue

		var pkt_type = packet.decode_u8(0)

		match pkt_type:
			PKT_WORLD_STATE:
				_handle_world_state(packet)
			PKT_PONG:
				pass  # Could calculate latency here


func _handle_world_state(packet: PackedByteArray) -> void:
	if packet.size() < 10:
		return

	var player_count = packet.decode_u8(9)
	var offset = 10
	var player_data_size = 30  # Size of PlayerData struct

	var received_ids: Array[int] = []
	var players_array: Array = []

	for i in range(player_count):
		if offset + player_data_size > packet.size():
			break

		var player_id = packet.decode_u32(offset)
		var pos_x = packet.decode_float(offset + 4)
		var pos_y = packet.decode_float(offset + 8)
		var pos_z = packet.decode_float(offset + 12)
		var rot_y = packet.decode_float(offset + 16)
		var state = packet.decode_u8(offset + 20)
		var combat_mode = packet.decode_u8(offset + 21)
		var health = packet.decode_float(offset + 22)

		offset += player_data_size
		received_ids.append(player_id)

		var data = {
			"player_id": player_id,
			"position": Vector3(pos_x, pos_y, pos_z),
			"rotation_y": rot_y,
			"state": state,
			"combat_mode": combat_mode,
			"health": health
		}
		players_array.append(data)

		# First time seeing this ID? It's us!
		if my_player_id == 0 and i == player_count - 1:
			my_player_id = player_id
			print("NetworkManager: Assigned player ID: %d" % my_player_id)

			# Set initial spawn position for local player
			if local_player:
				local_player.global_position = Vector3(pos_x, pos_y, pos_z)
				print("NetworkManager: Spawned at (%.1f, %.1f, %.1f)" % [pos_x, pos_y, pos_z])

		# Update or create remote player (skip ourselves)
		if player_id != my_player_id:
			if player_id in remote_players:
				_update_remote_player(player_id, data)
			else:
				_create_remote_player(player_id, data)

	# Remove players that left
	for existing_id in remote_players.keys():
		if existing_id not in received_ids:
			_remove_remote_player(existing_id)

	world_state_received.emit(players_array)


func _create_remote_player(player_id: int, data: Dictionary) -> void:
	# Load the remote player scene
	var remote_scene = load("res://multiplayer/remote_player.tscn")
	if remote_scene == null:
		print("NetworkManager: Failed to load remote_player.tscn")
		return

	var remote = remote_scene.instantiate()
	remote.player_id = player_id
	remote.name = "RemotePlayer_%d" % player_id

	get_tree().current_scene.add_child(remote)
	remote_players[player_id] = remote

	_update_remote_player(player_id, data)

	print("NetworkManager: Created remote player %d" % player_id)
	player_joined.emit(player_id, data)


func _update_remote_player(player_id: int, data: Dictionary) -> void:
	if player_id not in remote_players:
		return

	var remote = remote_players[player_id]
	if not is_instance_valid(remote):
		return

	remote.update_from_network(data)


func _remove_remote_player(player_id: int) -> void:
	if player_id not in remote_players:
		return

	var remote = remote_players[player_id]
	if is_instance_valid(remote):
		remote.queue_free()

	remote_players.erase(player_id)
	print("NetworkManager: Removed remote player %d" % player_id)
	player_left.emit(player_id)
