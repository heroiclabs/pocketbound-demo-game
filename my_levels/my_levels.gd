extends CanvasLayer

signal back_requested
signal new_level_requested
signal play_requested(key: String, owner_id: String)
signal edit_requested(key: String, owner_id: String)

const GUI_BUTTON_NORMAL: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip.tres")
const GUI_BUTTON_ACTIVE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip_right.tres")
const GUI_WINDOW: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_window.tres")
const SCROLLBAR_BG_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_bg.tres")
const SCROLLBAR_HANDLE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_handle.tres")

const MENU_DESIGN_SIZE := Vector2(1280, 720)

var _levels: Array = []
var _selected_index: int = -1
var _own_user_id: String = ""
var _own_username: String = ""
var _leaderboard_filter: String = "all_time"
var _lb_seq: int = 0
var _level_cards: Array[Control] = []
var _lb_filter_btns: Array[Button] = []

@onready var _ui_root: Control = %UiRoot
@onready var _levels_container: VBoxContainer = %LevelsContainer
@onready var _leaderboard_list: VBoxContainer = %LeaderboardList
@onready var _lb_header_label: Label = %LbHeaderLabel
@onready var _test_btn: Button = %TestBtn
@onready var _edit_btn: Button = %EditBtn
@onready var _publish_btn: Button = %PublishBtn
@onready var _delete_btn: Button = %DeleteBtn


func _ready() -> void:
	%MenuBtn.pressed.connect(func(): back_requested.emit())
	%NewLevelBtn.pressed.connect(func(): new_level_requested.emit())
	_lb_header_label.theme_type_variation = &"LightLabel"
	_test_btn.pressed.connect(_on_test_pressed)
	_edit_btn.pressed.connect(_on_edit_pressed)
	_publish_btn.pressed.connect(_on_publish_pressed)
	_delete_btn.pressed.connect(_on_delete_pressed)

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

	var all_btns: Array[Button] = [%MenuBtn, %NewLevelBtn, _test_btn, _edit_btn, _publish_btn, _delete_btn]
	for b in _lb_filter_btns:
		all_btns.append(b)
	for btn in all_btns:
		btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
		btn.pressed.connect(func(): AudioManager.play("click"))

	_apply_scrollbar_theme_to_all(_ui_root)
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()


func open() -> void:
	_selected_index = -1
	_level_cards.clear()
	_clear_children(_levels_container)
	_lb_header_label.text = "Leaderboards"
	_set_lb_message("Loading levels...")
	_update_action_buttons()
	_fetch_own_levels()


func _on_resize() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x > 0 and vp.y > 0:
		var sc := minf(vp.x / MENU_DESIGN_SIZE.x, vp.y / MENU_DESIGN_SIZE.y)
		_ui_root.scale = Vector2.ONE * sc
		_ui_root.position = (vp - MENU_DESIGN_SIZE * sc) * 0.5


func _fetch_own_levels() -> void:
	if not OnlineSession.session:
		await OnlineSession.session_ready
	if OnlineSession.session:
		_own_user_id = str(OnlineSession.session.user_id)
		_own_username = str(OnlineSession.session.username)
	var result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	if not is_instance_valid(self):
		return
	_levels = _extract_levels(result)
	_rebuild_level_list()
	if not _levels.is_empty():
		_select_level(0)
	else:
		_lb_header_label.text = "Leaderboards"
		_set_lb_message("Select a level to view its leaderboard.")
	_update_action_buttons()


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


func _extract_levels(result: Variant) -> Array:
	var out: Array = []
	if result is Dictionary:
		for entry in result.get("levels", []):
			if entry is Dictionary:
				out.append(entry)
	return out


func _level_name(entry: Dictionary) -> String:
	var val: Variant = entry.get("value", {})
	if val is Dictionary:
		var n := str((val as Dictionary).get("name", "")).strip_edges()
		if not n.is_empty():
			return n
	return str(entry.get("key", ""))


func _level_key(entry: Dictionary) -> String:
	var val: Variant = entry.get("value", {})
	if val is Dictionary:
		var n := str((val as Dictionary).get("name", "")).strip_edges()
		if not n.is_empty():
			return n
	return str(entry.get("key", "")).strip_edges()


func _rebuild_level_list() -> void:
	_clear_children(_levels_container)
	_level_cards.clear()
	if _levels.is_empty():
		var lbl := Label.new()
		lbl.text = "No levels yet.\nClick 'New Level' to create one!"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.theme_type_variation = &"HeadingLabel"
		_levels_container.add_child(lbl)
		return
	for i in range(_levels.size()):
		var card := _make_level_card(_levels[i], i)
		_levels_container.add_child(card)
		_level_cards.append(card)


func _make_level_card(entry: Dictionary, idx: int) -> Control:
	var val: Dictionary = {}
	var val_v: Variant = entry.get("value", {})
	if val_v is Dictionary:
		val = val_v as Dictionary
	var level_name := _level_name(entry)

	var card := Button.new()
	card.flat = true
	card.custom_minimum_size = Vector2(0, 84)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	card.pressed.connect(func():
		AudioManager.play("click")
		_select_level(idx)
	)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.188, 0.384, 0.188, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var thumb := _make_thumbnail(val)
	row.add_child(thumb)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = level_name
	name_lbl.clip_text = true
	name_lbl.theme_type_variation = &"LightTitleLabel"
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_lbl)

	if not _own_username.is_empty():
		var by_lbl := Label.new()
		by_lbl.text = "By: %s" % _own_username
		by_lbl.theme_type_variation = &"SubLabel"
		by_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(by_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "Published" if _is_published(entry) else "Draft"
	status_lbl.theme_type_variation = &"SubLabel"
	if _is_published(entry):
		status_lbl.add_theme_color_override("font_color", Palette.LIGHT)
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(status_lbl)

	return card


func _make_thumbnail(val: Dictionary) -> Control:
	var thumb := Control.new()
	thumb.custom_minimum_size = Vector2(72, 72)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grid_size: int = maxi(int(val.get("grid_size", 5)), 1)
	var xs: Array = val.get("x", [])
	var ys: Array = val.get("y", [])
	var walkable_ids: Array = val.get("walkable", [])
	var start_ids: Array = val.get("start", [])
	var end_ids: Array = val.get("end", [])

	var walkable_set: Dictionary = {}
	for id in walkable_ids:
		walkable_set[int(id)] = true
	var start_set: Dictionary = {}
	for id in start_ids:
		start_set[int(id)] = true
	var end_set: Dictionary = {}
	for id in end_ids:
		end_set[int(id)] = true

	var cell_colors: Dictionary = {}
	for i in range(xs.size()):
		var cx := int(xs[i])
		var cy := int(ys[i])
		if cx < 0 or cy < 0 or cx >= grid_size or cy >= grid_size:
			continue
		var k := Vector2i(cx, cy)
		if start_set.has(i) or end_set.has(i):
			cell_colors[k] = Palette.LIGHTEST
		elif walkable_set.has(i):
			cell_colors[k] = Palette.LIGHT
		else:
			cell_colors[k] = Palette.DARK

	thumb.draw.connect(func():
		var sz := thumb.size
		if sz.x <= 0.0 or sz.y <= 0.0:
			return
		var cw := sz.x / float(grid_size)
		var ch := sz.y / float(grid_size)
		thumb.draw_rect(Rect2(Vector2.ZERO, sz), Palette.DARKEST)
		for pos in cell_colors:
			thumb.draw_rect(
				Rect2(pos.x * cw + 1.0, pos.y * ch + 1.0, cw - 2.0, ch - 2.0),
				cell_colors[pos]
			)
	)
	return thumb


func _select_level(idx: int) -> void:
	_selected_index = idx
	for i in range(_level_cards.size()):
		_level_cards[i].modulate = Color.WHITE if i == idx else Color(1.0, 1.0, 1.0, 0.45)
	_update_action_buttons()
	_refresh_leaderboard()


func _update_action_buttons() -> void:
	var has := _selected_index >= 0 and _selected_index < _levels.size()
	var published := false
	if has:
		published = _is_published(_levels[_selected_index])
	_test_btn.disabled = not has
	_edit_btn.disabled = not has or published
	_publish_btn.disabled = not has or published
	_delete_btn.disabled = not has


func _set_lb_message(msg: String) -> void:
	_clear_children(_leaderboard_list)
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.theme_type_variation = &"LightLabel"
	_leaderboard_list.add_child(lbl)


func _refresh_leaderboard() -> void:
	if _selected_index < 0 or _selected_index >= _levels.size():
		_lb_header_label.text = "Leaderboards"
		_set_lb_message("Select a level to view its leaderboard.")
		return
	_lb_seq += 1
	var seq := _lb_seq
	var entry: Dictionary = _levels[_selected_index]
	var owner_id := str(entry.get("user_id", ""))
	var key := _level_key(entry)
	_lb_header_label.text = _level_name(entry)
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
			row.modulate = Color(1.0, 1.0, 0.5)

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


func _on_test_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _levels.size():
		return
	var entry: Dictionary = _levels[_selected_index]
	play_requested.emit(_level_key(entry), str(entry.get("user_id", "")))


func _on_edit_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _levels.size():
		return
	var entry: Dictionary = _levels[_selected_index]
	if _is_published(entry):
		return
	edit_requested.emit(_level_key(entry), str(entry.get("user_id", "")))


func _on_publish_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _levels.size():
		return
	var entry: Dictionary = _levels[_selected_index]
	if _is_published(entry):
		return

	var key := _level_key(entry)
	if key.is_empty():
		_set_lb_message("Could not publish level.")
		return

	var result = await OnlineSession.call_rpc("publish_level", JSON.stringify({"key": key}))
	if not is_instance_valid(self):
		return
	if result == null:
		var rpc_error := OnlineSession.last_rpc_error.to_lower()
		if "level not found" in rpc_error:
			_set_lb_message("Level not found.")
			return
		_set_lb_message("Could not publish level.")
		return

	_set_lb_message("Level published.")
	_fetch_own_levels()


func _on_delete_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _levels.size():
		return
	var entry: Dictionary = _levels[_selected_index]
	_show_confirm_delete(_level_key(entry), _level_name(entry))


func _show_confirm_delete(key: String, level_name: String) -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(Palette.DARKEST, 0.88)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := NinePatchRect.new()
	panel.texture = GUI_WINDOW
	panel.patch_margin_left = 14
	panel.patch_margin_top = 14
	panel.patch_margin_right = 14
	panel.patch_margin_bottom = 14
	panel.custom_minimum_size = Vector2(420, 180)
	center.add_child(panel)

	var pm := MarginContainer.new()
	pm.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pm.add_theme_constant_override(s, 20)
	panel.add_child(pm)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	pm.add_child(col)

	var q := Label.new()
	q.text = 'Delete "%s"?\nThis cannot be undone.' % level_name
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.theme_type_variation = &"LargeLabel"
	col.add_child(q)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	col.add_child(btns)

	var del_btn := _make_pixel_button("Delete", Vector2(150, 42), 20, func():
		overlay.queue_free()
		_confirm_delete(key)
	)
	btns.add_child(del_btn)

	var cancel_btn := _make_pixel_button("Cancel", Vector2(150, 42), 20, func():
		overlay.queue_free()
	)
	btns.add_child(cancel_btn)


func _confirm_delete(key: String) -> void:
	var result = await OnlineSession.call_rpc("delete_level", JSON.stringify({"key": key}))
	if not is_instance_valid(self):
		return
	if result == null:
		return
	_levels = _levels.filter(func(e: Dictionary) -> bool:
		return _level_key(e) != key
	)
	_selected_index = -1
	_rebuild_level_list()
	if not _levels.is_empty():
		_select_level(0)
	else:
		_lb_header_label.text = "Leaderboards"
		_set_lb_message("Select a level to view its leaderboard.")
		_update_action_buttons()


func _set_active_lb_filter(active_btn: Button) -> void:
	for btn in _lb_filter_btns:
		btn.modulate = Color.WHITE if btn == active_btn else Color(1, 1, 1, 0.55)


func _make_button_style(tex: Texture2D) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.texture_margin_left = 10
	s.texture_margin_top = 10
	s.texture_margin_right = 10
	s.texture_margin_bottom = 10
	s.draw_center = true
	return s


func _make_pixel_button(text: String, min_size: Vector2, font_size: int, callback: Callable = Callable()) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_stylebox_override("normal", _make_button_style(GUI_BUTTON_NORMAL))
	btn.add_theme_stylebox_override("hover", _make_button_style(GUI_BUTTON_ACTIVE))
	btn.add_theme_stylebox_override("pressed", _make_button_style(GUI_BUTTON_ACTIVE))
	btn.add_theme_stylebox_override("focus", _make_button_style(GUI_BUTTON_ACTIVE))
	btn.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	btn.pressed.connect(func(): AudioManager.play("click"))
	if callback.is_valid():
		btn.pressed.connect(callback)
	return btn


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _is_published(entry: Dictionary) -> bool:
	var value_variant: Variant = entry.get("value", {})
	if not (value_variant is Dictionary):
		return false
	var value := value_variant as Dictionary
	var published_variant: Variant = value.get("published_at", "")
	var published_text := str(published_variant).strip_edges()
	return not published_text.is_empty()
