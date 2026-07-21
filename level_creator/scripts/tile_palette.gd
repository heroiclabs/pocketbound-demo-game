extends PanelContainer

signal tile_picked(obj: PlaceableObject)
signal grid_size_changed(value: float)
signal save_requested
signal publish_requested
signal play_requested

const PlaceableScene = preload("res://level_player/placeable_object.tscn")
const GUI_BUTTON_NORMAL_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip.tres")
const GUI_BUTTON_ACTIVE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip_right.tres")
const GUI_WINDOW_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_window.tres")
const SCROLLBAR_BG_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_bg.tres")
const SCROLLBAR_HANDLE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/Scrollbar_handle.tres")
const BASIC_FONT: Font = preload("res://assets/Fonts/Pixelify_Sans/PixelifySans-VariableFont_wght.ttf")
const TITLE_FONT: Font = preload("res://assets/Fonts/Pixelify_Sans/static/PixelifySans-Bold.ttf")


const COLOR_TEXT_LIGHT := Palette.LIGHTEST
const COLOR_FIELD_BG := Palette.DARK
const COLOR_FIELD_BORDER := Palette.LIGHT
const COLOR_TAB_SELECTED_BG := Palette.DARK
const COLOR_TAB_UNSELECTED_BG := Palette.LIGHT
const COLOR_TAB_BORDER := Palette.DARKEST
const COLOR_TAB_SELECTED_TEXT := Palette.LIGHTEST
const COLOR_TAB_UNSELECTED_TEXT := Palette.DARKEST

const ROOM_TILES := [
	{"sprite": "block.png",  "components": [ComponentRegistry.BLOCKED]},
	{"sprite": "N.png",      "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH]},
	{"sprite": "E.png",      "components": [ComponentRegistry.WALKABLE, ComponentRegistry.EAST]},
	{"sprite": "S.png",      "components": [ComponentRegistry.WALKABLE, ComponentRegistry.SOUTH]},
	{"sprite": "W.png",      "components": [ComponentRegistry.WALKABLE, ComponentRegistry.WEST]},
	{"sprite": "NE.png",     "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH, ComponentRegistry.EAST]},
	{"sprite": "NW.png",     "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH, ComponentRegistry.WEST]},
	{"sprite": "NS.png",     "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH, ComponentRegistry.SOUTH]},
	{"sprite": "EW.png",     "components": [ComponentRegistry.WALKABLE, ComponentRegistry.EAST, ComponentRegistry.WEST]},
	{"sprite": "ES.png",     "components": [ComponentRegistry.WALKABLE, ComponentRegistry.EAST, ComponentRegistry.SOUTH]},
	{"sprite": "SW.png",     "components": [ComponentRegistry.WALKABLE, ComponentRegistry.SOUTH, ComponentRegistry.WEST]},
	{"sprite": "NES.png",    "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH, ComponentRegistry.EAST, ComponentRegistry.SOUTH]},
	{"sprite": "NEW.png",    "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH, ComponentRegistry.EAST, ComponentRegistry.WEST]},
	{"sprite": "NSW.png",    "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH, ComponentRegistry.SOUTH, ComponentRegistry.WEST]},
	{"sprite": "ESW.png",    "components": [ComponentRegistry.WALKABLE, ComponentRegistry.EAST, ComponentRegistry.SOUTH, ComponentRegistry.WEST]},
	{"sprite": "NESW.png",   "components": [ComponentRegistry.WALKABLE, ComponentRegistry.NORTH, ComponentRegistry.EAST, ComponentRegistry.SOUTH, ComponentRegistry.WEST]},
]
const BLOCK_TILE_INDEX := 0
const SINGLE_DOOR_TILE_INDICES := [1, 2, 3, 4]
const DUAL_DOOR_TILE_INDICES := [5, 6, 7, 8, 9, 10]
const THREE_DOOR_TILE_INDICES := [11, 12, 13, 14]
const FOUR_DOOR_TILE_INDICES := [15]

var world: TileWorld

var _start_button: TextureButton
var _end_button: TextureButton

var _name_edit: LineEdit
var _grid_size_spin: SpinBox
var _desc_edit: TextEdit
var _tab_container: TabContainer
var _tab_row: HBoxContainer
var _design_tab_button: Button
var _info_tab_button: Button
var _save_button: Button
var _publish_button: Button
var _play_button: Button
var _basic_buttons: Array[TextureButton] = []
var _room_buttons: Array[TextureButton] = []
var _section_labels: Array[Label] = []
var _info_labels: Array[Label] = []
var _status_label: Label
var _status_gen: int = 0

var level_name: String:
	get: return _name_edit.text if _name_edit else ""
	set(v):
		if _name_edit:
			_name_edit.text = v

var level_description: String:
	get: return _desc_edit.text if _desc_edit else ""
	set(v):
		if _desc_edit:
			_desc_edit.text = v

var grid_size: float:
	get: return _grid_size_spin.value if _grid_size_spin else 4.0
	set(v):
		if _grid_size_spin:
			_grid_size_spin.value = v


func _ready() -> void:
	add_theme_stylebox_override("panel", _make_window_style(GUI_WINDOW_TEXTURE))

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 10)
	outer_margin.add_theme_constant_override("margin_right", 10)
	outer_margin.add_theme_constant_override("margin_top", 10)
	outer_margin.add_theme_constant_override("margin_bottom", 10)
	add_child(outer_margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	outer_margin.add_child(vbox)

	_tab_row = HBoxContainer.new()
	_tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_row.add_theme_constant_override("separation", 10)
	vbox.add_child(_tab_row)

	_design_tab_button = _make_tab_button("Design", 0)
	_design_tab_button.size_flags_stretch_ratio = 0.95
	_tab_row.add_child(_design_tab_button)

	_info_tab_button = _make_tab_button("Level Info", 1)
	_info_tab_button.size_flags_stretch_ratio = 1.05
	_tab_row.add_child(_info_tab_button)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_container.use_hidden_tabs_for_min_size = true
	_tab_container.clip_contents = true
	vbox.add_child(_tab_container)

	_build_design_tab(_tab_container)
	_build_level_info_tab(_tab_container)
	if _tab_container.has_method("set_tabs_visible"):
		_tab_container.call("set_tabs_visible", false)
	_tab_container.tab_changed.connect(_on_tab_changed)
	_set_active_tab(0)
	_style_tab_container()
	call_deferred("_style_tab_container")

	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 8)
	vbox.add_child(actions)

	_play_button = Button.new()
	_play_button.text = "Test"
	_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_button.custom_minimum_size = Vector2(0, 40)
	_style_pixel_button(_play_button)
	_play_button.disabled = true
	_play_button.pressed.connect(func(): play_requested.emit())
	actions.add_child(_play_button)

	_save_button = Button.new()
	_save_button.text = "Save Draft"
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_button.custom_minimum_size = Vector2(0, 40)
	_style_pixel_button(_save_button)
	_save_button.pressed.connect(func(): save_requested.emit())
	actions.add_child(_save_button)

	_publish_button = Button.new()
	_publish_button.text = "Publish"
	_publish_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_publish_button.custom_minimum_size = Vector2(0, 40)
	_style_pixel_button(_publish_button)
	_publish_button.pressed.connect(func(): publish_requested.emit())
	actions.add_child(_publish_button)

	_status_label = Label.new()
	_status_label.theme_type_variation = &"SectionLabel"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.visible = false
	vbox.add_child(_status_label)


func _build_design_tab(tabs: TabContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Design"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	tabs.add_child(scroll)
	_apply_scrollbar_theme(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var base_grid := _add_room_section(vbox, "Base rooms", 3)
	_start_button = _make_composite_texture_button("N", "portal", LevelConfig.START_OVERLAY_SCALE)
	_basic_buttons.append(_start_button)
	_start_button.pressed.connect(_on_start_pressed)
	base_grid.add_child(_start_button)

	_end_button = _make_composite_texture_button("N", "cat1", LevelConfig.GOAL_OVERLAY_SCALE)
	_basic_buttons.append(_end_button)
	_end_button.pressed.connect(_on_end_pressed)
	base_grid.add_child(_end_button)

	_add_room_button(base_grid, BLOCK_TILE_INDEX)

	var one_door_grid := _add_room_section(vbox, "Single door", 4)
	for idx in SINGLE_DOOR_TILE_INDICES:
		_add_room_button(one_door_grid, int(idx))

	var dual_door_grid := _add_room_section(vbox, "Dual door", 4)
	for idx in DUAL_DOOR_TILE_INDICES:
		_add_room_button(dual_door_grid, int(idx))

	var three_door_grid := _add_room_section(vbox, "Tree doors", 4)
	for idx in THREE_DOOR_TILE_INDICES:
		_add_room_button(three_door_grid, int(idx))

	var four_door_grid := _add_room_section(vbox, "Four doors", 4)
	for idx in FOUR_DOOR_TILE_INDICES:
		_add_room_button(four_door_grid, int(idx))


func _build_level_info_tab(tabs: TabContainer) -> void:
	var margin := MarginContainer.new()
	margin.name = "Level Info"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	tabs.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var name_label := _make_info_label("Level Name")
	vbox.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "My Level"
	_style_line_edit(_name_edit)
	vbox.add_child(_name_edit)

	var size_label := _make_info_label("Grid Size")
	vbox.add_child(size_label)

	_grid_size_spin = SpinBox.new()
	_grid_size_spin.min_value = 2
	_grid_size_spin.max_value = 4
	_grid_size_spin.value = 4
	_grid_size_spin.custom_minimum_size.y = 34
	_style_spin_box(_grid_size_spin)
	_grid_size_spin.value_changed.connect(func(v: float): grid_size_changed.emit(v))
	vbox.add_child(_grid_size_spin)

	var desc_label := _make_info_label("Description")
	vbox.add_child(desc_label)

	_desc_edit = TextEdit.new()
	_desc_edit.placeholder_text = "Describe your level..."
	_desc_edit.custom_minimum_size.y = 80
	_desc_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_edit.add_theme_font_override("font", BASIC_FONT)
	_desc_edit.add_theme_font_size_override("font_size", 18)
	_desc_edit.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	_desc_edit.add_theme_color_override("font_placeholder_color", Palette.LIGHT)
	_desc_edit.add_theme_stylebox_override("normal", _make_field_style())
	_desc_edit.add_theme_stylebox_override("focus", _make_field_style())
	vbox.add_child(_desc_edit)


func _make_texture_button(texture_ref: String) -> TextureButton:
	var btn := TextureButton.new()
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var texture := _load_palette_texture(texture_ref)
	if texture:
		btn.texture_normal = texture
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = Vector2(56, 56)
	return btn


func _make_composite_texture_button(base_texture_ref: String, overlay_texture_ref: String, overlay_scale: float) -> TextureButton:
	var btn := _make_texture_button(base_texture_ref)
	var overlay_texture := _load_palette_texture(overlay_texture_ref)
	if overlay_texture == null:
		return btn

	var overlay := TextureRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.texture = overlay_texture
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	btn.add_child(overlay)
	btn.resized.connect(_on_composite_button_resized.bind(btn, overlay, overlay_scale))
	_layout_composite_overlay(btn, overlay, overlay_scale)
	return btn


func _on_composite_button_resized(button: TextureButton, overlay: TextureRect, overlay_scale: float) -> void:
	_layout_composite_overlay(button, overlay, overlay_scale)


func _layout_composite_overlay(button: TextureButton, overlay: TextureRect, overlay_scale: float) -> void:
	var base_size := minf(button.size.x, button.size.y)
	if base_size <= 0.0:
		base_size = minf(button.custom_minimum_size.x, button.custom_minimum_size.y)
	var side := maxf(8.0, floorf(base_size * overlay_scale))
	overlay.custom_minimum_size = Vector2(side, side)
	overlay.size = Vector2(side, side)
	var pos := (button.size - overlay.size) * 0.5
	overlay.position = Vector2(floorf(pos.x), floorf(pos.y))


func _load_palette_texture(texture_ref: String) -> Texture2D:
	var texture_path := texture_ref if texture_ref.begins_with("res://") else LevelConfig.sprite_resource_path(texture_ref)
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_warning("Failed to load palette texture: %s" % texture_path)
	return texture


func _add_room_section(parent: VBoxContainer, title: String, columns: int) -> GridContainer:
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"SectionLabel"
	_section_labels.append(label)
	parent.add_child(label)

	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


func _add_room_button(grid: GridContainer, index: int) -> void:
	var def: Dictionary = ROOM_TILES[index]
	var btn := _make_texture_button(str(def["sprite"]))
	_room_buttons.append(btn)
	btn.pressed.connect(_on_room_pressed.bind(index))
	grid.add_child(btn)


func _make_info_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionLabel"
	_info_labels.append(label)
	return label


func _style_tab_container() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Palette.LIGHTEST
	panel_style.border_color = Palette.DARK
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	_tab_container.add_theme_stylebox_override("panel", panel_style)

	_apply_custom_tab_styles()


func _make_tab_button(text: String, tab_index: int) -> Button:
	var button := Button.new()
	button.text = text
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.custom_minimum_size = Vector2(0, 56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(func(): _set_active_tab(tab_index))
	return button


func _set_active_tab(index: int) -> void:
	if _tab_container == null:
		return
	_tab_container.current_tab = index
	_apply_custom_tab_styles()


func _on_tab_changed(_tab: int) -> void:
	_apply_custom_tab_styles()


func _apply_custom_tab_styles() -> void:
	if _design_tab_button:
		_style_tab_button(_design_tab_button, _tab_container.current_tab == 0)
	if _info_tab_button:
		_style_tab_button(_info_tab_button, _tab_container.current_tab == 1)


func _style_tab_button(button: Button, is_selected: bool) -> void:
	var bg := COLOR_TAB_SELECTED_BG if is_selected else COLOR_TAB_UNSELECTED_BG
	var hover_bg := COLOR_TAB_UNSELECTED_BG if is_selected else COLOR_TAB_SELECTED_BG
	var fg := COLOR_TAB_SELECTED_TEXT if is_selected else COLOR_TAB_UNSELECTED_TEXT
	var normal := _make_tab_style(bg, COLOR_TAB_BORDER)
	var hover := _make_tab_style(hover_bg, COLOR_TAB_BORDER)
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_focus_color", fg)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_stylebox_override("disabled", normal)


func _style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_font_override("font", BASIC_FONT)
	edit.add_theme_font_size_override("font_size", 18)
	edit.add_theme_color_override("font_color", COLOR_TEXT_LIGHT)
	edit.add_theme_color_override("font_placeholder_color", Palette.LIGHT)
	edit.add_theme_stylebox_override("normal", _make_field_style())
	edit.add_theme_stylebox_override("focus", _make_field_style())


func _style_spin_box(spin: SpinBox) -> void:
	var spin_edit := spin.get_line_edit()
	if spin_edit:
		_style_line_edit(spin_edit)

	var normal_bg: StyleBoxFlat = _make_spin_button_style(COLOR_FIELD_BG, COLOR_FIELD_BORDER, true)
	var hovered_bg: StyleBoxFlat = _make_spin_button_style(Palette.DARK, COLOR_FIELD_BORDER, true)
	var pressed_bg: StyleBoxFlat = _make_spin_button_style(Palette.DARKEST, COLOR_FIELD_BORDER, true)
	var disabled_bg: StyleBoxFlat = _make_spin_button_style(Palette.DARK, COLOR_FIELD_BORDER, true)
	var normal_down_bg: StyleBoxFlat = _make_spin_button_style(COLOR_FIELD_BG, COLOR_FIELD_BORDER, false)
	var hovered_down_bg: StyleBoxFlat = _make_spin_button_style(Palette.DARK, COLOR_FIELD_BORDER, false)
	var pressed_down_bg: StyleBoxFlat = _make_spin_button_style(Palette.DARKEST, COLOR_FIELD_BORDER, false)
	var disabled_down_bg: StyleBoxFlat = _make_spin_button_style(Palette.DARK, COLOR_FIELD_BORDER, false)
	var separator: StyleBoxFlat = _make_spin_separator_style()

	spin.add_theme_color_override("up_icon_modulate", COLOR_TEXT_LIGHT)
	spin.add_theme_color_override("up_hover_icon_modulate", COLOR_TEXT_LIGHT)
	spin.add_theme_color_override("up_pressed_icon_modulate", COLOR_TEXT_LIGHT)
	spin.add_theme_color_override("up_disabled_icon_modulate", Palette.DARK)
	spin.add_theme_color_override("down_icon_modulate", COLOR_TEXT_LIGHT)
	spin.add_theme_color_override("down_hover_icon_modulate", COLOR_TEXT_LIGHT)
	spin.add_theme_color_override("down_pressed_icon_modulate", COLOR_TEXT_LIGHT)
	spin.add_theme_color_override("down_disabled_icon_modulate", Palette.DARK)

	spin.add_theme_stylebox_override("up_background", normal_bg)
	spin.add_theme_stylebox_override("up_background_hovered", hovered_bg)
	spin.add_theme_stylebox_override("up_background_pressed", pressed_bg)
	spin.add_theme_stylebox_override("up_background_disabled", disabled_bg)
	spin.add_theme_stylebox_override("down_background", normal_down_bg)
	spin.add_theme_stylebox_override("down_background_hovered", hovered_down_bg)
	spin.add_theme_stylebox_override("down_background_pressed", pressed_down_bg)
	spin.add_theme_stylebox_override("down_background_disabled", disabled_down_bg)
	spin.add_theme_stylebox_override("field_and_buttons_separator", separator)
	spin.add_theme_stylebox_override("up_down_buttons_separator", separator)


func _make_field_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FIELD_BG
	style.border_color = COLOR_FIELD_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _make_spin_button_style(bg_color: Color, border_color: Color, top_button: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	if top_button:
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 0
	else:
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_right = 4
	return style


func _make_spin_separator_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FIELD_BORDER
	return style


func _make_tab_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _make_window_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 14
	style.texture_margin_top = 14
	style.texture_margin_right = 14
	style.texture_margin_bottom = 14
	style.draw_center = true
	return style


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


func _style_pixel_button(button: Button) -> void:
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _make_button_style(GUI_BUTTON_NORMAL_TEXTURE))
	button.add_theme_stylebox_override("hover", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("pressed", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("focus", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("disabled", _make_button_style(GUI_BUTTON_NORMAL_TEXTURE))


func apply_layout(panel_width: float, panel_height: float, grid_cell_size: float = -1.0) -> void:
	if panel_width <= 0.0:
		return

	custom_minimum_size = Vector2(panel_width, panel_height)
	size = Vector2(panel_width, panel_height)

	var room_tile := maxf(24.0, floorf(grid_cell_size))
	if room_tile <= 24.0:
		var horizontal_padding := 16.0
		var separation := 8.0
		var room_columns := 4.0
		room_tile = floorf((panel_width - horizontal_padding - separation * (room_columns - 1.0)) / room_columns)
		room_tile = maxf(24.0, room_tile)
	room_tile = minf(room_tile, 80.0)

	for btn in _room_buttons:
		if btn:
			btn.custom_minimum_size = Vector2(room_tile, room_tile)

	for btn in _basic_buttons:
		if btn:
			btn.custom_minimum_size = Vector2(room_tile, room_tile)

	if _save_button:
		_save_button.custom_minimum_size.y = maxf(34.0, floorf(room_tile * 0.70))
	if _publish_button:
		_publish_button.custom_minimum_size.y = maxf(34.0, floorf(room_tile * 0.70))
	if _play_button:
		_play_button.custom_minimum_size.y = maxf(34.0, floorf(room_tile * 0.70))

	if _desc_edit:
		_desc_edit.custom_minimum_size.y = maxf(70.0, panel_height * 0.22)


func _on_start_pressed() -> void:
	var id := world.create_entity(TileWorld.OFF_GRID_COORD, TileWorld.OFF_GRID_COORD, "portal")
	world.add(ComponentRegistry.WALKABLE, id)
	world.add(ComponentRegistry.START, id)
	var obj := PlaceableScene.instantiate() as PlaceableObject
	obj.entity_id = id
	obj.sprite_path = "portal"
	obj.set_layered_textures(
		LevelConfig.load_sprite_texture("N"),
		LevelConfig.load_sprite_texture("portal"),
		0.0,
		LevelConfig.START_OVERLAY_SCALE
	)
	_start_button.disabled = true
	tile_picked.emit(obj)


func _on_end_pressed() -> void:
	var id := world.create_entity(TileWorld.OFF_GRID_COORD, TileWorld.OFF_GRID_COORD, "cat1")
	world.add(ComponentRegistry.WALKABLE, id)
	world.add(ComponentRegistry.END, id)
	var obj := PlaceableScene.instantiate() as PlaceableObject
	obj.entity_id = id
	obj.sprite_path = "cat1"
	obj.set_layered_textures(
		LevelConfig.load_sprite_texture("N"),
		LevelConfig.load_sprite_texture("cat1"),
		0.0,
		LevelConfig.GOAL_OVERLAY_SCALE
	)
	_end_button.disabled = true
	tile_picked.emit(obj)


func _on_room_pressed(index: int) -> void:
	var def: Dictionary = ROOM_TILES[index]
	var sprite_name: String = def["sprite"]
	var id := world.create_entity(TileWorld.OFF_GRID_COORD, TileWorld.OFF_GRID_COORD, sprite_name)
	for comp in def["components"]:
		world.add(comp, id)
	var obj := PlaceableScene.instantiate() as PlaceableObject
	obj.entity_id = id
	obj.sprite_path = sprite_name
	_set_sprite(obj, sprite_name)
	tile_picked.emit(obj)


func _set_sprite(obj: PlaceableObject, sprite_name: String) -> void:
	obj.set_texture(LevelConfig.load_sprite_texture(sprite_name))


func enable_start() -> void:
	_start_button.disabled = false


func enable_end() -> void:
	_end_button.disabled = false


func set_test_enabled(enabled: bool) -> void:
	if _play_button:
		_play_button.disabled = not enabled


func is_test_enabled() -> bool:
	return _play_button != null and not _play_button.disabled


func show_status(text: String, is_error: bool) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.85, 0.3, 0.3) if is_error else Color(0.3, 0.75, 0.4)
	)
	_status_label.visible = true
	if not is_error:
		_status_gen += 1
		var gen := _status_gen
		get_tree().create_timer(3.0).timeout.connect(func():
			if _status_gen == gen:
				_status_label.visible = false
		)


func reset() -> void:
	_start_button.disabled = false
	_end_button.disabled = false
	set_test_enabled(false)
	if _status_label:
		_status_label.visible = false
