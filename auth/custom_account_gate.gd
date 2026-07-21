extends CanvasLayer

signal setup_completed

const MENU_DESIGN_SIZE := Vector2(1280, 720)

@onready var _ui_root: Control = %UiRoot
@onready var _username_field: LineEdit = %UsernameField
@onready var _password_field: LineEdit = %PasswordField
@onready var _submit_button: Button = %SubmitBtn
@onready var _username_status_label: Label = %UsernameStatus
@onready var _password_status_label: Label = %PasswordStatus
@onready var _status_label: Label = %StatusLabel

var _is_submitting := false
var _username_available := false
var _username_check_pending := false
var _username_check_seq := 0


func _ready() -> void:
	get_viewport().size_changed.connect(_layout_ui_scale)
	_layout_ui_scale()
	_update_submit_state()
	_username_field.grab_focus()
	_username_field.text_changed.connect(_on_username_changed)
	_username_field.text_submitted.connect(func(_new_text: String): _on_submit_pressed())
	_password_field.text_changed.connect(_on_password_changed)
	_password_field.text_submitted.connect(func(_new_text: String): _on_submit_pressed())
	_submit_button.pressed.connect(_on_submit_pressed)


func _layout_ui_scale() -> void:
	if not _ui_root:
		return

	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var scale_factor := minf(vp_size.x / MENU_DESIGN_SIZE.x, vp_size.y / MENU_DESIGN_SIZE.y)
	_ui_root.scale = Vector2.ONE * scale_factor
	_ui_root.position = (vp_size - MENU_DESIGN_SIZE * scale_factor) * 0.5


func _on_username_changed(_new_text: String) -> void:
	if _status_label:
		_status_label.visible = false
	var lowered := _username_field.text.to_lower()
	if lowered != _username_field.text:
		_username_check_seq += 1
		_username_available = false
		_username_check_pending = false
		var caret_column := _username_field.caret_column
		_username_field.text = lowered
		_username_field.caret_column = min(caret_column, lowered.length())
		return
	var username := _username_field.text.strip_edges()

	_username_check_seq += 1
	var seq := _username_check_seq

	if username.is_empty():
		_username_check_pending = false
		_username_available = false
		_username_status_label.visible = false
		_update_submit_state()
		return
	if username.length() > 128:
		_username_check_pending = false
		_username_available = false
		_set_field_status(_username_status_label, "Username max length is 128.", true)
		_update_submit_state()
		return
	if username.contains(" "):
		_username_check_pending = false
		_username_available = false
		_set_field_status(_username_status_label, "Username cannot contain spaces.", true)
		_update_submit_state()
		return
	if not SessionController.is_username_email_compatible(username):
		_username_check_pending = false
		_username_available = false
		_set_field_status(_username_status_label, "Use only letters, numbers, ., _, -", true)
		_update_submit_state()
		return

	_username_check_pending = true
	_username_available = false
	_set_field_status(_username_status_label, "Checking username...", false)
	_update_submit_state()

	await get_tree().create_timer(0.35).timeout
	if seq != _username_check_seq:
		return

	var has_session := await _ensure_session()
	if seq != _username_check_seq:
		return
	if not has_session:
		_username_check_pending = false
		_username_available = false
		_set_field_status(_username_status_label, "Could not check username.", true)
		_update_submit_state()
		return

	var username_taken := await _is_username_taken(username)
	if seq != _username_check_seq:
		return

	_username_check_pending = false
	_username_available = not username_taken
	if username_taken:
		_set_field_status(_username_status_label, "Username is taken.", true)
	else:
		_set_field_status(_username_status_label, "Username is available!", false, true)
	_update_submit_state()


func _on_password_changed(_new_text: String) -> void:
	if _status_label:
		_status_label.visible = false
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
		and SessionController.is_username_email_compatible(username) \
		and not _username_check_pending \
		and _username_available
	var password_ok := password.length() >= 8
	_submit_button.disabled = _is_submitting \
		or not username_ok \
		or not password_ok


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
	_submit_button.text = "Creating..."
	_update_submit_state()
	_show_status("Creating your account...", false)

	var hidden_email := _build_hidden_email(username)
	var auth_result = await OnlineSession.client.authenticate_email_async(hidden_email, password, username, true)
	if auth_result == null:
		_finish_submit("Could not create account.", true)
		return
	if auth_result.is_exception():
		_finish_submit(_format_create_error(str(auth_result.get_exception().message)), true)
		return

	OnlineSession.session = auth_result

	_show_status("Account created.", false)
	setup_completed.emit()


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
	if _username_check_pending:
		return "Checking username..."
	if not _username_available:
		return "Pick an available username."
	if password.length() < 8:
		return "Password must be at least 8 characters."
	return ""


func _ensure_session() -> bool:
	if not OnlineSession.session:
		await OnlineSession.session_ready
	return OnlineSession.session != null


func _is_username_taken(username: String) -> bool:
	var result = await OnlineSession.client.get_users_async(OnlineSession.session, PackedStringArray(), [username])
	if result == null or result.is_exception():
		return false
	for user in result.users:
		if str(user.id) == str(OnlineSession.session.user_id):
			continue
		if str(user.username).strip_edges().nocasecmp_to(username) == 0:
			return true
	return false


# Nakama's email auth requires a real-looking email, but our custom auth scheme
# is username + password only. We construct a synthetic email by appending a
# fixed domain so we can reuse the email auth flow without exposing an actual
# email address. The domain "email.com" is a real registered domain, so in
# theory two users with identical usernames on different systems could collide —
# this is acceptable for a sample project but a production game should use
# authenticate_custom() with a server-generated opaque identifier instead.
func _build_hidden_email(username: String) -> String:
	return "%s@email.com" % username.to_lower()


func _format_create_error(message: String) -> String:
	var msg := message.strip_edges()
	if msg.is_empty():
		return "Could not create account."
	var lowered := msg.to_lower()
	if ("already in use" in lowered or "already exists" in lowered) and "username" in lowered:
		return "Username is already in use."
	if ("already in use" in lowered or "already exists" in lowered) and "email" in lowered:
		return "Account already exists. Try logging in."
	if "invalid email" in lowered:
		return "Use only letters, numbers, ., _, -"
	return msg


func _show_status(text: String, is_error: bool) -> void:
	if not _status_label:
		return
	_status_label.text = text
	_status_label.visible = not text.is_empty()
	_status_label.add_theme_color_override("font_color", Palette.DARKEST if is_error else Palette.LIGHTEST)


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
