extends CanvasLayer

signal back_requested
signal play_requested(key: String, owner_id: String)

const SPINNER_SCENE: PackedScene = preload("res://scenes/spinner_animation.tscn")
const SCROLLBAR_BG_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_bg.tres")
const SCROLLBAR_HANDLE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_handle.tres")

const MENU_DESIGN_SIZE := Vector2(1280, 720)

var _ctrl := CommunityLevelsController.new()
var _builder := LevelCardBuilder.new()

var _selected_index: int = -1
var _selected_level_key: String = ""
var _selected_owner_id: String = ""
var _own_user_id: String = ""
var _leaderboard_filter: String = "all_time"
var _lb_seq: int = 0
var _fetch_seq: int = 0
var _level_cards: Array[Control] = []
var _lb_filter_btns: Array[Button] = []
var _list_filter_btns: Array[Button] = []
var _card_stat_labels_by_id: Dictionary = {}

@onready var _ui_root: Control = %UiRoot
@onready var _levels_container: VBoxContainer = %LevelsContainer
@onready var _leaderboard_list: VBoxContainer = %LeaderboardList
@onready var _lb_header_label: Label = %LbHeaderLabel
@onready var _play_btn: Button = %PlayBtn
@onready var _list_filter_friends_btn: Button = %ListFilterFriends
@onready var _list_filter_best_score_btn: Button = %ListFilterBestScore
@onready var _list_filter_newest_btn: Button = %ListFilterNewest


func _ready() -> void:
	%BackBtn.pressed.connect(func(): back_requested.emit())
	_play_btn.pressed.connect(_on_play_pressed)
	_lb_header_label.theme_type_variation = &"LightLabel"

	_list_filter_btns = [_list_filter_newest_btn, _list_filter_friends_btn, _list_filter_best_score_btn]
	var list_filter_keys: Array[String] = [
		CommunityLevelsController.LIST_FILTER_NEWEST,
		CommunityLevelsController.LIST_FILTER_FRIENDS,
		CommunityLevelsController.LIST_FILTER_BEST_SCORE,
	]
	for i in range(_list_filter_btns.size()):
		var btn := _list_filter_btns[i]
		var filter_key := list_filter_keys[i]
		btn.pressed.connect(func():
			_on_list_filter_pressed(filter_key, btn)
		)

	_lb_filter_btns = [%FilterAllTime, %FilterThisWeek, %FilterFriends]
	var filter_keys: Array[String] = ["all_time", "this_week", "friends"]
	for i in range(_lb_filter_btns.size()):
		var btn := _lb_filter_btns[i]
		var fkey := filter_keys[i]
		btn.pressed.connect(func():
			_leaderboard_filter = fkey
			_set_active_lb_filter(btn)
			_refresh_leaderboard()
		)

	var all_btns: Array[Button] = [%BackBtn, _play_btn]
	for b in _list_filter_btns:
		all_btns.append(b)
	for b in _lb_filter_btns:
		all_btns.append(b)
	for btn in all_btns:
		btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
		btn.pressed.connect(func(): AudioManager.play("click"))

	_ctrl.entries_ready.connect(_on_entries_ready)
	_ctrl.stats_updated.connect(_on_stats_updated)

	_apply_scrollbar_theme_to_all(_ui_root)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func open() -> void:
	_selected_index = -1
	_selected_level_key = ""
	_selected_owner_id = ""
	_card_stat_labels_by_id.clear()
	_ctrl.list_filter = CommunityLevelsController.LIST_FILTER_NEWEST
	_set_active_list_filter(_list_filter_newest_btn)
	_level_cards.clear()
	_show_level_list_spinner()
	_lb_header_label.text = "Leaderboards"
	_set_lb_message("Loading community levels...")
	_play_btn.disabled = true
	_fetch_seq += 1
	_ctrl.reset()
	_ctrl.load_entries()


func _on_entries_ready() -> void:
	if not is_instance_valid(self):
		return
	if _ctrl.entries.is_empty():
		_set_lb_message("No community levels found.")
	_rebuild_level_list()
	_restore_selection()
	_play_btn.disabled = _selected_index < 0
	_ctrl.queue_missing_stats()


func _on_stats_updated(identity: String) -> void:
	if not is_instance_valid(self):
		return
	_apply_stats_to_card_by_id(identity)


func _on_resize() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x > 0 and vp.y > 0:
		var sc := minf(vp.x / MENU_DESIGN_SIZE.x, vp.y / MENU_DESIGN_SIZE.y)
		_ui_root.scale = Vector2.ONE * sc
		_ui_root.position = (vp - MENU_DESIGN_SIZE * sc) * 0.5


func _show_level_list_spinner() -> void:
	_clear_children(_levels_container)
	_play_btn.disabled = true

	var spinner_row := CenterContainer.new()
	spinner_row.name = "ListLoading"
	spinner_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinner_row.custom_minimum_size = Vector2(0, 220)
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

	_levels_container.add_child(spinner_row)


func _rebuild_level_list() -> void:
	_clear_children(_levels_container)
	_level_cards.clear()
	_card_stat_labels_by_id.clear()
	if _ctrl.entries.is_empty():
		var lbl := Label.new()
		if _ctrl.friends.is_empty():
			lbl.text = "No friends found.\nAdd friends to see their levels here."
		else:
			lbl.text = "No community levels yet."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.theme_type_variation = &"HeadingLabel"
		_levels_container.add_child(lbl)
		return
	for i in range(_ctrl.entries.size()):
		var entry := _ctrl.entries[i] as Dictionary
		var identity := _ctrl.entry_identity(entry)
		var result := _builder.make_level_card(entry, i, identity, _select_level)
		var card := result["card"] as Button
		_levels_container.add_child(card)
		_level_cards.append(card)
		_card_stat_labels_by_id[identity] = result["labels"]
		_apply_stats_to_card(entry)


func _select_level(idx: int) -> void:
	_selected_index = idx
	if _selected_index >= 0 and _selected_index < _ctrl.entries.size():
		var selected_entry: Dictionary = _ctrl.entries[_selected_index]
		_selected_owner_id = str(selected_entry.get("user_id", ""))
		_selected_level_key = LevelData.level_key(selected_entry)
	for i in range(_level_cards.size()):
		_level_cards[i].modulate = Color.WHITE if i == idx else Palette.DIMMED
	_play_btn.disabled = false
	_refresh_leaderboard()


func _set_lb_message(msg: String) -> void:
	_clear_children(_leaderboard_list)
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.theme_type_variation = &"LightLabel"
	_leaderboard_list.add_child(lbl)


func _refresh_leaderboard() -> void:
	if _selected_index < 0 or _selected_index >= _ctrl.entries.size():
		_lb_header_label.text = "Leaderboards"
		_set_lb_message("Select a level to view its leaderboard.")
		return
	_lb_seq += 1
	var seq := _lb_seq
	var entry: Dictionary = _ctrl.entries[_selected_index]
	var owner_id := str(entry.get("user_id", ""))
	var key := LevelData.level_key(entry)
	_lb_header_label.text = LevelData.level_key(entry)
	_set_lb_message("Loading...")
	var payload := JSON.stringify({
		"level_owner_id": owner_id,
		"level_key": key,
		"filter": _leaderboard_filter,
	})
	var result = await OnlineSession.call_rpc("get_leaderboard", payload)
	if not is_instance_valid(self) or seq != _lb_seq:
		return
	_render_leaderboard(result)


func _render_leaderboard(result: Variant) -> void:
	_clear_children(_leaderboard_list)
	if not (result is Dictionary):
		_set_lb_message("No scores yet.")
		return
	var entries: Array = result.get("entries", [])
	if entries.is_empty():
		_set_lb_message("No scores yet.")
		return
	var player_rank := int(result.get("player_rank", 0))
	for entry in entries:
		var rank := int(entry.get("rank", 0))
		var username := str(entry.get("username", "?"))
		var time_ms := int(entry.get("time_ms", 0))
		var slides := int(entry.get("slide_count", 0))
		var is_player := player_rank > 0 and rank == player_rank

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		if is_player:
			row.modulate = Palette.HIGHLIGHT_ROW

		var rank_lbl := Label.new()
		rank_lbl.text = "%d" % rank
		rank_lbl.custom_minimum_size.x = 26
		rank_lbl.theme_type_variation = &"LightLabel"
		row.add_child(rank_lbl)

		var name_lbl := Label.new()
		name_lbl.text = username + (" (You!)" if is_player else "")
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.theme_type_variation = &"LightLabel"
		row.add_child(name_lbl)

		var time_lbl := Label.new()
		time_lbl.text = "%.2fs" % (time_ms / 1000.0)
		time_lbl.theme_type_variation = &"LightLabel"
		row.add_child(time_lbl)

		var slide_lbl := Label.new()
		slide_lbl.text = "%dsl" % slides
		slide_lbl.custom_minimum_size.x = 34
		slide_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slide_lbl.theme_type_variation = &"LightLabel"
		row.add_child(slide_lbl)

		_leaderboard_list.add_child(row)


func _on_play_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _ctrl.entries.size():
		return
	var entry: Dictionary = _ctrl.entries[_selected_index]
	play_requested.emit(LevelData.level_key(entry), str(entry.get("user_id", "")))


func _set_active_lb_filter(active_btn: Button) -> void:
	for btn in _lb_filter_btns:
		btn.modulate = Color.WHITE if btn == active_btn else Palette.INACTIVE


func _on_list_filter_pressed(filter_key: String, btn: Button) -> void:
	_ctrl.list_filter = filter_key
	_set_active_list_filter(btn)
	if filter_key == CommunityLevelsController.LIST_FILTER_NEWEST \
			or filter_key == CommunityLevelsController.LIST_FILTER_FRIENDS:
		_set_lb_message("Loading community levels...")
		_fetch_seq += 1
		_ctrl.reset()
		_ctrl.load_entries()
		return
	_ctrl.apply_filter()
	_rebuild_level_list()
	_restore_selection()
	_play_btn.disabled = _selected_index < 0
	_ctrl.queue_missing_stats()


func _set_active_list_filter(active_btn: Button) -> void:
	for btn in _list_filter_btns:
		btn.modulate = Color.WHITE if btn == active_btn else Palette.INACTIVE


func _restore_selection() -> void:
	if _ctrl.entries.is_empty():
		_selected_index = -1
		_selected_owner_id = ""
		_selected_level_key = ""
		return

	if not _selected_owner_id.is_empty() and not _selected_level_key.is_empty():
		for i in range(_ctrl.entries.size()):
			var entry: Dictionary = _ctrl.entries[i]
			if str(entry.get("user_id", "")) != _selected_owner_id:
				continue
			if LevelData.level_key(entry) != _selected_level_key:
				continue
			_select_level(i)
			return

	_select_level(0)


func _apply_stats_to_card_by_id(identity: String) -> void:
	for entry_variant in _ctrl.entries:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		if _ctrl.entry_identity(entry) != identity:
			continue
		_apply_stats_to_card(entry)
		return


func _apply_stats_to_card(entry: Dictionary) -> void:
	var identity := _ctrl.entry_identity(entry)
	if identity.is_empty():
		return
	var labels_variant: Variant = _card_stat_labels_by_id.get(identity, null)
	if not (labels_variant is Dictionary):
		return

	var labels := labels_variant as Dictionary
	var ranking_lbl := labels.get("ranking", null) as Label
	var steps_lbl := labels.get("steps", null) as Label
	var time_lbl := labels.get("time", null) as Label
	var played_lbl := labels.get("played", null) as Label
	if ranking_lbl == null or steps_lbl == null or time_lbl == null or played_lbl == null:
		return

	var rank := int(_ctrl.vote_rank_by_id.get(identity, 0))
	var rating := _ctrl.entry_vote_rating(entry)
	var total_votes := _ctrl.entry_total_votes(entry)
	var rank_text := "-" if rank <= 0 else "#%d" % rank
	ranking_lbl.text = "Rank: %s  Rating: %.1f/5 (%d votes)" % [rank_text, rating, total_votes]

	var stats_variant: Variant = _ctrl.entry_stats_by_id.get(identity, _ctrl.default_stats())
	var stats: Dictionary = _ctrl.default_stats()
	if stats_variant is Dictionary:
		stats = stats_variant as Dictionary

	var best_steps := maxi(0, int(stats.get("best_slide_count", 0)))
	var best_time_ms := maxi(0, int(stats.get("best_time_ms", 0)))
	var play_count := maxi(0, int(stats.get("play_count", 0)))

	steps_lbl.text = "Best steps: %s" % ("--" if best_steps <= 0 else str(best_steps))
	time_lbl.text = "Best time: %s" % _builder.format_card_time(best_time_ms)
	played_lbl.text = "Played: %d" % play_count


func _make_scroll_style(texture: Texture2D, margin: int = 2) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.draw_center = true
	return style


func _apply_scrollbar_theme_to_all(root: Node) -> void:
	if root == null:
		return
	for node in root.find_children("", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if scroll == null:
			continue
		_apply_scrollbar_theme(scroll)


func _apply_scrollbar_theme(scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	var v_scroll := scroll.get_v_scroll_bar()
	if v_scroll:
		var min_size_v := v_scroll.custom_minimum_size
		min_size_v.x = 12
		v_scroll.custom_minimum_size = min_size_v
		v_scroll.add_theme_stylebox_override("scroll", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("scroll_focus", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber_highlight", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		v_scroll.add_theme_stylebox_override("grabber_pressed", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))

	var h_scroll := scroll.get_h_scroll_bar()
	if h_scroll:
		var min_size_h := h_scroll.custom_minimum_size
		min_size_h.y = 12
		h_scroll.custom_minimum_size = min_size_h
		h_scroll.add_theme_stylebox_override("scroll", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("scroll_focus", _make_scroll_style(SCROLLBAR_BG_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("grabber", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("grabber_highlight", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))
		h_scroll.add_theme_stylebox_override("grabber_pressed", _make_scroll_style(SCROLLBAR_HANDLE_TEXTURE, 2))


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
