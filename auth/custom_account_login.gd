extends CanvasLayer

signal login_completed
signal create_account_requested

const MENU_DESIGN_SIZE := Vector2(1280, 720)

@onready var _ui_root: Control = %UiRoot
@onready var _username_field: LineEdit = %UsernameField
@onready var _password_field: LineEdit = %PasswordField
@onready var _submit_button: Button = %SubmitBtn
@onready var _create_account_button: Button = %CreateAccountBtn
@onready var _password_status_label: Label = %PasswordStatus
@onready var _status_label: Label = %StatusLabel

var _is_submitting := false


func _ready() -> void:
	get_viewport().size_changed.connect(_layout_ui_scale)
	_layout_ui_scale()
	_update_submit_state()
	_username_field.grab_focus()
	_username_field.text_changed.connect(_on_field_changed)
	_username_field.text_submitted.connect(func(_new_text: String): _on_submit_pressed())
	_password_field.text_changed.connect(_on_password_changed)
	_password_field.text_submitted.connect(func(_new_text: String): _on_submit_pressed())
	_submit_button.pressed.connect(_on_submit_pressed)
	_create_account_button.pressed.connect(_on_create_account_pressed)


func reset_form() -> void:
	_is_submitting = false
	_username_field.text = ""
	_password_field.text = ""
	_submit_button.text = "Enter"
	_create_account_button.visible = false
	_password_status_label.visible = false
	_status_label.visible = false
	_update_submit_state()


func _layout_ui_scale() -> void:
	if not _ui_root:
		return

	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var scale_factor := minf(vp_size.x / MENU_DESIGN_SIZE.x, vp_size.y / MENU_DESIGN_SIZE.y)
	_ui_root.scale = Vector2.ONE * scale_factor
	_ui_root.position = (vp_size - MENU_DESIGN_SIZE * scale_factor) * 0.5


func _on_field_changed(_new_text: String) -> void:
	if _status_label:
		_status_label.visible = false
	var lowered := _username_field.text.to_lower()
	if lowered != _username_field.text:
		var caret_column := _username_field.caret_column
		_username_field.text = lowered
		_username_field.caret_column = min(caret_column, lowered.length())
		return
	_create_account_button.visible = false
	_update_submit_state()


func _on_password_changed(_new_text: String) -> void:
	if _status_label:
		_status_label.visible = false
	_create_account_button.visible = false
	_validate_password_field()
	_update_submit_state()


func _update_submit_state() -> void:
	if not _submit_button:
		return
	var username := _username_field.text.strip_edges()
	var password := _password_field.text
	var username_ok := not username.is_empty() \
		and username.length() <= 128 \
		and not username.contains(" ") \
		and SessionController.is_username_email_compatible(username)
	var password_ok := password.length() >= 8
	_submit_button.disabled = _is_submitting or not username_ok or not password_ok


func _on_submit_pressed() -> void:
	if _is_submitting:
		return

	var username := _username_field.text.strip_edges().to_lower()
	var password := _password_field.text
	var validation_error := _validate_inputs(username, password)
	if not validation_error.is_empty():
		_show_status(validation_error, true)
		return

	_is_submitting = true
	_submit_button.text = "Signing in..."
	_create_account_button.visible = false
	_update_submit_state()
	_show_status("Signing in...", false)

	var hidden_email := _build_hidden_email(username)
	var previous_session := OnlineSession.session
	var auth_result = await OnlineSession.client.authenticate_email_async(hidden_email, password, null, false)
	if auth_result == null:
		_finish_submit("Could not log in.", true)
		_create_account_button.visible = true
		return
	if auth_result.is_exception():
		_finish_submit(_format_auth_error(str(auth_result.get_exception().message)), true)
		_create_account_button.visible = true
		return

	OnlineSession.session = auth_result
	var link_error := await OnlineSession.link_current_device_after_login(auth_result, previous_session)
	if not link_error.is_empty():
		push_warning("Could not link device after login: %s" % link_error)
	_show_status("Logged in.", false)
	login_completed.emit()


func _finish_submit(message: String, is_error: bool) -> void:
	_is_submitting = false
	_submit_button.text = "Enter"
	_update_submit_state()
	_show_status(message, is_error)


func _validate_inputs(username: String, password: String) -> String:
	if username.is_empty():
		return "Username is required."
	if username.length() > 128:
		return "Username max length is 128."
	if username.contains(" "):
		return "Username cannot contain spaces."
	if not SessionController.is_username_email_compatible(username):
		return "Use only letters, numbers, ., _, -"
	if password.length() < 8:
		return "Password must be at least 8 characters."
	return ""


# See custom_account_gate.gd _build_hidden_email() for a full explanation of
# this pattern and why authenticate_custom() is the production alternative.
func _build_hidden_email(username: String) -> String:
	return "%s@email.com" % username.to_lower()


func _format_auth_error(message: String) -> String:
	var msg := message.strip_edges()
	if msg.is_empty():
		return "Could not log in."
	return msg


func _show_status(text: String, is_error: bool) -> void:
	if not _status_label:
		return
	_status_label.text = text
	_status_label.visible = not text.is_empty()
	_status_label.add_theme_color_override("font_color", Palette.LIGHTEST if is_error else Palette.LIGHT)


func _validate_password_field() -> void:
	var password := _password_field.text
	if password.is_empty():
		_password_status_label.visible = false
		return
	if password.length() < 8:
		var remaining := 8 - password.length()
		var plural := "" if remaining == 1 else "s"
		_set_field_status(_password_status_label, "%d more character%s needed." % [remaining, plural], true)
		return
	_set_field_status(_password_status_label, "Password length OK.", false, true)


func _set_field_status(label: Label, text: String, is_error: bool, is_success: bool = false) -> void:
	label.text = text
	label.visible = not text.is_empty()
	var color := Palette.DARKEST if is_error else Palette.LIGHT
	if is_success:
		color = Palette.LIGHTEST
	label.add_theme_color_override("font_color", color)


func _on_create_account_pressed() -> void:
	create_account_requested.emit()


