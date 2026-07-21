extends Node2D

const CANVAS_LAYER_VISIBILITY_META := "__screen_visible_before_hide"

const MyLevelsScene = preload("res://my_levels/my_levels.tscn")
const CommunityLevelsScene = preload("res://community_levels/community_levels.tscn")

@export var use_local_server: bool = false

@onready var _level_creator: LevelCreator = $LevelCreator
@onready var _level_player: LevelPlayer = $LevelPlayer
@onready var _level_complete_modal: LevelCompleteModal = $LevelCompleteModal
@onready var _level_testing_complete: LevelTestingComplete = $LevelTestingComplete
@onready var _main_menu: MainMenu = $MainMenu
@onready var _custom_account_entry = $CustomAccountEntry
@onready var _custom_account_gate = $CustomAccountGate
@onready var _custom_account_login = $CustomAccountLogin

var _my_levels: CanvasLayer
var _community_levels: CanvasLayer
var _nav := NavigationController.new()
var _current_play_source: String = ""
var _campaign_next_level_key: String = ""
var _campaign_next_level_owner_id: String = ""
var _campaign_has_next_level := false
var _show_level_testing_complete := false


func _ready() -> void:
	OnlineSession.start(use_local_server)

	var vw := LevelConfig.GRID_ORIGIN.x + LevelConfig.PUZZLE_SIZE + LevelConfig.UI_PANEL_GAP + LevelConfig.UI_PANEL_WIDTH + LevelConfig.RIGHT_MARGIN
	var vh := LevelConfig.GRID_ORIGIN.y + LevelConfig.PUZZLE_SIZE + LevelConfig.BOTTOM_MARGIN
	get_window().size = Vector2i(int(vw), int(vh))
	if OS.has_feature("web"):
		_force_web_viewport_resize.call_deferred()

	_set_screen_active(_level_creator, false)
	_set_screen_active(_level_player, false)
	_set_screen_active(_level_complete_modal, false)
	_set_screen_active(_level_testing_complete, false)

	_my_levels = MyLevelsScene.instantiate()
	_my_levels.visible = false
	add_child(_my_levels)
	_my_levels.back_requested.connect(_on_my_levels_back)
	_my_levels.new_level_requested.connect(_on_create_level)
	_my_levels.play_requested.connect(func(key: String, owner_id: String): _on_play_level(key, owner_id, "my_levels"))
	_my_levels.edit_requested.connect(_on_edit_level)

	_community_levels = CommunityLevelsScene.instantiate()
	_community_levels.visible = false
	add_child(_community_levels)
	_community_levels.back_requested.connect(_on_community_levels_back)
	_community_levels.play_requested.connect(func(key: String, owner_id: String): _on_play_level(key, owner_id, "community"))
	_main_menu.create_level_requested.connect(_on_create_level)
	_main_menu.play_level_requested.connect(_on_play_level)
	_main_menu.edit_level_requested.connect(_on_edit_level)
	_main_menu.my_levels_requested.connect(_on_open_my_levels)
	_main_menu.community_levels_requested.connect(_on_open_community_levels)
	_main_menu.logout_requested.connect(_on_main_menu_logout_requested)
	_level_creator.play_requested.connect(func(key: String, owner_id: String): _on_play_level(key, owner_id, "creator"))

	_level_player.main_menu_requested.connect(_on_return_to_menu)
	_level_player.edit_level_requested.connect(_on_edit_from_player)
	_level_player.level_completed.connect(_on_level_completed)
	_level_creator.main_menu_requested.connect(_on_return_to_menu)
	_level_complete_modal.main_menu_requested.connect(_on_level_complete_main_menu)
	_level_complete_modal.next_level_requested.connect(_on_next_level)
	_level_testing_complete.main_menu_requested.connect(_on_level_complete_main_menu)
	_level_testing_complete.edit_requested.connect(_on_edit_from_testing_complete)
	_level_testing_complete.save_requested.connect(_on_save_from_testing_complete)
	_level_testing_complete.publish_requested.connect(_on_publish_from_testing_complete)
	_custom_account_entry.login_requested.connect(_on_custom_account_login_requested)
	_custom_account_entry.create_requested.connect(_on_custom_account_create_requested)
	_custom_account_gate.setup_completed.connect(_on_custom_account_gate_completed)
	_custom_account_login.login_completed.connect(_on_custom_account_login_completed)
	_custom_account_login.create_account_requested.connect(_on_custom_account_create_requested)

	_nav.set_root(NavigationController.Screen.MENU)
	_show_auth_entry_as_default()
	await _enforce_custom_account_gate()


func _force_web_viewport_resize() -> void:
	# Godot web has a race: the canvas is sized to window.innerWidth/innerHeight
	# during engine init, but the viewport callback isn't registered yet, so the
	# internal viewport misses the notification. By the time _ready() runs the
	# callback IS registered, but updateSize() returns 0 (canvas already correct).
	# Bumping canvas.width by 1 forces updateSize() to detect a mismatch on the
	# next frame, resize back, and notify the viewport.
	JavaScriptBridge.eval("var c=document.getElementById('canvas');if(c)c.width++")


func _enforce_custom_account_gate() -> void:
	var needs_gate := await AuthFlow.needs_custom_account_gate()
	if needs_gate:
		_show_auth_entry_as_default()
		return

	_set_screen_active(_custom_account_entry, false)
	_set_screen_active(_custom_account_login, false)
	_set_screen_active(_custom_account_gate, false)
	_nav.set_root(NavigationController.Screen.MENU)
	_apply_navigation()


func _show_auth_entry_as_default() -> void:
	_set_screen_active(_main_menu, false)
	_set_screen_active(_my_levels, false)
	_set_screen_active(_community_levels, false)
	_set_screen_active(_custom_account_entry, true)
	_set_screen_active(_custom_account_login, false)
	_set_screen_active(_custom_account_gate, false)


func _on_custom_account_gate_completed() -> void:
	_set_screen_active(_custom_account_entry, false)
	_set_screen_active(_custom_account_login, false)
	_set_screen_active(_custom_account_gate, false)
	_set_screen_active(_main_menu, true)
	_main_menu.refresh()


func _on_custom_account_login_requested() -> void:
	_set_screen_active(_custom_account_entry, false)
	_set_screen_active(_custom_account_gate, false)
	_custom_account_login.reset_form()
	_set_screen_active(_custom_account_login, true)


func _on_custom_account_create_requested() -> void:
	_set_screen_active(_custom_account_entry, false)
	_set_screen_active(_custom_account_login, false)
	_set_screen_active(_custom_account_gate, true)


func _on_custom_account_login_completed() -> void:
	_set_screen_active(_custom_account_entry, false)
	_set_screen_active(_custom_account_login, false)
	_set_screen_active(_custom_account_gate, false)
	_set_screen_active(_main_menu, true)
	_main_menu.refresh()


func _on_main_menu_logout_requested() -> void:
	_nav.set_root(NavigationController.Screen.MENU)
	_set_screen_active(_custom_account_gate, false)
	_set_screen_active(_custom_account_login, false)
	_set_screen_active(_main_menu, false)
	_set_screen_active(_custom_account_entry, true)


func _navigate_in(screen: int) -> void:
	_nav.push(screen)
	_apply_navigation()


func _navigate_out() -> void:
	_nav.pop()
	_apply_navigation()


func _set_navigation_root(screen: int) -> void:
	_nav.set_root(screen)
	_apply_navigation()


func _apply_navigation() -> void:
	var current := _nav.current()
	_set_screen_active(_main_menu, current == NavigationController.Screen.MENU)
	_set_screen_active(_my_levels, current == NavigationController.Screen.MY_LEVELS)
	_set_screen_active(_community_levels, current == NavigationController.Screen.COMMUNITY_LEVELS)
	_set_screen_active(_level_creator, current == NavigationController.Screen.CREATOR)
	_set_screen_active(_level_player, current == NavigationController.Screen.PLAYER)
	_set_screen_active(_level_complete_modal, current == NavigationController.Screen.LEVEL_COMPLETE and not _show_level_testing_complete)
	_set_screen_active(_level_testing_complete, current == NavigationController.Screen.LEVEL_COMPLETE and _show_level_testing_complete)


func _set_screen_active(node: Node, active: bool) -> void:
	if node is CanvasLayer:
		node.visible = active
	elif node is Node2D:
		(node as Node2D).visible = active
	_set_canvas_layers_visible(node, active)
	node.set_process(active)
	node.set_physics_process(active)
	node.set_process_input(active)
	node.set_process_unhandled_input(active)
	node.propagate_call("set_process", [active])
	node.propagate_call("set_physics_process", [active])
	node.propagate_call("set_process_input", [active])
	node.propagate_call("set_process_unhandled_input", [active])


func _set_canvas_layers_visible(node: Node, active: bool) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			var canvas_layer := child as CanvasLayer
			if active:
				if canvas_layer.has_meta(CANVAS_LAYER_VISIBILITY_META):
					var restored_visible := bool(canvas_layer.get_meta(CANVAS_LAYER_VISIBILITY_META))
					canvas_layer.visible = restored_visible
					canvas_layer.remove_meta(CANVAS_LAYER_VISIBILITY_META)
			else:
				# Preserve the original visibility only once so repeated hide calls
				# do not overwrite it with false.
				if not canvas_layer.has_meta(CANVAS_LAYER_VISIBILITY_META):
					canvas_layer.set_meta(CANVAS_LAYER_VISIBILITY_META, canvas_layer.visible)
				canvas_layer.visible = false
		_set_canvas_layers_visible(child, active)


func _on_create_level() -> void:
	_level_creator.start_new_level()
	_navigate_in(NavigationController.Screen.CREATOR)


func _on_play_level(key: String, owner_id: String, source: String = "") -> void:
	_open_player_level(key, owner_id, source, false)


func _open_player_level(key: String, owner_id: String, source: String = "", replace_current_screen: bool = false) -> void:
	_current_play_source = source
	_show_level_testing_complete = false
	_level_player.load_level(key, owner_id, source)
	if replace_current_screen:
		_nav.replace_top(NavigationController.Screen.PLAYER)
		_apply_navigation()
		return
	_navigate_in(NavigationController.Screen.PLAYER)


func _on_edit_level(key: String, owner_id: String) -> void:
	_level_creator.edit_level(key, owner_id)
	_navigate_in(NavigationController.Screen.CREATOR)


func _on_edit_from_player(key: String, owner_id: String) -> void:
	_level_creator.edit_level(key, owner_id)
	if _nav.current() == NavigationController.Screen.PLAYER:
		_nav.pop()
	if _nav.current() != NavigationController.Screen.CREATOR:
		_nav.push(NavigationController.Screen.CREATOR)
	_apply_navigation()


func _on_level_completed(level_key: String, owner_id: String, level_name: String, time_ms: int, slide_count: int, rank: int) -> void:
	_campaign_has_next_level = false
	_campaign_next_level_key = ""
	_campaign_next_level_owner_id = ""
	if _current_play_source == "campaign":
		var next_info: Dictionary = _main_menu.get_campaign_next_level(level_key, owner_id)
		_campaign_has_next_level = bool(next_info.get("has_next", false))
		if _campaign_has_next_level:
			_campaign_next_level_key = str(next_info.get("key", "")).strip_edges()
			_campaign_next_level_owner_id = str(next_info.get("owner_id", "")).strip_edges()
	_show_level_testing_complete = _current_play_source == "creator"
	if _show_level_testing_complete:
		_level_testing_complete.open_for_level(level_key, owner_id, level_name, time_ms, slide_count, rank)
	else:
		_level_complete_modal.set_next_level_available(_campaign_has_next_level)
		_level_complete_modal.open_for_level(level_key, owner_id, level_name, time_ms, slide_count, rank)
	_nav.replace_top(NavigationController.Screen.LEVEL_COMPLETE)
	_apply_navigation()


func _on_return_to_menu() -> void:
	_show_level_testing_complete = false
	var returning_from_creator_to_my_levels: bool = (
		_nav.size() >= 2
		and _nav.current() == NavigationController.Screen.CREATOR
		and _nav.peek_prev() == NavigationController.Screen.MY_LEVELS
	)
	_main_menu.refresh()
	_navigate_out()
	if returning_from_creator_to_my_levels:
		_my_levels.open()


func _on_level_complete_main_menu() -> void:
	match _current_play_source:
		"campaign":
			_main_menu.refresh()
			_set_navigation_root(NavigationController.Screen.MENU)
			_main_menu.open_campaign_screen.call_deferred()
		"community":
			_community_levels.open()
			_set_navigation_root(NavigationController.Screen.COMMUNITY_LEVELS)
		"creator", "my_levels":
			_my_levels.open()
			_set_navigation_root(NavigationController.Screen.MY_LEVELS)
		_:
			_main_menu.refresh()
			_set_navigation_root(NavigationController.Screen.MENU)


func _on_next_level() -> void:
	if _current_play_source == "campaign" and _campaign_has_next_level and not _campaign_next_level_key.is_empty():
		_open_player_level(_campaign_next_level_key, _campaign_next_level_owner_id, "campaign", true)
		return
	_main_menu.refresh()
	_navigate_out()


func _on_edit_from_testing_complete(key: String, owner_id: String) -> void:
	_show_level_testing_complete = false
	_level_creator.edit_level(key, owner_id)
	if _nav.current() == NavigationController.Screen.LEVEL_COMPLETE:
		_nav.pop()
	if _nav.current() != NavigationController.Screen.CREATOR:
		_nav.push(NavigationController.Screen.CREATOR)
	_apply_navigation()


func _on_save_from_testing_complete() -> void:
	_level_testing_complete.set_save_enabled(false)
	var save_error := await _level_creator.save_current_level()
	if not is_instance_valid(self):
		return
	_level_testing_complete.set_save_enabled(true)
	if save_error.is_empty():
		_level_testing_complete.show_action_status("Saved!", false)
	else:
		_level_testing_complete.show_action_status(save_error, true)


func _on_publish_from_testing_complete(level_key: String) -> void:
	var key := level_key.strip_edges()
	if key.is_empty():
		_level_testing_complete.show_action_status("Save level before publishing.", true)
		return
	_level_testing_complete.set_publish_enabled(false)
	var result: Variant = await OnlineSession.call_rpc("publish_level", JSON.stringify({"key": key}))
	if not is_instance_valid(self):
		return
	if result is Dictionary:
		_level_testing_complete.show_action_status("Level published.", false)
		_level_testing_complete.set_edit_enabled(false)
		return
	_level_testing_complete.set_publish_enabled(true)
	var rpc_error := OnlineSession.last_rpc_error.to_lower()
	if "not found" in rpc_error:
		_level_testing_complete.show_action_status("Level not found.", true)
		return
	if "published levels are read-only" in rpc_error:
		_level_testing_complete.show_action_status("Level is already published.", true)
		return
	_level_testing_complete.show_action_status("Could not publish level.", true)


func _on_open_my_levels() -> void:
	_my_levels.open()
	_navigate_in(NavigationController.Screen.MY_LEVELS)


func _on_open_community_levels() -> void:
	_community_levels.open()
	_navigate_in(NavigationController.Screen.COMMUNITY_LEVELS)


func _on_my_levels_back() -> void:
	if _nav.size() <= 1:
		_main_menu.refresh()
		_set_navigation_root(NavigationController.Screen.MENU)
		return
	_navigate_out()


func _on_community_levels_back() -> void:
	if _nav.size() <= 1:
		_main_menu.refresh()
		_set_navigation_root(NavigationController.Screen.MENU)
		return
	_navigate_out()
