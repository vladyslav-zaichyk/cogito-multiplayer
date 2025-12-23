extends Node
## NetworkClock: Synchronizes client time with host time for interpolation
## This allows clients to render objects "in the past" for smooth interpolation

var estimated_host_time: float = 0.0
var time_offset: float = 0.0
var _last_sync_time: float = 0.0
var _sync_interval: float = 0.5  # Sync every 0.5s

func _ready() -> void:
	if NetworkManager and NetworkManager.is_host():
		estimated_host_time = Time.get_ticks_msec() / 1000.0
	set_process(true)


func _process(delta: float) -> void:
	if NetworkManager and NetworkManager.is_host():
		estimated_host_time += delta
		_last_sync_time += delta
		if _last_sync_time >= _sync_interval:
			_last_sync_time = 0.0
			sync_host_time.rpc(estimated_host_time)
	else:
		estimated_host_time += delta


func get_estimated_host_time() -> float:
	return estimated_host_time


@rpc("any_peer", "unreliable")
func sync_host_time(host_time: float) -> void:
	if NetworkManager and NetworkManager.is_host():
		return
	
	var local_receive_time = Time.get_ticks_msec() / 1000.0
	var new_offset = host_time - local_receive_time
	
	# EMA filter для згладжування
	time_offset = lerp(time_offset, new_offset, 0.1)
	estimated_host_time = local_receive_time + time_offset

