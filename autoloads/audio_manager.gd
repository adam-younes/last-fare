extends Node
## Centralized audio management for timing scares and layered ambience.

# Audio buses: Master, Ambient, SFX, Music, Voice

# Ambient layers — always running, crossfade between states
var _ambient_players: Dictionary = {}

enum AmbienceState {
	NORMAL_DRIVING,
	IDLE_WAITING,
	TENSION,
	SILENCE,       # The scariest sound
	WRONG,         # Something is off — distorted, detuned
}

var current_ambience: AmbienceState = AmbienceState.IDLE_WAITING


func _ready() -> void:
	# Create audio bus layout at runtime if not using a .tres
	_setup_ambient_layers()


func _setup_ambient_layers() -> void:
	# Pre-create AudioStreamPlayers for each ambient layer
	var layer_names := ["engine", "road", "radio", "interior", "wrongness"]
	for layer_name in layer_names:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"  # Change to "Ambient" once bus layout exists
		player.volume_db = -80.0  # Start silent
		player.name = "Ambient_" + layer_name
		add_child(player)
		_ambient_players[layer_name] = player


func set_ambience(state: AmbienceState, fade_time: float = 2.0) -> void:
	current_ambience = state
	match state:
		AmbienceState.NORMAL_DRIVING:
			_fade_layer("engine", 0.0, fade_time)
			_fade_layer("road", -5.0, fade_time)
			_fade_layer("radio", -15.0, fade_time)
			_fade_layer("interior", -10.0, fade_time)
			_fade_layer("wrongness", -80.0, fade_time)
		AmbienceState.IDLE_WAITING:
			_fade_layer("engine", -10.0, fade_time)
			_fade_layer("road", -80.0, fade_time)
			_fade_layer("radio", -20.0, fade_time)
			_fade_layer("interior", -5.0, fade_time)
			_fade_layer("wrongness", -80.0, fade_time)
		AmbienceState.TENSION:
			_fade_layer("engine", -5.0, fade_time)
			_fade_layer("road", -10.0, fade_time)
			_fade_layer("radio", -80.0, fade_time)
			_fade_layer("interior", -3.0, fade_time)
			_fade_layer("wrongness", -20.0, fade_time)
		AmbienceState.SILENCE:
			_fade_layer("engine", -80.0, fade_time * 0.5)
			_fade_layer("road", -80.0, fade_time * 0.5)
			_fade_layer("radio", -80.0, fade_time * 0.3)
			_fade_layer("interior", -80.0, fade_time * 0.5)
			_fade_layer("wrongness", -80.0, fade_time)
		AmbienceState.WRONG:
			_fade_layer("engine", -3.0, fade_time)
			_fade_layer("road", -8.0, fade_time)
			_fade_layer("radio", -80.0, fade_time * 0.3)
			_fade_layer("interior", -5.0, fade_time)
			_fade_layer("wrongness", -5.0, fade_time)


func _fade_layer(layer_name: String, target_db: float, duration: float) -> void:
	if not _ambient_players.has(layer_name):
		return
	var player: AudioStreamPlayer = _ambient_players[layer_name]
	var tween := create_tween()
	tween.tween_property(player, "volume_db", target_db, duration)


## Play a one-shot sound effect.
func play_sfx(stream: AudioStream, volume_db: float = 0.0, bus: String = "Master") -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = bus
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## Play a sound effect with positional delay (for timing scares).
func play_sfx_delayed(stream: AudioStream, delay: float, volume_db: float = 0.0) -> void:
	await get_tree().create_timer(delay).timeout
	play_sfx(stream, volume_db)


## Set a specific ambient layer's stream.
func set_layer_stream(layer_name: String, stream: AudioStream) -> void:
	if _ambient_players.has(layer_name):
		var player: AudioStreamPlayer = _ambient_players[layer_name]
		player.stream = stream
		if not player.playing and stream != null:
			player.play()


## Stop all audio (for scene transitions or hard cuts).
func stop_all(fade_time: float = 0.5) -> void:
	for player: AudioStreamPlayer in _ambient_players.values():
		var tween := create_tween()
		tween.tween_property(player, "volume_db", -80.0, fade_time)
		tween.tween_callback(player.stop)
