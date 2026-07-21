extends CanvasLayer
class_name MainMenu

signal create_level_requested
signal play_level_requested(level_key: String, owner_id: String, source: String)
signal edit_level_requested(level_key: String, owner_id: String)
signal my_levels_requested
signal community_levels_requested
signal logout_requested

const OptionsPanel = preload("res://scenes/options_panel.tscn")
const CreditsScene = preload("res://scenes/credits.tscn")

const GUI_BUTTON_NORMAL_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip.tres")
const GUI_BUTTON_ACTIVE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip_right.tres")
const SCROLLBAR_BG_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_bg.tres")
const SCROLLBAR_HANDLE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_handle.tres")
const SPINNER_SCENE: PackedScene = preload("res://scenes/spinner_animation.tscn")
const DISCORD_INVITE_URL := "https://discord.gg/mtnd76cFsc"

const COLOR_TEXT_DARK := Palette.DARKEST
const COLOR_TEXT_LIGHT := Palette.LIGHTEST
const COLOR_STATUS_ERROR := Palette.DARKEST
const COLOR_STATUS_OK := Palette.LIGHTEST
const COLOR_DIALOG_OVERLAY := Palette.DARKEST

const MAIN_BUTTON_SIZE := Vector2(300, 54)
const ACTION_BUTTON_SIZE := Vector2(120, 42)
const DIALOG_BUTTON_SIZE := Vector2(150, 42)
const FRIEND_REQUEST_BUTTON_SIZE := Vector2(42, 30)
const FRIEND_PENDING_BUTTON_SIZE := Vector2(98, 30)
const FRIENDS_PANEL_MIN_WIDTH := 420.0
const FRIENDS_PANEL_MAX_WIDTH := 760.0
const MENU_DESIGN_SIZE := Vector2(1280, 720)

@onready var _background: Sprite2D = %Background
@onready var _ui_root: Control = %UiRoot
@onready var _main_margin: MarginContainer = %MainMargin
@onready var _status_label: Label = %StatusLabel
@onready var _login_label: Label = %LoginLabel
@onready var _friend_lookup_row: HBoxContainer = %FriendLookupRow
@onready var _friend_lookup_field: LineEdit = %FriendLookupField
@onready var _friend_lookup_btn: Button = %FriendLookupBtn
@onready var _friend_search_container: VBoxContainer = %FriendSearchContainer
@onready var _friend_lookup_status: Label = %FriendLookupStatus
@onready var _friend_lookup_results: VBoxContainer = %FriendLookupResults
@onready var _friend_list_container: VBoxContainer = %FriendListContainer
@onready var _friends_header: Label = %FriendsHeader
@onready var _friends_scope_label: Label = %FriendsScopeLabel
@onready var _friends_container: VBoxContainer = %FriendsContainer
@onready var _friends_list_scroll: ScrollContainer = %ListScroll
@onready var _friends_panel: NinePatchRect = %FriendsPanel
@onready var _friends_panel_margin: MarginContainer = %FriendsPanelMargin
@onready var _friends_column: VBoxContainer = %FriendsColumn
@onready var _dialog_overlay: ColorRect = %DialogOverlay
@onready var _dialog_title: Label = %DialogTitle
@onready var _dialog_body: VBoxContainer = %DialogBody
@onready var _dialog_close_btn: Button = %DialogCloseBtn
@onready var _account_setup_form: VBoxContainer = %AccountSetupForm
@onready var _setup_username_field: LineEdit = %SetupUsernameField
@onready var _setup_email_field: LineEdit = %SetupEmailField
@onready var _setup_password_field: LineEdit = %SetupPasswordField
@onready var _setup_error_label: Label = %SetupErrorLabel
@onready var _setup_submit_btn: Button = %SetupSubmitBtn
@onready var _setup_username_status: Label = %SetupUsernameStatus
@onready var _setup_email_status: Label = %SetupEmailStatus
@onready var _setup_password_status: Label = %SetupPasswordStatus
@onready var _discord_btn: Button = %DiscordBtn

var _has_email: bool = false
var _options_panel: Node = null
var _credits_panel: Node = null
var _username_available: bool = true
var _username_check_seq: int = 0
var _friends_widgets: Array[Control] = []

var _friend_lookup_results_data: Array = []
var _friend_lookup_seq: int = 0
var _friend_lookup_add_inflight: Dictionary = {}
var _friend_request_action_inflight: Dictionary = {}
var _refresh_inflight := false
var _community_filter_seq: int = 0
var _friends_panel_fit_queued := false
var _friend_lookup_mode_active := false
var _single_player_dialog_open := false

var _friends_ctrl := FriendsController.new()
var _campaign_ctrl := CampaignController.new()


func _ready() -> void:
	_friends_widgets = [
		_login_label,
		%SearchHeader,
		_friend_lookup_row,
		_friend_search_container,
		_friend_list_container,
	]

	get_viewport().size_changed.connect(_layout_background)
	get_viewport().size_changed.connect(_layout_ui_scale)
	get_viewport().size_changed.connect(_layout_dialog_close_button)
	_layout_background()
	_layout_ui_scale()
	_setup_dialog_close_button()

	_update_login_label(_login_label)

	_wire_btn(%SinglePlayerBtn, _on_single_player_pressed)
	_wire_btn(%CreatorBtn, func(): my_levels_requested.emit())
	_wire_btn(%CommunityBtn, func(): community_levels_requested.emit())
	_wire_btn(%CreditsBtn, _on_credits_pressed)
	_wire_btn(%OptionsBtn, _on_options_pressed)
	_wire_btn(%LogoutBtn, _on_logout_pressed)
	_wire_btn(%QuitBtn, _on_quit_pressed)
	if _discord_btn:
		_wire_btn(_discord_btn, _on_discord_pressed)
	if OS.has_feature("web"):
		%QuitBtn.visible = false
	_wire_btn(_dialog_close_btn, _close_dialog)
	_wire_btn(_friend_lookup_btn, _on_friend_lookup_pressed)

	_friend_lookup_field.text_submitted.connect(func(_new_text: String): _on_friend_lookup_pressed())
	_friend_lookup_field.text_changed.connect(_on_friend_lookup_text_changed)

	_setup_username_field.text_changed.connect(_on_setup_username_changed)
	_setup_email_field.text_changed.connect(_on_setup_field_changed)
	_setup_password_field.text_changed.connect(_on_setup_field_changed)
	_wire_btn(_setup_submit_btn, _on_setup_submit_pressed)
	_apply_friends_scrollbar_theme()
	_clear_friend_lookup_status()
	_set_friend_lookup_mode(false)

	_schedule_friends_panel_fit()
	refresh()


func _wire_btn(btn: Button, callback: Callable = Callable()) -> void:
	btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	btn.pressed.connect(func(): AudioManager.play("click"))
	if callback.is_valid():
		btn.pressed.connect(callback)


func _layout_background() -> void:
	if not _background or not _background.texture:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var tex_size := _background.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale_factor := maxf(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
	_background.scale = Vector2.ONE * scale_factor
	_background.position = vp_size * 0.5


func _layout_ui_scale() -> void:
	if not _ui_root:
		return

	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	var scale_factor := minf(vp_size.x / MENU_DESIGN_SIZE.x, vp_size.y / MENU_DESIGN_SIZE.y)
	_ui_root.scale = Vector2.ONE * scale_factor
	_ui_root.position = (vp_size - MENU_DESIGN_SIZE * scale_factor) * 0.5


func _setup_dialog_close_button() -> void:
	if _dialog_close_btn == null:
		return
	_dialog_close_btn.text = "Back"
	_dialog_close_btn.custom_minimum_size = Vector2(180, 50.4)
	if _dialog_close_btn.get_parent() != self:
		var old_parent := _dialog_close_btn.get_parent()
		if old_parent:
			old_parent.remove_child(_dialog_close_btn)
		add_child(_dialog_close_btn)
	_dialog_close_btn.size_flags_horizontal = 0
	_dialog_close_btn.size_flags_vertical = 0
	_dialog_close_btn.visible = false
	_dialog_close_btn.z_index = 1000
	_layout_dialog_close_button()


func _layout_dialog_close_button() -> void:
	if _dialog_close_btn == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	var margin := 20.0
	var btn_size := _dialog_close_btn.get_combined_minimum_size()
	_dialog_close_btn.position = Vector2(margin, vp_size.y - btn_size.y - margin)


func _schedule_friends_panel_fit() -> void:
	if _friends_panel_fit_queued:
		return
	_friends_panel_fit_queued = true
	call_deferred("_fit_friends_panel_to_content")


func _fit_friends_panel_to_content() -> void:
	_friends_panel_fit_queued = false
	if not _friends_panel or not _friends_panel_margin or not _friends_column:
		return

	var margin_left := _friends_panel_margin.get_theme_constant("margin_left")
	var margin_right := _friends_panel_margin.get_theme_constant("margin_right")
	var content_min := _friends_column.get_combined_minimum_size()
	var target_width := clampf(content_min.x + float(margin_left + margin_right), FRIENDS_PANEL_MIN_WIDTH, FRIENDS_PANEL_MAX_WIDTH)

	var min_size := _friends_panel.custom_minimum_size
	if is_equal_approx(min_size.x, target_width):
		return
	min_size.x = target_width
	_friends_panel.custom_minimum_size = min_size


func refresh() -> void:
	if _refresh_inflight:
		return
	_refresh_all_data.call_deferred()


func _show_friends_content(show_friends: bool) -> void:
	for widget in _friends_widgets:
		widget.visible = show_friends
	_account_setup_form.visible = not show_friends
	if not show_friends:
		_setup_error_label.visible = false
		_clear_friend_lookup_status()
	_friend_lookup_mode_active = false
	if show_friends:
		_set_friend_lookup_mode(false)
	_schedule_friends_panel_fit()


func _set_friend_lookup_mode(active: bool) -> void:
	_friend_lookup_mode_active = active
	if not _friend_search_container or not _friend_list_container:
		return
	_friend_search_container.visible = active
	_friend_list_container.visible = not active
	_schedule_friends_panel_fit()


func _on_setup_submit_pressed() -> void:
	var username := _setup_username_field.text.strip_edges().to_lower()
	var email := _setup_email_field.text.strip_edges().to_lower()
	var password := _setup_password_field.text

	_setup_error_label.visible = false
	_setup_submit_btn.disabled = true
	_setup_submit_btn.text = "Creating..."

	var auth_result = await OnlineSession.client.authenticate_email_async(email, password, username, true)
	if auth_result == null:
		_show_setup_error("Could not create account.")
		_setup_submit_btn.text = "Link Account"
		_update_setup_submit_state()
		return
	if auth_result.is_exception():
		_show_setup_error(auth_result.get_exception().message)
		_setup_submit_btn.text = "Link Account"
		_update_setup_submit_state()
		return

	OnlineSession.session = auth_result

	_has_email = true
	_update_login_label(_login_label)
	_show_friends_content(true)
	_setup_submit_btn.text = "Link Account"
	_update_setup_submit_state()
	await _friends_ctrl.load_friends()
	_render_friends()


func _on_setup_username_changed(_new_text: String) -> void:
	var lowered := _setup_username_field.text.to_lower()
	if lowered != _setup_username_field.text:
		_username_check_seq += 1
		_username_available = false
		var caret_column := _setup_username_field.caret_column
		_setup_username_field.text = lowered
		_setup_username_field.caret_column = min(caret_column, lowered.length())
		return
	var username := _setup_username_field.text.strip_edges()
	_update_setup_submit_state()
	if username.is_empty():
		_setup_username_status.visible = false
		_username_available = true
		return
	if username.length() > 128:
		_setup_username_status.text = "Max 128 characters."
		_setup_username_status.add_theme_color_override("font_color", COLOR_STATUS_ERROR)
		_setup_username_status.visible = true
		_username_available = false
		_update_setup_submit_state()
		return
	_username_check_seq += 1
	var seq := _username_check_seq
	_setup_username_status.text = "Checking..."
	_setup_username_status.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	_setup_username_status.visible = true
	await get_tree().create_timer(0.4).timeout
	if seq != _username_check_seq:
		return
	var result = await OnlineSession.client.get_users_async(OnlineSession.session, PackedStringArray(), [username])
	if seq != _username_check_seq:
		return
	if result == null or result.is_exception():
		_setup_username_status.visible = false
		_username_available = true
		_update_setup_submit_state()
		return
	var taken := false
	for user in result.users:
		if str(user.username).strip_edges().nocasecmp_to(username) == 0 and user.id != OnlineSession.session.user_id:
			taken = true
			break
	_username_available = not taken
	if taken:
		_setup_username_status.text = "Username is taken."
		_setup_username_status.add_theme_color_override("font_color", COLOR_STATUS_ERROR)
	else:
		_setup_username_status.text = "Username is available!"
		_setup_username_status.add_theme_color_override("font_color", COLOR_STATUS_OK)
	_setup_username_status.visible = true
	_update_setup_submit_state()


func _on_setup_field_changed(_new_text: String) -> void:
	_validate_email_field()
	_validate_password_field()
	_update_setup_submit_state()


func _is_valid_email(email: String) -> bool:
	return email.length() >= 10 and email.length() <= 255 \
		and email.contains("@") and email.contains(".") \
		and not email.contains(" ")


func _validate_email_field() -> void:
	var email := _setup_email_field.text.strip_edges()
	if email.is_empty():
		_setup_email_status.visible = false
		return
	var valid := _is_valid_email(email)
	if not valid:
		_setup_email_status.text = "Enter a valid email address."
		_setup_email_status.add_theme_color_override("font_color", COLOR_STATUS_ERROR)
	else:
		_setup_email_status.text = "Email looks good."
		_setup_email_status.add_theme_color_override("font_color", COLOR_STATUS_OK)
	_setup_email_status.visible = true


func _validate_password_field() -> void:
	var password := _setup_password_field.text
	if password.is_empty():
		_setup_password_status.visible = false
		return
	if password.length() < 8:
		_setup_password_status.text = "%d more character%s needed." % [8 - password.length(), "" if 8 - password.length() == 1 else "s"]
		_setup_password_status.add_theme_color_override("font_color", COLOR_STATUS_ERROR)
	else:
		_setup_password_status.text = "Password length OK."
		_setup_password_status.add_theme_color_override("font_color", COLOR_STATUS_OK)
	_setup_password_status.visible = true


func _update_setup_submit_state() -> void:
	var username := _setup_username_field.text.strip_edges()
	var email := _setup_email_field.text.strip_edges()
	var password := _setup_password_field.text

	var username_ok := not username.is_empty() and username.length() <= 128 and _username_available
	var email_ok := _is_valid_email(email)
	var password_ok := password.length() >= 8

	_setup_submit_btn.disabled = not (username_ok and email_ok and password_ok)


func _show_setup_error(message: String) -> void:
	_setup_error_label.text = message
	_setup_error_label.visible = true


func _refresh_all_data() -> void:
	_refresh_inflight = true
	_campaign_ctrl.invalidate_cache()

	var has_session := await _ensure_session()
	if not has_session:
		_update_login_label(_login_label)
		_render_friends()
		_set_status("Could not authenticate.")
		_refresh_inflight = false
		return

	_update_login_label(_login_label)

	var account = await OnlineSession.client.get_account_async(OnlineSession.session)
	_has_email = account != null and not account.is_exception() and account.email != ""
	_show_friends_content(true)

	_set_status("Loading single-player levels...")
	await _campaign_ctrl.load_own_levels()
	if _campaign_ctrl.own_levels.is_empty():
		_set_status("No single-player levels found.")
	else:
		_set_status("Loaded %d single-player levels." % _campaign_ctrl.own_levels.size())

	_set_status("Loading friends...")
	_show_friends_loading_spinner()
	var ok := await _friends_ctrl.load_friends()
	if not ok:
		_set_status("Could not load friends.")
		_sync_friend_lookup_results()
		_render_friends()
		_refresh_inflight = false
		return

	_sync_friend_lookup_results()
	_render_friends()
	var accepted_count := _friends_ctrl.count_by_state(FriendsController.FRIEND_STATE_FRIEND)
	var incoming_count := _friends_ctrl.count_by_state(FriendsController.FRIEND_STATE_INVITE_RECEIVED)
	var outgoing_count := _friends_ctrl.count_by_state(FriendsController.FRIEND_STATE_INVITE_SENT)
	_set_status("Loaded %d friends, %d incoming, %d pending." % [accepted_count, incoming_count, outgoing_count])
	_status_label.visible = false
	_refresh_inflight = false


func _ensure_session() -> bool:
	if not OnlineSession.session:
		await OnlineSession.session_ready
	return OnlineSession.session != null


func _show_friends_loading_spinner() -> void:
	for child in _friends_container.get_children():
		child.queue_free()

	var spinner_row := CenterContainer.new()
	spinner_row.name = "FriendsLoading"
	spinner_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinner_row.custom_minimum_size = Vector2(0, 180)
	spinner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var spinner_anchor := Control.new()
	spinner_anchor.custom_minimum_size = Vector2(48, 48)
	spinner_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spinner_row.add_child(spinner_anchor)

	var spinner_instance := SPINNER_SCENE.instantiate()
	if spinner_instance is Node2D:
		var spinner := spinner_instance as Node2D
		spinner_anchor.add_child(spinner)
		spinner.position = spinner_anchor.custom_minimum_size * 0.5
	else:
		spinner_row.add_child(spinner_instance)

	_friends_container.add_child(spinner_row)
	_friends_header.text = "Friends"
	if _friends_scope_label:
		_friends_scope_label.text = "Loading..."
	_schedule_friends_panel_fit()


func _render_friends() -> void:
	for child in _friends_container.get_children():
		child.queue_free()

	var visible_count := 0
	for friend in _friends_ctrl.friends:
		var friend_name := str(friend.get("name", ""))

		visible_count += 1
		var user_id := str(friend.get("user_id", ""))
		var state := int(friend.get("state", FriendsController.FRIEND_STATE_FRIEND))
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, 30)
		row.add_theme_constant_override("separation", 8)
		_friends_container.add_child(row)

		if state == FriendsController.FRIEND_STATE_FRIEND:
			var select_btn := Button.new()
			select_btn.flat = true
			select_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			select_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			select_btn.clip_text = true
			select_btn.text = friend_name
			select_btn.add_theme_font_size_override("font_size", 18)
			select_btn.add_theme_color_override("font_color", COLOR_TEXT_LIGHT if user_id == _friends_ctrl.selected_friend_id else COLOR_TEXT_DARK)
			select_btn.pressed.connect(_on_friend_selected.bind(user_id))
			row.add_child(select_btn)
		elif state == FriendsController.FRIEND_STATE_INVITE_RECEIVED:
			row.add_child(_make_friend_row_label(friend_name))
			var inflight := _friend_request_action_inflight.has(user_id)
			var reject_btn := _make_pixel_button("X", FRIEND_REQUEST_BUTTON_SIZE, 14, _on_friend_request_reject_pressed.bind(user_id))
			reject_btn.disabled = inflight
			row.add_child(reject_btn)
			var accept_btn := _make_pixel_button("✓", FRIEND_REQUEST_BUTTON_SIZE, 16, _on_friend_request_accept_pressed.bind(user_id))
			accept_btn.disabled = inflight
			row.add_child(accept_btn)
		else:
			row.add_child(_make_friend_row_label(friend_name))
			if state == FriendsController.FRIEND_STATE_INVITE_SENT:
				var pending_btn := _make_pixel_button("Pending", FRIEND_PENDING_BUTTON_SIZE, 13)
				pending_btn.disabled = true
				row.add_child(pending_btn)

		var divider := HSeparator.new()
		divider.modulate = Palette.DARKEST
		_friends_container.add_child(divider)

	if visible_count == 0:
		var empty := Label.new()
		empty.text = "No friends found."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.theme_type_variation = &"HeadingLabel"
		_friends_container.add_child(empty)

	var incoming_count := _friends_ctrl.count_by_state(FriendsController.FRIEND_STATE_INVITE_RECEIVED)
	var outgoing_count := _friends_ctrl.count_by_state(FriendsController.FRIEND_STATE_INVITE_SENT)
	_friends_header.text = "Friends"
	if _friends_scope_label:
		_friends_scope_label.text = "Incoming %d | Pending %d" % [incoming_count, outgoing_count]
	_schedule_friends_panel_fit()


func _on_friend_request_accept_pressed(user_id: String) -> void:
	if user_id.is_empty() or _friend_request_action_inflight.has(user_id):
		return
	_friend_request_action_inflight[user_id] = true
	_render_friends()
	_set_status("Accepting friend request...")

	var result = await OnlineSession.client.add_friends_async(OnlineSession.session, [user_id], null)
	_friend_request_action_inflight.erase(user_id)

	if result == null or result.is_exception():
		var message := "Could not accept friend request."
		if result != null and result.is_exception():
			var error_text := str(result.get_exception().message).strip_edges()
			if not error_text.is_empty():
				message = error_text
		_set_status(message)
		_render_friends()
		return

	_clear_friend_lookup_status()
	await _friends_ctrl.load_friends()
	_render_friends()
	_sync_friend_lookup_results()


func _on_friend_request_reject_pressed(user_id: String) -> void:
	if user_id.is_empty() or _friend_request_action_inflight.has(user_id):
		return
	_friend_request_action_inflight[user_id] = true
	_render_friends()
	_set_status("Rejecting friend request...")

	var result = await OnlineSession.client.delete_friends_async(OnlineSession.session, [user_id], null)
	_friend_request_action_inflight.erase(user_id)

	if result == null or result.is_exception():
		var message := "Could not reject friend request."
		if result != null and result.is_exception():
			var error_text := str(result.get_exception().message).strip_edges()
			if not error_text.is_empty():
				message = error_text
		_set_status(message)
		_render_friends()
		return

	_clear_friend_lookup_status()
	await _friends_ctrl.load_friends()
	_render_friends()
	_sync_friend_lookup_results()


func _make_friend_row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = &"HeadingLabel"
	return label


func _on_friend_selected(user_id: String) -> void:
	if _friends_ctrl.state_for(user_id) != FriendsController.FRIEND_STATE_FRIEND:
		return
	_friends_ctrl.selected_friend_id = user_id
	_render_friends()


func _on_friend_lookup_text_changed(_new_text: String) -> void:
	_set_friend_lookup_mode(false)
	_clear_friend_lookup_status()


func _on_friend_lookup_pressed() -> void:
	var query := _friend_lookup_field.text.strip_edges()
	if query.begins_with("@"):
		query = query.substr(1)
	if query.is_empty():
		_set_friend_lookup_status("Enter a username to search.", true)
		return
	if query.contains(" "):
		_set_friend_lookup_status("Usernames cannot contain spaces.", true)
		return

	_set_friend_lookup_mode(true)
	_friend_lookup_results_data.clear()
	_friend_lookup_add_inflight.clear()
	_render_friend_lookup_results()
	_friend_lookup_seq += 1
	var seq := _friend_lookup_seq

	_friend_lookup_btn.disabled = true
	_friend_lookup_btn.text = "Searching..."
	_set_friend_lookup_status("Searching...")

	var result = await OnlineSession.client.get_users_async(OnlineSession.session, PackedStringArray(), [query])
	if seq != _friend_lookup_seq:
		return

	_friend_lookup_btn.disabled = false
	_friend_lookup_btn.text = "Search"

	if result == null or result.is_exception():
		_friend_lookup_results_data.clear()
		_friend_lookup_add_inflight.clear()
		_render_friend_lookup_results()
		_set_friend_lookup_status("Could not search users.", true)
		return

	var users = result.users
	_friend_lookup_results_data.clear()
	_friend_lookup_add_inflight.clear()

	for user in users:
		if user == null:
			continue
		var username := str(user.username).strip_edges()
		if username.nocasecmp_to(query) != 0:
			continue
		var user_id := str(user.id).strip_edges()
		if user_id.is_empty() or user_id == str(OnlineSession.session.user_id):
			continue
		var relation_state := _friends_ctrl.state_for(user_id)
		_friend_lookup_results_data.append({
			"user_id": user_id,
			"username": username,
			"display_name": str(user.display_name).strip_edges(),
			"relation_state": relation_state,
			"already_friend": relation_state == FriendsController.FRIEND_STATE_FRIEND,
		})

	_render_friend_lookup_results()
	if _friend_lookup_results_data.is_empty():
		_set_friend_lookup_status("No player found for @%s." % query)
	else:
		_set_friend_lookup_status("Player found.", false, true)


func _render_friend_lookup_results() -> void:
	for child in _friend_lookup_results.get_children():
		child.queue_free()

	for entry_variant: Variant in _friend_lookup_results_data:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var user_id := str(entry.get("user_id", ""))
		if user_id.is_empty():
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_friend_lookup_results.add_child(row)

		var name_label := Label.new()
		var username := str(entry.get("username", "")).strip_edges()
		var display_name := str(entry.get("display_name", "")).strip_edges()
		var label_text := "@%s" % username
		if username.is_empty():
			label_text = user_id.left(8)
		if not display_name.is_empty() and display_name.nocasecmp_to(username) != 0:
			label_text = "%s (@%s)" % [display_name, username]
		name_label.text = label_text
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.theme_type_variation = &"HeadingLabel"
		row.add_child(name_label)

		var relation_state := int(entry.get("relation_state", FriendsController.FRIEND_STATE_NONE))
		var adding := _friend_lookup_add_inflight.has(user_id)
		var request_action_busy := _friend_request_action_inflight.has(user_id)
		var add_button_text := "Add"
		var add_callback := _on_friend_add_pressed.bind(user_id)
		var disabled := adding
		if adding:
			add_button_text = "Adding..."
		elif relation_state == FriendsController.FRIEND_STATE_FRIEND:
			add_button_text = "Added"
			disabled = true
			add_callback = Callable()
		elif relation_state == FriendsController.FRIEND_STATE_INVITE_SENT:
			add_button_text = "Pending"
			disabled = true
			add_callback = Callable()
		elif relation_state == FriendsController.FRIEND_STATE_INVITE_RECEIVED:
			add_button_text = "Accept"
			disabled = request_action_busy
			add_callback = _on_friend_request_accept_pressed.bind(user_id)

		var add_btn := _make_pixel_button(add_button_text, Vector2(92, 34), 15, add_callback)
		add_btn.disabled = disabled
		row.add_child(add_btn)

	_schedule_friends_panel_fit()


func _on_friend_add_pressed(user_id: String) -> void:
	if user_id.is_empty() or _friend_lookup_add_inflight.has(user_id):
		return

	_friend_lookup_add_inflight[user_id] = true
	_render_friend_lookup_results()
	_set_friend_lookup_status("Sending friend request...")

	var result = await OnlineSession.client.add_friends_async(OnlineSession.session, [user_id], null)
	_friend_lookup_add_inflight.erase(user_id)

	if result == null or result.is_exception():
		var message := "Could not add friend."
		if result != null and result.is_exception():
			var error_text := str(result.get_exception().message).strip_edges()
			if not error_text.is_empty():
				message = error_text
		_set_friend_lookup_status(message, true)
		_render_friend_lookup_results()
		return

	_friend_lookup_results_data.clear()
	_friend_lookup_add_inflight.clear()
	_render_friend_lookup_results()
	_clear_friend_lookup_status()
	_set_friend_lookup_mode(false)
	await _friends_ctrl.load_friends()
	_render_friends()


func _sync_friend_lookup_results() -> void:
	if _friend_lookup_results_data.is_empty():
		return
	var changed := false
	for i in range(_friend_lookup_results_data.size()):
		var entry_variant: Variant = _friend_lookup_results_data[i]
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var user_id := str(entry.get("user_id", "")).strip_edges()
		if user_id.is_empty():
			continue
		var relation_state := _friends_ctrl.state_for(user_id)
		if int(entry.get("relation_state", FriendsController.FRIEND_STATE_NONE)) != relation_state:
			changed = true
		entry["relation_state"] = relation_state
		var already := relation_state == FriendsController.FRIEND_STATE_FRIEND
		if bool(entry.get("already_friend", false)) != already:
			changed = true
		entry["already_friend"] = already
		_friend_lookup_results_data[i] = entry
	if changed:
		_render_friend_lookup_results()


func _set_friend_lookup_status(text: String, is_error: bool = false, is_success: bool = false) -> void:
	_friend_lookup_status.text = text
	_friend_lookup_status.visible = not text.is_empty()
	var color := COLOR_TEXT_DARK
	if is_error:
		color = COLOR_STATUS_ERROR
	elif is_success:
		color = COLOR_STATUS_OK
	_friend_lookup_status.add_theme_color_override("font_color", color)
	_schedule_friends_panel_fit()


func _clear_friend_lookup_status() -> void:
	_friend_lookup_status.text = ""
	_friend_lookup_status.visible = false
	_schedule_friends_panel_fit()


func _on_single_player_pressed() -> void:
	await _open_single_player_dialog()


func open_campaign_screen() -> void:
	_on_single_player_pressed.call_deferred()


func _on_credits_pressed() -> void:
	if is_instance_valid(_credits_panel):
		return
	_set_main_menu_content_visible(false)
	_credits_panel = CreditsScene.instantiate()
	if _credits_panel == null:
		_set_main_menu_content_visible(true)
		return
	_credits_panel.tree_exited.connect(func():
		_credits_panel = null
		_set_main_menu_content_visible(true)
	)
	add_child(_credits_panel)


func _on_options_pressed() -> void:
	if is_instance_valid(_options_panel):
		return
	_options_panel = OptionsPanel.instantiate()
	_options_panel.tree_exited.connect(func(): _options_panel = null)
	add_child(_options_panel)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_discord_pressed() -> void:
	OS.shell_open(DISCORD_INVITE_URL)


func _on_logout_pressed() -> void:
	logout_requested.emit()


func _open_single_player_dialog() -> void:
	_single_player_dialog_open = true
	_set_main_menu_content_visible(false)
	_open_dialog("Campaign")
	_dialog_title.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	_dialog_overlay.color = Color(Palette.DARKEST, 0)
	if _campaign_ctrl.own_levels.is_empty():
		await _campaign_ctrl.load_own_levels()
	_open_dialog("Campaign")
	_dialog_title.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	_dialog_overlay.color = Color(Palette.DARKEST, 0)

	if _campaign_ctrl.own_levels.is_empty():
		_add_dialog_text("No personal levels yet.")
		_dialog_body.add_child(_make_pixel_button("Open Level Creator", DIALOG_BUTTON_SIZE, 18, func():
			_close_dialog()
			create_level_requested.emit()
		))
		return

	for entry in _campaign_ctrl.own_levels:
		var key := LevelData.level_key(entry)
		var owner_id := str(entry.get("user_id", ""))
		var published := LevelData.is_published(entry)
		var display_name := LevelData.display_level_name(entry) + (" [published]" if published else "")

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_dialog_body.add_child(row)

		var name_label := Label.new()
		name_label.text = display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.theme_type_variation = &"LargeLabel"
		name_label.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
		row.add_child(name_label)

		row.add_child(_make_pixel_button("Play", ACTION_BUTTON_SIZE, 18, _on_dialog_play.bind(key, owner_id, "campaign")))


func _open_community_dialog() -> void:
	_open_dialog("Community Levels")

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	_dialog_body.add_child(filter_row)

	var filter_labels := ["Friends", "Top Rated", "Newest"]
	var filter_keys := ["friends", "top_rated", "newest"]
	var filter_btns: Array = []
	for lbl in filter_labels:
		var btn := _make_pixel_button(lbl, Vector2(150, 38), 16)
		filter_row.add_child(btn)
		filter_btns.append(btn)

	for btn in filter_btns:
		btn.modulate = Palette.DIMMED
	filter_btns[2].modulate = Color.WHITE

	var level_list := VBoxContainer.new()
	level_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_list.add_theme_constant_override("separation", 6)
	_dialog_body.add_child(level_list)

	var loading_lbl := Label.new()
	loading_lbl.text = "Loading levels..."
	loading_lbl.theme_type_variation = &"HeadingLabel"
	level_list.add_child(loading_lbl)

	var community_entries: Array = await _campaign_ctrl.load_all_community_levels(_friends_ctrl.name_by_id)

	if not is_instance_valid(level_list):
		return

	for i in range(filter_btns.size()):
		var btn: Button = filter_btns[i]
		var fkey: String = filter_keys[i]
		btn.pressed.connect(func():
			for b in filter_btns:
				b.modulate = Palette.DIMMED
			btn.modulate = Color.WHITE
			_populate_community_list(level_list, community_entries, fkey)
		)

	_populate_community_list(level_list, community_entries, "newest")


func _populate_community_list(level_list: VBoxContainer, entries: Array, filter: String) -> void:
	_community_filter_seq += 1
	var seq := _community_filter_seq

	for child in level_list.get_children():
		child.queue_free()

	if entries.is_empty():
		var empty := Label.new()
		if filter == "friends" and _friends_ctrl.count_by_state(FriendsController.FRIEND_STATE_FRIEND) == 0:
			empty.text = "No friends found.\nAdd friends in Nakama to browse their levels."
		else:
			empty.text = "No community levels yet."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.theme_type_variation = &"HeadingLabel"
		level_list.add_child(empty)
		return

	match filter:
		"friends":
			var sorted := entries.duplicate()
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var owner_cmp := str(a.get("owner_name", "")).nocasecmp_to(str(b.get("owner_name", "")))
				if owner_cmp == 0:
					return LevelData.display_level_name(a).nocasecmp_to(LevelData.display_level_name(b)) < 0
				return owner_cmp < 0
			)
			_render_community_entries(level_list, sorted)
		"newest":
			var sorted := entries.duplicate()
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return LevelData.entry_updated_at(a) > LevelData.entry_updated_at(b)
			)
			_render_community_entries(level_list, sorted)
		"top_rated":
			_populate_top_rated(level_list, entries, seq)


func _populate_top_rated(level_list: VBoxContainer, entries: Array, seq: int) -> void:
	var loading := Label.new()
	loading.text = "Fetching rankings..."
	loading.theme_type_variation = &"HeadingLabel"
	level_list.add_child(loading)

	# NOTE: fires one sequential RPC per community level to fetch its leaderboard.
	# This is fine for a small dataset but will be slow at scale. A production
	# game would use a dedicated server-side aggregation RPC or pre-computed rankings.
	var scored: Array = []
	for entry in entries:
		var owner_id := str(entry.get("user_id", ""))
		var level_key := LevelData.level_key(entry)
		var payload := JSON.stringify({
			"level_owner_id": owner_id,
			"level_key": level_key,
			"filter": "all_time",
		})
		var result = await OnlineSession.call_rpc("get_leaderboard", payload)
		var count := 0
		if result and result.get("entries") != null:
			count = (result["entries"] as Array).size()
		var scored_entry: Dictionary = entry.duplicate()
		scored_entry["_play_count"] = count
		scored.append(scored_entry)

	if not is_instance_valid(level_list) or seq != _community_filter_seq:
		return

	for child in level_list.get_children():
		child.queue_free()

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("_play_count", 0)) > int(b.get("_play_count", 0))
	)
	_render_community_entries(level_list, scored, true)


func _render_community_entries(level_list: VBoxContainer, entries: Array, show_count: bool = false) -> void:
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No community levels yet."
		empty.theme_type_variation = &"HeadingLabel"
		level_list.add_child(empty)
		return

	for entry in entries:
		var key := LevelData.level_key(entry)
		var owner_id := str(entry.get("user_id", ""))
		var owner_name := str(entry.get("owner_name", owner_id))
		var level_name := LevelData.display_level_name(entry)

		var label_text := "%s  —  %s" % [level_name, owner_name]
		if show_count:
			var count := int(entry.get("_play_count", 0))
			label_text += "  (%d play%s)" % [count, "" if count == 1 else "s"]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		level_list.add_child(row)

		var name_label := Label.new()
		name_label.text = label_text
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.theme_type_variation = &"HeadingLabel"
		row.add_child(name_label)

		row.add_child(_make_pixel_button("Play", ACTION_BUTTON_SIZE, 18, _on_dialog_play.bind(key, owner_id, "community")))


func get_campaign_next_level(current_key: String, current_owner_id: String) -> Dictionary:
	return _campaign_ctrl.get_campaign_next_level(current_key, current_owner_id)


func _on_dialog_play(key: String, owner_id: String, source: String = "") -> void:
	_close_dialog()
	play_level_requested.emit(key, owner_id, source)


func _on_dialog_edit(key: String, owner_id: String) -> void:
	_close_dialog()
	edit_level_requested.emit(key, owner_id)


func _on_dialog_delete(key: String, level_name: String) -> void:
	_open_dialog("Delete Level?")
	_add_dialog_text("Delete \"%s\"?\nThis cannot be undone." % level_name)

	var btn_row := HBoxContainer.new()
	btn_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	_dialog_body.add_child(btn_row)

	btn_row.add_child(_make_pixel_button("Delete", DIALOG_BUTTON_SIZE, 20, func():
		await _confirm_delete(key)
	))
	btn_row.add_child(_make_pixel_button("Cancel", DIALOG_BUTTON_SIZE, 20, func():
		await _open_single_player_dialog()
	))


func _confirm_delete(key: String) -> void:
	_open_dialog("Delete Level?")
	_add_dialog_text("Deleting...")

	var result = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": key}))

	if result == null:
		_open_dialog("Delete Level?")
		_add_dialog_text("Failed to delete level.")
		_dialog_body.add_child(_make_pixel_button("Back", DIALOG_BUTTON_SIZE, 20, func():
			await _open_single_player_dialog()
		))
		return

	_campaign_ctrl.own_levels = _campaign_ctrl.own_levels.filter(func(e: Dictionary) -> bool:
		return LevelData.level_key(e) != key
	)
	await _open_single_player_dialog()


func _update_login_label(label: Label) -> void:
	if OnlineSession.session == null:
		label.text = "Logged in as\nloading..."
		_schedule_friends_panel_fit()
		return
	var username := str(OnlineSession.session.username).strip_edges()
	if username.is_empty():
		username = str(OnlineSession.session.user_id).left(8)
	label.text = "Logged in as\n%s" % username
	_schedule_friends_panel_fit()


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _open_dialog(title: String) -> void:
	_dialog_title.text = title
	_dialog_title.add_theme_color_override("font_color", COLOR_TEXT_DARK)
	_clear_dialog_body()
	_dialog_overlay.visible = true
	_dialog_overlay.color = COLOR_DIALOG_OVERLAY
	if _dialog_close_btn:
		_dialog_close_btn.visible = true
		_layout_dialog_close_button()


func _close_dialog() -> void:
	_dialog_overlay.visible = false
	if _dialog_close_btn:
		_dialog_close_btn.visible = false
	if _single_player_dialog_open:
		_single_player_dialog_open = false
		_set_main_menu_content_visible(true)
	_clear_dialog_body()


func _clear_dialog_body() -> void:
	for child in _dialog_body.get_children():
		child.queue_free()


func _set_main_menu_content_visible(show_content: bool) -> void:
	if _main_margin:
		_main_margin.visible = show_content


func _add_dialog_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = &"LargeLabel"
	_dialog_body.add_child(label)


func _make_button_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 10
	style.texture_margin_top = 10
	style.texture_margin_right = 10
	style.texture_margin_bottom = 10
	style.draw_center = true
	return style


func _make_scroll_style(texture: Texture2D, margin: int = 2) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.draw_center = true
	return style


func _apply_friends_scrollbar_theme() -> void:
	if not _ui_root:
		return
	for node in _ui_root.find_children("", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if scroll == null:
			continue
		_apply_scrollbar_theme(scroll)


func _apply_scrollbar_theme(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var v_scroll := scroll.get_v_scroll_bar()
	if not v_scroll:
		pass
	else:
		var min_size_v := v_scroll.custom_minimum_size
		min_size_v.x = 12
		v_scroll.custom_minimum_size = min_size_v
		v_scroll.add_theme_stylebox_override("scroll", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("scroll_focus", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber_highlight", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber_pressed", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))

	var h_scroll := scroll.get_h_scroll_bar()
	if not h_scroll:
		return
	var min_size_h := h_scroll.custom_minimum_size
	min_size_h.y = 12
	h_scroll.custom_minimum_size = min_size_h
	h_scroll.add_theme_stylebox_override("scroll", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
	h_scroll.add_theme_stylebox_override("scroll_focus", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
	h_scroll.add_theme_stylebox_override("grabber", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
	h_scroll.add_theme_stylebox_override("grabber_highlight", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
	h_scroll.add_theme_stylebox_override("grabber_pressed", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))


func _make_pixel_button(text: String, min_size: Vector2, font_size: int, callback: Callable = Callable()) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", _make_button_style(GUI_BUTTON_NORMAL_TEXTURE))
	button.add_theme_stylebox_override("hover", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("pressed", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("focus", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	button.pressed.connect(func(): AudioManager.play("click"))
	if callback.is_valid():
		button.pressed.connect(callback)
	return button
