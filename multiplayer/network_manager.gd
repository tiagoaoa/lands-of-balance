extends Node

## UDP Multiplayer Network Manager
## Handles communication with the game server

signal connected_to_server
signal disconnected_from_server
signal player_joined(player_id: int, player_data: Dictionary)
signal player_left(player_id: int)
signal world_state_received(players: Array)
signal entity_state_received(entities: Array)
signal arrow_spawned(arrow_data: Dictionary)
signal arrow_hit(arrow_id: int, hit_pos: Vector3, hit_entity_id: int)

const DEFAULT_SERVER_IP = "65.109.48.183"  # scherbius.vitorpy.com
const DEFAULT_SERVER_PORT = 7777

# Packet types (must match server)
const PKT_JOIN = 1
const PKT_LEAVE = 2
const PKT_UPDATE = 3
const PKT_WORLD_STATE = 4
const PKT_PING = 5
const PKT_PONG = 6
const PKT_ENTITY_STATE = 7      # Server broadcasts entity states
const PKT_ENTITY_DAMAGE = 8     # Client reports damage to entity
const PKT_ARROW_SPAWN = 9       # Client spawns arrow
const PKT_ARROW_HIT = 10        # Arrow hit event

# Entity types
const ENTITY_BOBBA = 0
const ENTITY_DRAGON = 1
const ENTITY_ARROW = 2

# Entity states (Bobba)
const BOBBA_ROAMING = 0
const BOBBA_CHASING = 1
const BOBBA_ATTACKING = 2
const BOBBA_IDLE = 3
const BOBBA_STUNNED = 4

# Entity states (Dragon)
const DRAGON_PATROL = 0
const DRAGON_FLYING_TO_LAND = 1
const DRAGON_LANDING = 2
const DRAGON_WAIT = 3
const DRAGON_TAKING_OFF = 4
const DRAGON_ATTACKING = 5

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

# Entity synchronization
var is_host: bool = false  # First player to join becomes host, controls entities
var tracked_entities: Dictionary = {}  # entity_id -> {type, node, last_state}
var network_arrows: Dictionary = {}  # arrow_id -> Arrow node
var _next_arrow_id: int = 1
var _entity_update_timer: float = 0.0
const ENTITY_UPDATE_INTERVAL: float = 0.0167  # 60 entity updates per second (1/60)

var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.0167  # 60 updates per second (1/60)

# Logging
var _log_file: FileAccess
var _log_timer: float = 0.0
const LOG_INTERVAL: float = 0.5  # Log every 0.5 seconds
const STATE_NAMES = ["IDLE", "WALKING", "RUNNING", "ATTACKING", "BLOCKING", "JUMPING"]


func _ready() -> void:
	# Generate random player name
	player_name = "Player_%d" % (randi() % 10000)
	print("NetworkManager: Ready, player name: ", player_name)

	# Open log file
	var log_path = "user://multiplayer_%s.log" % player_name
	_log_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _log_file:
		_log("=== Multiplayer Log Started for %s ===" % player_name)
		print("NetworkManager: Logging to %s" % ProjectSettings.globalize_path(log_path))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _log_file:
			_log("=== Game closing ===")
			_log_file.close()
			_log_file = null


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

	# Send entity updates (host only)
	if is_host:
		_entity_update_timer += delta
		if _entity_update_timer >= ENTITY_UPDATE_INTERVAL:
			_entity_update_timer = 0.0
			_send_entity_updates()

	# Periodic logging
	_log_timer += delta
	if _log_timer >= LOG_INTERVAL:
		_log_timer = 0.0
		_log_positions()


func _log(message: String) -> void:
	if _log_file:
		var timestamp = Time.get_ticks_msec() / 1000.0
		_log_file.store_line("[%.3f] %s" % [timestamp, message])
		_log_file.flush()


func _get_state_name(state: int) -> String:
	if state >= 0 and state < STATE_NAMES.size():
		return STATE_NAMES[state]
	return "UNKNOWN(%d)" % state


func _log_positions() -> void:
	if my_player_id == 0:
		return

	# Log local player
	if local_player:
		var state = STATE_IDLE
		if local_player.has_method("get_network_state"):
			state = local_player.get_network_state()
		var pos = local_player.global_position
		_log("LOCAL  [ID:%d] pos=(%.2f, %.2f, %.2f) state=%s" % [
			my_player_id, pos.x, pos.y, pos.z, _get_state_name(state)
		])

	# Log remote players
	for player_id in remote_players.keys():
		var remote = remote_players[player_id]
		if is_instance_valid(remote):
			var pos = remote.global_position
			var state = remote.current_state if "current_state" in remote else 0
			_log("REMOTE [ID:%d] pos=(%.2f, %.2f, %.2f) state=%s" % [
				player_id, pos.x, pos.y, pos.z, _get_state_name(state)
			])


func connect_to_server(ip: String = "", port: int = 0) -> bool:
	print("NetworkManager: connect_to_server called")
	if ip.is_empty():
		ip = server_ip
	if port == 0:
		port = server_port

	server_ip = ip
	server_port = port

	print("NetworkManager: Creating UDP socket to %s:%d" % [ip, port])
	socket = PacketPeerUDP.new()
	var err = socket.connect_to_host(ip, port)

	if err != OK:
		print("NetworkManager: Failed to connect to %s:%d - Error: %d" % [ip, port, err])
		return false

	print("NetworkManager: Socket connected to %s:%d" % [ip, port])

	# Send join packet
	_send_join()
	is_connected = true
	connected_to_server.emit()

	return true


func disconnect_from_server() -> void:
	if not is_connected:
		return

	_log("=== Disconnecting from server ===")
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

	# Close log file
	if _log_file:
		_log_file.close()
		_log_file = null

	disconnected_from_server.emit()
	print("NetworkManager: Disconnected from server")


func set_local_player(player: Node3D) -> void:
	local_player = player


func _send_join() -> void:
	print("NetworkManager: _send_join called")
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

	var err = socket.put_packet(buffer)
	print("NetworkManager: Sent join packet (%d bytes), result: %d" % [buffer.size(), err])


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
	# Header (9) + PlayerData: player_id(4) + pos(12) + rot(4) + state(1) + combat(1) + health(4) + anim(32) = 58
	buffer.resize(9 + 58)

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
	# Get actual model facing direction, not CharacterBody3D rotation
	var facing_rot: float = 0.0
	if local_player.has_method("get_facing_rotation"):
		facing_rot = local_player.get_facing_rotation()
	else:
		facing_rot = local_player.rotation.y
	buffer.encode_float(offset, facing_rot)
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
	var combat_mode_val = 1  # Armed by default
	if "combat_mode" in local_player:
		combat_mode_val = local_player.combat_mode
	buffer.encode_u8(offset, combat_mode_val)
	offset += 1

	# Health
	var health = 100.0
	if "health" in local_player:
		health = local_player.health
	buffer.encode_float(offset, health)
	offset += 4

	# Animation name (32 bytes, null-padded)
	var anim_name = "Idle"
	if local_player.has_method("get_current_animation"):
		anim_name = local_player.get_current_animation()
	elif "_current_anim" in local_player:
		anim_name = str(local_player._current_anim)
	var anim_bytes = anim_name.to_utf8_buffer()
	for i in range(min(anim_bytes.size(), 31)):
		buffer.encode_u8(offset + i, anim_bytes[i])

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
			PKT_ENTITY_STATE:
				_handle_entity_state(packet)
			PKT_ARROW_SPAWN:
				_handle_arrow_spawn(packet)
			PKT_ARROW_HIT:
				_handle_arrow_hit(packet)
			PKT_PONG:
				pass  # Could calculate latency here


func _handle_world_state(packet: PackedByteArray) -> void:
	if packet.size() < 10:
		return

	var player_count = packet.decode_u8(9)
	var offset = 10
	# PlayerData: player_id(4) + pos(12) + rot(4) + state(1) + combat(1) + health(4) + anim(32) = 58 bytes
	var player_data_size = 58

	# Debug: Log packet details on first receive or when player count changes
	_log("PACKET: size=%d player_count=%d expected_data=%d" % [
		packet.size(), player_count, 10 + player_count * player_data_size
	])

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

		# Read animation name (32 bytes starting at offset + 26)
		var anim_bytes = packet.slice(offset + 26, offset + 26 + 32)
		var anim_name = ""
		for b in anim_bytes:
			if b == 0:
				break
			anim_name += char(b)
		if anim_name.is_empty():
			anim_name = "Idle"

		offset += player_data_size
		received_ids.append(player_id)

		var data = {
			"player_id": player_id,
			"position": Vector3(pos_x, pos_y, pos_z),
			"rotation_y": rot_y,
			"state": state,
			"combat_mode": combat_mode,
			"health": health,
			"anim_name": anim_name
		}
		players_array.append(data)

		# Debug: Log each player's raw parsed data
		_log("PARSED [%d]: id=%d pos=(%.2f,%.2f,%.2f) rot=%.2f state=%d combat=%d hp=%.1f anim='%s'" % [
			i, player_id, pos_x, pos_y, pos_z, rot_y, state, combat_mode, health, anim_name
		])

		# First time seeing this ID? It's us!
		if my_player_id == 0 and i == player_count - 1:
			my_player_id = player_id
			print("NetworkManager: Assigned player ID: %d" % my_player_id)

			# Determine if we're the host (first player = lowest ID or only player)
			# The host is authoritative for entity state
			if player_count == 1:
				is_host = true
				print("NetworkManager: We are the HOST (first player)")
				_log("HOST: We are the host - authoritative for entities")
			else:
				# Find the lowest player ID - they are the host
				var lowest_id = player_id
				for p in players_array:
					if p["player_id"] < lowest_id:
						lowest_id = p["player_id"]
				is_host = (player_id == lowest_id)
				if is_host:
					print("NetworkManager: We are the HOST (lowest ID)")
					_log("HOST: We are the host - authoritative for entities")
				else:
					print("NetworkManager: We are a CLIENT (host is ID:%d)" % lowest_id)
					_log("CLIENT: Host is ID:%d" % lowest_id)

			# Don't overwrite local player position - keep the scene's spawn point
			# The server doesn't know our initial position until we send updates
			if local_player:
				var current_pos = local_player.global_position
				print("NetworkManager: Keeping local spawn at (%.1f, %.1f, %.1f)" % [current_pos.x, current_pos.y, current_pos.z])
				print("NetworkManager: Server suggested (%.1f, %.1f, %.1f) - ignored" % [pos_x, pos_y, pos_z])

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

	var pos = data.get("position", Vector3.ZERO)
	var state = data.get("state", 0)
	_log("JOINED [ID:%d] pos=(%.2f, %.2f, %.2f) state=%s" % [
		player_id, pos.x, pos.y, pos.z, _get_state_name(state)
	])
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


# ============================================================================
# ENTITY SYNCHRONIZATION
# ============================================================================

## Register an entity for network synchronization (call from Bobba/Dragon _ready)
func register_entity(entity: Node3D, entity_type: int, entity_id: int) -> void:
	tracked_entities[entity_id] = {
		"type": entity_type,
		"node": entity,
		"id": entity_id
	}
	_log("ENTITY REGISTERED: type=%d id=%d" % [entity_type, entity_id])
	print("NetworkManager: Registered entity type=%d id=%d" % [entity_type, entity_id])


## Unregister an entity (call when entity is destroyed)
func unregister_entity(entity_id: int) -> void:
	if entity_id in tracked_entities:
		tracked_entities.erase(entity_id)
		_log("ENTITY UNREGISTERED: id=%d" % entity_id)


## Send entity state updates to server (host only)
func _send_entity_updates() -> void:
	if tracked_entities.is_empty():
		return

	# EntityData: type(1) + id(4) + pos(12) + rot(4) + state(1) + health(4) + extra(8) = 34 bytes
	const ENTITY_DATA_SIZE = 34
	var entity_count = tracked_entities.size()
	var buffer = PackedByteArray()
	buffer.resize(10 + entity_count * ENTITY_DATA_SIZE)

	# Header
	buffer.encode_u8(0, PKT_ENTITY_STATE)
	buffer.encode_u32(1, my_player_id)
	buffer.encode_u32(5, sequence)
	sequence += 1
	buffer.encode_u8(9, entity_count)

	var offset = 10
	for entity_id in tracked_entities:
		var entity_data = tracked_entities[entity_id]
		var node = entity_data["node"]
		if not is_instance_valid(node):
			continue

		buffer.encode_u8(offset, entity_data["type"])
		offset += 1
		buffer.encode_u32(offset, entity_id)
		offset += 4
		buffer.encode_float(offset, node.global_position.x)
		offset += 4
		buffer.encode_float(offset, node.global_position.y)
		offset += 4
		buffer.encode_float(offset, node.global_position.z)
		offset += 4
		buffer.encode_float(offset, node.rotation.y)
		offset += 4

		# Get state and health from entity
		var state = 0
		var health = 100.0
		if node.has_method("get_network_state"):
			state = node.get_network_state()
		elif "state" in node:
			state = node.state
		if "health" in node:
			health = node.health

		buffer.encode_u8(offset, state)
		offset += 1
		buffer.encode_float(offset, health)
		offset += 4

		# Extra data (8 bytes) - entity-specific
		# For Dragon: lap_count (4) + patrol_angle (4)
		# For Bobba: target_player_id (4) + padding (4)
		if entity_data["type"] == ENTITY_DRAGON and "lap_count" in node:
			buffer.encode_u32(offset, node.lap_count)
			buffer.encode_float(offset + 4, node.patrol_angle if "patrol_angle" in node else 0.0)
		else:
			buffer.encode_u32(offset, 0)
			buffer.encode_u32(offset + 4, 0)
		offset += 8

	socket.put_packet(buffer)


## Handle entity state from server (non-host clients)
func _handle_entity_state(packet: PackedByteArray) -> void:
	if packet.size() < 10:
		return

	# Host doesn't need to receive entity state - it's authoritative
	if is_host:
		return

	var entity_count = packet.decode_u8(9)
	var offset = 10
	const ENTITY_DATA_SIZE = 34

	var entities_array: Array = []

	for i in range(entity_count):
		if offset + ENTITY_DATA_SIZE > packet.size():
			break

		var entity_type = packet.decode_u8(offset)
		var entity_id = packet.decode_u32(offset + 1)
		var pos_x = packet.decode_float(offset + 5)
		var pos_y = packet.decode_float(offset + 9)
		var pos_z = packet.decode_float(offset + 13)
		var rot_y = packet.decode_float(offset + 17)
		var state = packet.decode_u8(offset + 21)
		var health = packet.decode_float(offset + 22)
		var extra1 = packet.decode_u32(offset + 26)
		var extra2 = packet.decode_float(offset + 30)

		offset += ENTITY_DATA_SIZE

		var data = {
			"entity_id": entity_id,
			"entity_type": entity_type,
			"position": Vector3(pos_x, pos_y, pos_z),
			"rotation_y": rot_y,
			"state": state,
			"health": health,
			"extra1": extra1,
			"extra2": extra2
		}
		entities_array.append(data)

		# Update local entity if it exists
		if entity_id in tracked_entities:
			var entity_data = tracked_entities[entity_id]
			var node = entity_data["node"]
			if is_instance_valid(node) and node.has_method("apply_network_state"):
				node.apply_network_state(data)

	entity_state_received.emit(entities_array)


## Send arrow spawn event to server
func send_arrow_spawn(spawn_pos: Vector3, direction: Vector3, shooter_id: int) -> int:
	var arrow_id = _next_arrow_id
	_next_arrow_id += 1

	var buffer = PackedByteArray()
	buffer.resize(9 + 4 + 12 + 12 + 4)  # Header + arrow_id + pos + dir + shooter_id = 41 bytes

	buffer.encode_u8(0, PKT_ARROW_SPAWN)
	buffer.encode_u32(1, my_player_id)
	buffer.encode_u32(5, sequence)
	sequence += 1

	var offset = 9
	buffer.encode_u32(offset, arrow_id)
	offset += 4
	buffer.encode_float(offset, spawn_pos.x)
	offset += 4
	buffer.encode_float(offset, spawn_pos.y)
	offset += 4
	buffer.encode_float(offset, spawn_pos.z)
	offset += 4
	buffer.encode_float(offset, direction.x)
	offset += 4
	buffer.encode_float(offset, direction.y)
	offset += 4
	buffer.encode_float(offset, direction.z)
	offset += 4
	buffer.encode_u32(offset, shooter_id)

	socket.put_packet(buffer)
	_log("ARROW SPAWN: id=%d pos=(%.2f,%.2f,%.2f)" % [arrow_id, spawn_pos.x, spawn_pos.y, spawn_pos.z])

	return arrow_id


## Handle arrow spawn from another player
func _handle_arrow_spawn(packet: PackedByteArray) -> void:
	if packet.size() < 41:
		return

	var sender_id = packet.decode_u32(1)
	if sender_id == my_player_id:
		return  # Ignore our own arrows

	var offset = 9
	var arrow_id = packet.decode_u32(offset)
	var pos_x = packet.decode_float(offset + 4)
	var pos_y = packet.decode_float(offset + 8)
	var pos_z = packet.decode_float(offset + 12)
	var dir_x = packet.decode_float(offset + 16)
	var dir_y = packet.decode_float(offset + 20)
	var dir_z = packet.decode_float(offset + 24)
	var shooter_id = packet.decode_u32(offset + 28)

	var data = {
		"arrow_id": arrow_id,
		"position": Vector3(pos_x, pos_y, pos_z),
		"direction": Vector3(dir_x, dir_y, dir_z),
		"shooter_id": shooter_id
	}

	_log("ARROW RECEIVED: id=%d pos=(%.2f,%.2f,%.2f)" % [arrow_id, pos_x, pos_y, pos_z])
	arrow_spawned.emit(data)


## Send arrow hit event to server
func send_arrow_hit(arrow_id: int, hit_pos: Vector3, hit_entity_id: int) -> void:
	var buffer = PackedByteArray()
	buffer.resize(9 + 4 + 12 + 4)  # Header + arrow_id + pos + entity_id = 29 bytes

	buffer.encode_u8(0, PKT_ARROW_HIT)
	buffer.encode_u32(1, my_player_id)
	buffer.encode_u32(5, sequence)
	sequence += 1

	var offset = 9
	buffer.encode_u32(offset, arrow_id)
	offset += 4
	buffer.encode_float(offset, hit_pos.x)
	offset += 4
	buffer.encode_float(offset, hit_pos.y)
	offset += 4
	buffer.encode_float(offset, hit_pos.z)
	offset += 4
	buffer.encode_u32(offset, hit_entity_id)

	socket.put_packet(buffer)
	_log("ARROW HIT: id=%d entity=%d" % [arrow_id, hit_entity_id])


## Handle arrow hit event from server
func _handle_arrow_hit(packet: PackedByteArray) -> void:
	if packet.size() < 29:
		return

	var offset = 9
	var arrow_id = packet.decode_u32(offset)
	var hit_x = packet.decode_float(offset + 4)
	var hit_y = packet.decode_float(offset + 8)
	var hit_z = packet.decode_float(offset + 12)
	var hit_entity_id = packet.decode_u32(offset + 16)

	arrow_hit.emit(arrow_id, Vector3(hit_x, hit_y, hit_z), hit_entity_id)


## Send damage event to server (any client can report damage)
func send_entity_damage(entity_id: int, damage: float, attacker_id: int) -> void:
	var buffer = PackedByteArray()
	buffer.resize(9 + 4 + 4 + 4)  # Header + entity_id + damage + attacker_id = 21 bytes

	buffer.encode_u8(0, PKT_ENTITY_DAMAGE)
	buffer.encode_u32(1, my_player_id)
	buffer.encode_u32(5, sequence)
	sequence += 1

	var offset = 9
	buffer.encode_u32(offset, entity_id)
	offset += 4
	buffer.encode_float(offset, damage)
	offset += 4
	buffer.encode_u32(offset, attacker_id)

	socket.put_packet(buffer)
	_log("ENTITY DAMAGE: entity=%d damage=%.1f attacker=%d" % [entity_id, damage, attacker_id])
