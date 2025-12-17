extends Node
#Loads options like volume and graphic options on game startup

var config = ConfigFile.new()

@onready var sfx_bus_index = AudioServer.get_bus_index(OptionsConstants.SFX_BUS_NAME)
@onready var music_bus_index = AudioServer.get_bus_index(OptionsConstants.MUSIC_BUS_NAME)

# Loads settings from config file. Loads with standard values if settings not 
# existing
func load_settings():
	var err = config.load(OptionsConstants.CONFIG_FILE_NAME)
	
	if err != OK:
		return
	
	var sfx_volume = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.SFX_VOLUME_KEY_NAME, 1)
	var music_volume = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.MUSIC_VOLUME_KEY_NAME, 1)
	var is_fullscreen = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.FULLSCREEN_MODE_KEY_NAME, DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	var resolution_index = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.RESOLUTION_INDEX_KEY_NAME, 0)
	var fullscreen_resolution_scale = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.FULLSCREEN_RESOLUTION_SCALE_KEY, 1.0)
	var gui_scale = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.GUI_SCALE_KEY, 1)
	var vsync = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.VSYNC_KEY, true)
	var invert_y = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.INVERT_VERTICAL_AXIS_KEY, true)
	var msaa_2d = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.MSAA_2D_KEY, 0)
	var msaa_3d = config.get_value(OptionsConstants.SECTION_NAME, OptionsConstants.MSAA_3D_KEY, 0)
	
	AudioServer.set_bus_volume_db(sfx_bus_index, sfx_volume)
	AudioServer.set_bus_volume_db(music_bus_index, music_volume)
	
	# Set window mode based on fullscreen toggle
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	
	# Apply appropriate 3D scaling based on window mode (fullscreen vs windowed)
	if is_fullscreen:
		get_viewport().scaling_3d_scale = fullscreen_resolution_scale
	else:
		get_viewport().scaling_3d_scale = 1.0
	
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		
	set_msaa("msaa_2d", msaa_2d)
	set_msaa("msaa_3d", msaa_3d)


func _ready():
	load_settings()


func set_msaa(mode, index):
	match index:
		0:
			get_viewport().set(mode, Viewport.MSAA_DISABLED)
		1:
			get_viewport().set(mode, Viewport.MSAA_2X)
		2:
			get_viewport().set(mode, Viewport.MSAA_4X)
		3:
			get_viewport().set(mode, Viewport.MSAA_8X)
