class_name TileWorld
extends RefCounted

const OFF_GRID_COORD := -9999

const _RESERVED := ["key", "grid_size", "name", "description", "x", "y", "sprite"]

const RULE_TARGET_EXISTS := "target_exists"
const RULE_TARGET_WALKABLE := "target_walkable"
const RULE_TARGET_NOT_BLOCKED := "target_not_blocked"
const RULE_SOURCE_EXIT_IF_INTERIOR := "source_exit_dir_if_interior"
const RULE_TARGET_ENTRY_IF_INTERIOR := "target_entry_dir_if_interior"

# Indexed by entity ID (every entity has these)
var pos_x: Array[int] = []
var pos_y: Array[int] = []
var sprites: Array[String] = []

# Tombstone tracking — true means entity has been removed
var _dead: Array[bool] = []

# Hot movement permission signature (N/E/S/W bitmask) for each entity.
var move_signature: Array[int] = []

# Generic tag components: component_name -> Array[int] of entity IDs
var components: Dictionary = {}
# Fast membership index: component_name -> Dictionary{id: true}
var _component_lookup: Dictionary = {}

# Optional typed payload tables for richer future components.
var typed_components: Dictionary = {}

# Authoritative occupancy: Vector2i -> entity_id.
var _occupancy: Dictionary = {}

# Buffered structural/component writes.
var _commands: Array[Dictionary] = []
var _has_pending := false

var move_rule_table: Array[String] = [
	RULE_TARGET_EXISTS,
	RULE_TARGET_WALKABLE,
	RULE_TARGET_NOT_BLOCKED,
	RULE_SOURCE_EXIT_IF_INTERIOR,
	RULE_TARGET_ENTRY_IF_INTERIOR,
]


func _init() -> void:
	ComponentRegistry.ensure_loaded()


func create_entity(x: int, y: int, sprite: String) -> int:
	var id := pos_x.size()
	pos_x.append(x)
	pos_y.append(y)
	sprites.append(sprite)
	_dead.append(false)
	move_signature.append(0)
	_add_occupancy(id, x, y)
	return id


func entity_count() -> int:
	return pos_x.size()


func is_alive(id: int) -> bool:
	return id >= 0 and id < _dead.size() and not _dead[id]


func _is_valid_id(id: int) -> bool:
	return id >= 0 and id < pos_x.size()


func set_pos(id: int, x: int, y: int) -> void:
	if not _is_valid_id(id):
		return
	_commands.append({"op": "set_pos", "id": id, "x": x, "y": y})
	_has_pending = true


func add(component: String, id: int) -> void:
	if not _is_valid_id(id):
		return
	if not ComponentRegistry.is_allowed(component):
		push_warning("Ignoring unknown component: %s" % component)
		return
	_commands.append({"op": "add", "component": component, "id": id})
	_has_pending = true


func remove(component: String, id: int) -> void:
	if not _is_valid_id(id):
		return
	_commands.append({"op": "remove", "component": component, "id": id})
	_has_pending = true


func remove_entity(id: int) -> void:
	if not _is_valid_id(id):
		return
	_commands.append({"op": "remove_entity", "id": id})
	_has_pending = true


func set_typed(component: String, id: int, value: Variant) -> void:
	if not _is_valid_id(id):
		return
	_commands.append({"op": "set_typed", "component": component, "id": id, "value": value})
	_has_pending = true


func remove_typed(component: String, id: int) -> void:
	if not _is_valid_id(id):
		return
	_commands.append({"op": "remove_typed", "component": component, "id": id})
	_has_pending = true


func get_typed(component: String, id: int, default_value: Variant = null) -> Variant:
	_ensure_committed()
	if not typed_components.has(component):
		return default_value
	var table := typed_components[component] as Dictionary
	return table.get(id, default_value)


func commit() -> void:
	if not _has_pending:
		return

	for cmd in _commands:
		var op := str(cmd.get("op", ""))
		match op:
			"set_pos":
				_apply_set_pos(int(cmd["id"]), int(cmd["x"]), int(cmd["y"]))
			"add":
				_apply_add(str(cmd["component"]), int(cmd["id"]))
			"remove":
				_apply_remove(str(cmd["component"]), int(cmd["id"]))
			"remove_entity":
				_apply_remove_entity(int(cmd["id"]))
			"set_typed":
				_apply_set_typed(str(cmd["component"]), int(cmd["id"]), cmd.get("value"))
			"remove_typed":
				_apply_remove_typed(str(cmd["component"]), int(cmd["id"]))

	_commands.clear()
	_has_pending = false


func entity_at(x: int, y: int) -> int:
	_ensure_committed()
	var key := Vector2i(x, y)
	return int(_occupancy.get(key, -1))


func get_components(id: int) -> Array[String]:
	_ensure_committed()
	var result: Array[String] = []
	if not _is_valid_id(id):
		return result
	for comp_name in _component_lookup.keys():
		var lookup := _component_lookup[comp_name] as Dictionary
		if lookup.has(id):
			result.append(str(comp_name))
	return result


func has(component: String, id: int) -> bool:
	_ensure_committed()
	return _has_component(component, id)


func get_ids(component: String) -> Array[int]:
	_ensure_committed()
	var ids := components.get(component, [] as Array[int]) as Array[int]
	return ids.duplicate()


func has_dir(id: int, dir: int) -> bool:
	_ensure_committed()
	if not _is_valid_id(id) or _dead[id]:
		return false
	return (move_signature[id] & dir) != 0


func is_walkable(id: int) -> bool:
	_ensure_committed()
	if not _is_valid_id(id) or _dead[id]:
		return false
	if _has_component(ComponentRegistry.WALKABLE, id):
		return true
	# Backward compatibility for older payloads.
	if _has_component(ComponentRegistry.START, id) or _has_component(ComponentRegistry.END, id):
		return true
	if _has_component(ComponentRegistry.BLOCKED, id):
		return false
	return move_signature[id] != 0


func get_start_pos() -> Vector2i:
	_ensure_committed()
	var ids := get_ids(ComponentRegistry.START)
	if ids.is_empty():
		return Vector2i(-1, -1)
	for id in ids:
		if _is_valid_id(id) and is_alive(id):
			return Vector2i(pos_x[id], pos_y[id])
	return Vector2i(-1, -1)


func get_end_pos() -> Vector2i:
	_ensure_committed()
	var ids := get_ids(ComponentRegistry.END)
	if ids.is_empty():
		return Vector2i(-1, -1)
	for id in ids:
		if _is_valid_id(id) and is_alive(id):
			return Vector2i(pos_x[id], pos_y[id])
	return Vector2i(-1, -1)


func clear() -> void:
	pos_x.clear()
	pos_y.clear()
	sprites.clear()
	_dead.clear()
	move_signature.clear()
	components.clear()
	_component_lookup.clear()
	typed_components.clear()
	_occupancy.clear()
	_commands.clear()
	_has_pending = false


func to_dict() -> Dictionary:
	_ensure_committed()
	var d := {}
	var new_x: Array[int] = []
	var new_y: Array[int] = []
	var new_sprites: Array[String] = []
	var id_map: Dictionary = {}

	for old_id in range(pos_x.size()):
		if _dead[old_id]:
			continue
		var new_id := new_x.size()
		id_map[old_id] = new_id
		new_x.append(pos_x[old_id])
		new_y.append(pos_y[old_id])
		new_sprites.append(sprites[old_id])

	d["x"] = new_x
	d["y"] = new_y
	d["sprite"] = new_sprites
	for comp_name in components:
		var remapped: Array[int] = []
		for old_id in components[comp_name]:
			if id_map.has(old_id):
				remapped.append(id_map[old_id])
		if not remapped.is_empty():
			d[comp_name] = remapped
	return d


func from_dict(d: Dictionary) -> void:
	clear()
	var xs: Array = d.get("x", [])
	var ys: Array = d.get("y", [])
	var sps: Array = d.get("sprite", [])
	var count := mini(xs.size(), ys.size())
	for i in range(count):
		create_entity(int(xs[i]), int(ys[i]), str(sps[i]) if i < sps.size() else "")

	for key in d:
		if key in _RESERVED:
			continue
		var arr = d[key]
		if arr is Array:
			for id_val in arr:
				if id_val is float or id_val is int:
					var id := int(id_val)
					if _is_valid_id(id):
						add(str(key), id)

	commit()
	_ensure_default_walkable_components()


func set_move_rules(rules: Array[String]) -> void:
	move_rule_table = rules.duplicate()


func can_move(from: Vector2i, to: Vector2i, direction: Vector2i, grid_size: int) -> bool:
	_ensure_committed()
	var dir := PlaceableObject.vec_to_dir(direction)
	if dir == 0:
		return false

	var source_id := entity_at(from.x, from.y)
	var target_id := entity_at(to.x, to.y)

	for rule_id in move_rule_table:
		if not _eval_move_rule(str(rule_id), from, to, source_id, target_id, dir, grid_size):
			return false
	return true


func _ensure_committed() -> void:
	if _has_pending:
		commit()


func _has_component(component: String, id: int) -> bool:
	if not _is_valid_id(id):
		return false
	if not _component_lookup.has(component):
		return false
	var lookup := _component_lookup[component] as Dictionary
	return lookup.has(id)


func _apply_add(component: String, id: int) -> void:
	if not _is_valid_id(id) or _dead[id]:
		return
	if not components.has(component):
		components[component] = [] as Array[int]
	if not _component_lookup.has(component):
		_component_lookup[component] = {}

	var lookup := _component_lookup[component] as Dictionary
	if lookup.has(id):
		return
	lookup[id] = true

	var arr := components[component] as Array[int]
	arr.append(id)

	var bit := int(ComponentRegistry.DIR_BIT_BY_COMPONENT.get(component, 0))
	if bit != 0:
		move_signature[id] = move_signature[id] | bit


func _apply_remove(component: String, id: int) -> void:
	if not components.has(component):
		return
	if not _component_lookup.has(component):
		return
	var lookup := _component_lookup[component] as Dictionary
	if not lookup.has(id):
		return
	lookup.erase(id)

	var arr := components[component] as Array[int]
	var idx := arr.find(id)
	if idx >= 0:
		arr.remove_at(idx)

	if arr.is_empty():
		components.erase(component)
		_component_lookup.erase(component)

	var bit := int(ComponentRegistry.DIR_BIT_BY_COMPONENT.get(component, 0))
	if bit != 0 and _is_valid_id(id):
		move_signature[id] = move_signature[id] & ~bit


func _apply_set_pos(id: int, x: int, y: int) -> void:
	if not _is_valid_id(id) or _dead[id]:
		return
	_remove_occupancy(id, pos_x[id], pos_y[id])
	pos_x[id] = x
	pos_y[id] = y
	_add_occupancy(id, x, y)


func _apply_remove_entity(id: int) -> void:
	if not _is_valid_id(id) or _dead[id]:
		return

	_remove_occupancy(id, pos_x[id], pos_y[id])
	_dead[id] = true
	move_signature[id] = 0

	for comp_name_var in _component_lookup.keys().duplicate():
		var comp_name := str(comp_name_var)
		var lookup := _component_lookup.get(comp_name, {} as Dictionary) as Dictionary
		if lookup.has(id):
			_apply_remove(comp_name, id)

	for comp_name_var in typed_components.keys().duplicate():
		var comp_name := str(comp_name_var)
		var table := typed_components.get(comp_name, {} as Dictionary) as Dictionary
		table.erase(id)
		if table.is_empty():
			typed_components.erase(comp_name)


func _apply_set_typed(component: String, id: int, value: Variant) -> void:
	if not _is_valid_id(id) or _dead[id]:
		return
	if not typed_components.has(component):
		typed_components[component] = {}
	var table := typed_components[component] as Dictionary
	table[id] = value


func _apply_remove_typed(component: String, id: int) -> void:
	if not typed_components.has(component):
		return
	var table := typed_components[component] as Dictionary
	table.erase(id)
	if table.is_empty():
		typed_components.erase(component)


func _is_occupiable(x: int, y: int) -> bool:
	return x != OFF_GRID_COORD and y != OFF_GRID_COORD


func _add_occupancy(id: int, x: int, y: int) -> void:
	if not _is_occupiable(x, y):
		return
	_occupancy[Vector2i(x, y)] = id


func _remove_occupancy(id: int, x: int, y: int) -> void:
	if not _is_occupiable(x, y):
		return
	var key := Vector2i(x, y)
	if int(_occupancy.get(key, -1)) == id:
		_occupancy.erase(key)


func _is_inside_grid(pos: Vector2i, grid_size: int) -> bool:
	return pos.x >= 0 and pos.x < grid_size and pos.y >= 0 and pos.y < grid_size


func _opposite_dir(dir: int) -> int:
	return PlaceableObject.opposite_dir(dir)


func _eval_move_rule(rule_id: String, _from: Vector2i, _to: Vector2i, source_id: int, target_id: int, dir: int, _grid_size: int) -> bool:
	match rule_id:
		RULE_TARGET_EXISTS:
			return target_id != -1 and is_alive(target_id)
		RULE_TARGET_WALKABLE:
			return target_id != -1 and is_walkable(target_id)
		RULE_TARGET_NOT_BLOCKED:
			return target_id != -1 and not _has_component(ComponentRegistry.BLOCKED, target_id)
		RULE_SOURCE_EXIT_IF_INTERIOR:
			if source_id == -1:
				return false
			return (move_signature[source_id] & dir) != 0
		RULE_TARGET_ENTRY_IF_INTERIOR:
			if target_id == -1:
				return false
			var entry_dir := _opposite_dir(dir)
			return (move_signature[target_id] & entry_dir) != 0
		_:
			# Unknown rule IDs are ignored to allow phased rollout.
			return true


func _ensure_default_walkable_components() -> void:
	for id in range(entity_count()):
		if not is_alive(id):
			continue
		if _has_component(ComponentRegistry.WALKABLE, id):
			continue
		if _has_component(ComponentRegistry.START, id) or _has_component(ComponentRegistry.END, id):
			add(ComponentRegistry.WALKABLE, id)
			continue
		if _has_component(ComponentRegistry.BLOCKED, id):
			continue
		if move_signature[id] != 0:
			add(ComponentRegistry.WALKABLE, id)
	commit()
