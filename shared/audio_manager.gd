extends Node

const _SFX_PATHS := {
	"btn_hover": "res://assets/Audio/SFX/btn_hover.wav",
	"click": "res://assets/Audio/SFX/click.wav",
	"catmeow": "res://assets/Audio/SFX/catmeow.wav",
	"level_win": "res://assets/Audio/SFX/level_win.wav",
	"player_move": "res://assets/Audio/SFX/player move.wav",
	"player_move_fail": "res://assets/Audio/SFX/player_move_fail.wav",
	"player_spawn": "res://assets/Audio/SFX/player_spawn.wav",
	"player_win": "res://assets/Audio/SFX/player_win.wav",
	"room_failed": "res://assets/Audio/SFX/room_failed.wav",
	"room_grab": "res://assets/Audio/SFX/room_grab.wav",
	"room_place_move": "res://assets/Audio/SFX/room_place_move.wav",
}

const _MUSIC_PATH := "res://assets/Audio/Music/ES_Fair N Square - William Benckert.mp3"
const _SETTINGS_PATH := "user://settings.json"
const _MUSIC_BASE_MULT := 0.6

var _players: Dictionary = {}
var _music_player: AudioStreamPlayer
var music_enabled: bool = true
var sfx_enabled: bool = true
var music_volume: float = 0.5  # 0.0 – 1.0
var sfx_volume: float = 1.0    # 0.0 – 1.0
var _audio_shutdown: bool = false
var _audio_disabled: bool = false


func _ready() -> void:
	_load_settings()
	_audio_disabled = AudioServer.get_driver_name().to_lower() == "dummy"
	if _audio_disabled:
		return

	for key in _SFX_PATHS:
		var player := AudioStreamPlayer.new()
		player.stream = load(_SFX_PATHS[key])
		add_child(player)
		_players[key] = player
	_apply_sfx_volume()

	_music_player = AudioStreamPlayer.new()
	_music_player.stream = load(_MUSIC_PATH)
	add_child(_music_player)
	_music_player.finished.connect(_music_player.play)
	_apply_music_volume()
	if music_enabled:
		_music_player.play()


func _exit_tree() -> void:
	_shutdown_audio()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown_audio()


func _shutdown_audio() -> void:
	if _audio_shutdown:
		return
	_audio_shutdown = true

	if _music_player:
		if _music_player.finished.is_connected(_music_player.play):
			_music_player.finished.disconnect(_music_player.play)
		_music_player.stop()
		_music_player.stream = null

	for player_var: Variant in _players.values():
		var player := player_var as AudioStreamPlayer
		if player == null:
			continue
		player.stop()
		player.stream = null
	_players.clear()


func play(sound: String) -> void:
	if _audio_disabled or _audio_shutdown:
		return
	if not sfx_enabled:
		return
	if _players.has(sound):
		_players[sound].play()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if _audio_disabled or _audio_shutdown:
		_save_settings()
		return
	if enabled:
		if not _music_player.playing:
			_music_player.play()
	else:
		_music_player.stop()
	_save_settings()


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	_save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	if not _audio_shutdown:
		_apply_music_volume()
	_save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if not _audio_shutdown:
		_apply_sfx_volume()
	_save_settings()


func _apply_music_volume() -> void:
	if _music_player == null:
		return
	_music_player.volume_db = _to_db(clampf(music_volume * _MUSIC_BASE_MULT, 0.0, 1.0))


func _apply_sfx_volume() -> void:
	for player: Variant in _players.values():
		(player as AudioStreamPlayer).volume_db = _to_db(sfx_volume)


func _to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return linear_to_db(linear)


func _save_settings() -> void:
	var file := FileAccess.open(_SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"music_enabled": music_enabled,
			"sfx_enabled": sfx_enabled,
			"music_volume": music_volume,
			"sfx_volume": sfx_volume,
		}))


func _load_settings() -> void:
	if not FileAccess.file_exists(_SETTINGS_PATH):
		return
	var file := FileAccess.open(_SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return
	var data := parsed as Dictionary
	if data.has("music_enabled"):
		music_enabled = bool(data["music_enabled"])
	if data.has("sfx_enabled"):
		sfx_enabled = bool(data["sfx_enabled"])
	if data.has("music_volume"):
		music_volume = clampf(float(data["music_volume"]), 0.0, 1.0)
	if data.has("sfx_volume"):
		sfx_volume = clampf(float(data["sfx_volume"]), 0.0, 1.0)
