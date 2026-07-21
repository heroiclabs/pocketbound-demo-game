extends CanvasLayer

@onready var _music_btn: Button = %MusicBtn
@onready var _music_slider: HSlider = %MusicSlider
@onready var _sfx_btn: Button = %SfxBtn
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _close_btn: Button = %CloseBtn


func _ready() -> void:
	_music_btn.text = "ON" if AudioManager.music_enabled else "OFF"
	_sfx_btn.text = "ON" if AudioManager.sfx_enabled else "OFF"
	_music_slider.value = AudioManager.music_volume
	_sfx_slider.value = AudioManager.sfx_volume

	_music_btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	_music_btn.pressed.connect(func(): AudioManager.play("click"))
	_music_btn.pressed.connect(func():
		AudioManager.set_music_enabled(not AudioManager.music_enabled)
		_music_btn.text = "ON" if AudioManager.music_enabled else "OFF"
	)

	_music_slider.value_changed.connect(func(v: float): AudioManager.set_music_volume(v))

	_sfx_btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	_sfx_btn.pressed.connect(func(): AudioManager.play("click"))
	_sfx_btn.pressed.connect(func():
		AudioManager.set_sfx_enabled(not AudioManager.sfx_enabled)
		_sfx_btn.text = "ON" if AudioManager.sfx_enabled else "OFF"
	)

	_sfx_slider.value_changed.connect(func(v: float): AudioManager.set_sfx_volume(v))

	_close_btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	_close_btn.pressed.connect(func(): AudioManager.play("click"))
	_close_btn.pressed.connect(queue_free)
