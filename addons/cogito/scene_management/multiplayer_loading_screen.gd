extends Control
## Multiplayer Loading Screen
## Shows loading progress and waits for all peers to load the scene
## This is a NEW scene, not editing the existing loading_screen.gd

signal loading_complete

@onready var loading_label: Label = $VBoxContainer/LoadingLabel
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var progress_bar: ProgressBar = $VBoxContainer/ProgressBar

var next_scene_path: String = ""
var is_waiting_for_peers: bool = false


func _ready() -> void:
	# Connect to WorldLoadingManager
	if WorldLoadingManager:
		# We'll handle loading ourselves
	
	# Start loading
	if next_scene_path != "":
		start_loading(next_scene_path)


func start_loading(scene_path: String) -> void:
	next_scene_path = scene_path
	
	if loading_label:
		loading_label.text = "Loading scene..."
	
	if status_label:
		status_label.text = "Preparing to load..."
	
	# Load scene asynchronously
	_load_scene_async(scene_path)


func _load_scene_async(scene_path: String) -> void:
	# Start threaded loading
	ResourceLoader.load_threaded_request(scene_path)
	
	# Update progress
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_update_loading_progress)
	timer.autostart = true
	add_child(timer)
	
	# Wait for loading to complete
	await _wait_for_scene_loaded(scene_path)
	
	# Scene loaded, now wait for all peers
	_wait_for_all_peers()


func _update_loading_progress() -> void:
	if next_scene_path == "":
		return
	
	var progress = []
	var status = ResourceLoader.load_threaded_get_status(next_scene_path, progress)
	
	if progress_bar:
		if progress.size() > 0:
			progress_bar.value = progress[0] * 100
	
	if status_label:
		match status:
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				status_label.text = "Invalid resource"
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				status_label.text = "Loading... %d%%" % (progress[0] * 100)
			ResourceLoader.THREAD_LOAD_LOADED:
				status_label.text = "Scene loaded, waiting for other players..."
			ResourceLoader.THREAD_LOAD_FAILED:
				status_label.text = "Failed to load scene"
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				status_label.text = "Invalid resource"


func _wait_for_scene_loaded(scene_path: String) -> void:
	while true:
		var progress = []
		var status = ResourceLoader.load_threaded_get_status(scene_path, progress)
		
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			# Get the loaded scene
			var packed_scene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
			if packed_scene:
				# Change to the new scene
				get_tree().change_scene_to_packed(packed_scene)
				break
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			if status_label:
				status_label.text = "Failed to load scene!"
			return
		
		await get_tree().process_frame


func _wait_for_all_peers() -> void:
	if not NetworkManager or not NetworkManager.is_multiplayer():
		# Single-player: no need to wait
		loading_complete.emit()
		return
	
	is_waiting_for_peers = true
	
	if status_label:
		status_label.text = "Waiting for other players to load..."
	
	# Notify WorldLoadingManager that we've loaded
	# We'll use a public method instead
	if WorldLoadingManager:
		WorldLoadingManager.notify_scene_loaded()
	
	# Wait for all peers to load
	await _check_all_peers_loaded()
	
	is_waiting_for_peers = false
	loading_complete.emit()


func _check_all_peers_loaded() -> void:
	if not WorldLoadingManager:
		await get_tree().create_timer(0.5).timeout
		return
	
	# Wait until WorldLoadingManager says all peers are loaded
	while WorldLoadingManager.is_loading():
		if status_label:
			var loaded_peers = WorldLoadingManager.get_loaded_peers()
			var total_peers = 1  # Server
			if NetworkManager:
				total_peers += NetworkManager.get_connected_peers().size()
			status_label.text = "Waiting for players... (%d/%d loaded)" % [loaded_peers.size(), total_peers]
		
		await get_tree().process_frame
	
	if status_label:
		status_label.text = "All players ready!"

