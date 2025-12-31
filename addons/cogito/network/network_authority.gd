extends Node
## Network Authority component for determining who controls an object in multiplayer.
## Attach this to any node that needs network authority management.
class_name NetworkAuthority

## Who has authority over this object
enum AuthorityType {
	SERVER_ONLY,  # Only server can control
	OWNER_ONLY,   # Only the owner (spawner) can control
	LOCAL_ONLY,   # Only local player can control
	ANY_CLIENT    # Any client can control (not recommended)
}

## Authority type for this object
@export var authority_type: AuthorityType = AuthorityType.SERVER_ONLY

## Peer ID that owns this object (set automatically on spawn)
var owner_peer_id: int = -1

## Is this object controlled by the local peer?
var is_local_authority: bool = false

## Is this object controlled by the server?
var is_server_authority: bool = false


func _ready() -> void:
	_update_authority()
	
	# Connect to network events
	if NetworkManager:
		NetworkManager.network_connected.connect(_on_network_connected)
		NetworkManager.network_disconnected.connect(_on_network_disconnected)


## Update authority status
func _update_authority() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		# Single-player: always has authority
		is_local_authority = true
		is_server_authority = true
		return
	
	var local_peer_id = NetworkManager.get_local_peer_id()
	var is_server = NetworkManager.is_host()
	
	match authority_type:
		AuthorityType.SERVER_ONLY:
			is_server_authority = is_server
			is_local_authority = is_server
		
		AuthorityType.OWNER_ONLY:
			is_local_authority = (owner_peer_id == local_peer_id)
			is_server_authority = is_server
		
		AuthorityType.LOCAL_ONLY:
			is_local_authority = true
			is_server_authority = false
		
		AuthorityType.ANY_CLIENT:
			is_local_authority = true
			is_server_authority = false


## Check if local peer has authority over this object
func has_authority() -> bool:
	return is_local_authority


## Check if server has authority over this object
func server_has_authority() -> bool:
	return is_server_authority


## Set the owner peer ID (usually called when spawning)
func set_owner_peer(peer_id: int) -> void:
	owner_peer_id = peer_id
	_update_authority()


## Get the owner peer ID
func get_owner_peer() -> int:
	return owner_peer_id


## Callback when network connects
func _on_network_connected(peer_id: int) -> void:
	_update_authority()


## Callback when network disconnects
func _on_network_disconnected(peer_id: int) -> void:
	# If owner disconnected, transfer authority to server
	if owner_peer_id == peer_id and authority_type == AuthorityType.OWNER_ONLY:
		authority_type = AuthorityType.SERVER_ONLY
		owner_peer_id = -1
		_update_authority()
	else:
		_update_authority()

