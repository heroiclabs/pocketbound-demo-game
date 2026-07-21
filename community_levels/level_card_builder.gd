class_name LevelCardBuilder
extends RefCounted

const ICON_RANK: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/icon_star.tres")
const ICON_STEPS: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/icon_steps.tres")
const ICON_TIME: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/icon_time.tres")
const ICON_PLAYED: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/icon_play.tres")


# Returns {"card": Button, "labels": {"ranking": Label, "steps": Label, "time": Label, "played": Label}}
func make_level_card(entry: Dictionary, idx: int, identity: String, on_select: Callable) -> Dictionary:
	var val: Dictionary = {}
	var val_v: Variant = entry.get("value", {})
	if val_v is Dictionary:
		val = val_v as Dictionary
	var level_name := LevelData.level_key(entry)
	var owner_name := str(entry.get("owner_name", ""))

	var card := Button.new()
	card.flat = true
	card.custom_minimum_size = Vector2(0, 140)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_entered.connect(func(): AudioManager.play("btn_hover"))
	card.pressed.connect(func():
		AudioManager.play("click")
		on_select.call(idx)
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

	row.add_child(make_thumbnail(val))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = level_name
	name_lbl.clip_text = true
	name_lbl.theme_type_variation = &"TitleLabel"
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_lbl)

	if not owner_name.is_empty():
		var by_lbl := Label.new()
		by_lbl.text = "By: %s" % owner_name
		by_lbl.theme_type_variation = &"SubLabel"
		by_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(by_lbl)

	var ranking_lbl := _make_meta_label()
	var steps_lbl := _make_meta_label()
	var time_lbl := _make_meta_label()
	var played_lbl := _make_meta_label()
	info.add_child(_make_meta_row(ICON_RANK, ranking_lbl))
	info.add_child(_make_meta_row(ICON_STEPS, steps_lbl))
	info.add_child(_make_meta_row(ICON_TIME, time_lbl))
	info.add_child(_make_meta_row(ICON_PLAYED, played_lbl))

	return {
		"card": card,
		"labels": {
			"ranking": ranking_lbl,
			"steps": steps_lbl,
			"time": time_lbl,
			"played": played_lbl,
		}
	}


func make_thumbnail(val: Dictionary) -> Control:
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


func format_card_time(time_ms: int) -> String:
	if time_ms <= 0:
		return "--"
	var total_seconds := int(time_ms / 1000)
	var minutes := int(total_seconds / 60)
	var seconds := int(total_seconds % 60)
	var centiseconds := int((time_ms % 1000) / 10)
	return "%02d:%02d.%02d" % [minutes, seconds, centiseconds]


func _make_meta_label() -> Label:
	var lbl := Label.new()
	lbl.theme_type_variation = &"MetaLabel"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_meta_row(icon_texture: Texture2D, text_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(14, 14)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	row.add_child(text_label)
	return row
