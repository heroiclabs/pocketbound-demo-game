class_name ComponentRegistry
extends RefCounted

const REGISTRY_PATH := "res://shared/component_registry.json"

const WALKABLE := "walkable"
const BLOCKED := "blocked"
const START := "start"
const END := "end"
const NORTH := "north"
const EAST := "east"
const SOUTH := "south"
const WEST := "west"

const DIR_BIT_BY_COMPONENT := {
	NORTH: 1,
	EAST: 2,
	SOUTH: 4,
	WEST: 8,
}

static var _loaded := false
static var _id_by_name: Dictionary = {}
static var _name_by_id: Dictionary = {}
static var _allowed: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var file := FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		_fallback()
		return

	var parsed_variant: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed_variant is Dictionary):
		_fallback()
		return

	var parsed: Dictionary = parsed_variant
	var components: Array = parsed.get("components", [])
	for row in components:
		if not (row is Dictionary):
			continue
		var name := str(row.get("name", ""))
		var id := _parse_int(row.get("id", "-1"), -1)
		if name.is_empty() or id < 0:
			continue
		_id_by_name[name] = id
		_name_by_id[id] = name
		_allowed[name] = true

	if _allowed.is_empty():
		_fallback()


static func is_allowed(name: String) -> bool:
	ensure_loaded()
	return _allowed.has(name)


static func id_of(name: String) -> int:
	ensure_loaded()
	return int(_id_by_name.get(name, -1))


static func name_of(id: int) -> String:
	ensure_loaded()
	return str(_name_by_id.get(id, ""))


static func all_names() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	for k in _allowed.keys():
		out.append(str(k))
	return out


static func _fallback() -> void:
	_id_by_name.clear()
	_name_by_id.clear()
	_allowed.clear()
	var defaults := [WALKABLE, BLOCKED, START, END, NORTH, EAST, SOUTH, WEST]
	for i in range(defaults.size()):
		var name := str(defaults[i])
		var id := i + 1
		_id_by_name[name] = id
		_name_by_id[id] = name
		_allowed[name] = true


static func _parse_int(value: Variant, fallback: int) -> int:
	var text := str(value).strip_edges()
	if text.is_valid_int():
		return int(text)
	return fallback
