class_name LevelData
extends RefCounted

static func normalize(rpc_name: String, payload: Variant) -> Variant:
	if not (payload is Dictionary):
		return payload

	var root := payload as Dictionary
	match rpc_name:
		"get_level":
			var out := root.duplicate(true)
			var value_variant: Variant = out.get("value", null)
			if value_variant is Dictionary:
				out["value"] = normalize_level_value(value_variant as Dictionary)
			return out
		"list_my_levels", "list_single_player_levels", "list_all_levels", "list_friend_levels":
			var out := root.duplicate(true)
			var levels_variant: Variant = out.get("levels", null)
			if levels_variant is Array:
				var normalized: Array = []
				for entry_variant in levels_variant as Array:
					if entry_variant is Dictionary:
						var entry := (entry_variant as Dictionary).duplicate(true)
						var value_variant: Variant = entry.get("value", null)
						if value_variant is Dictionary:
							entry["value"] = normalize_level_value(value_variant as Dictionary)
						normalized.append(entry)
					else:
						normalized.append(entry_variant)
				out["levels"] = normalized
			return out
		_:
			return payload


static func normalize_level_value(level_value: Dictionary) -> Dictionary:
	var normalized := level_value.duplicate(true)
	for key_variant in normalized.keys():
		var key := str(key_variant)
		var value: Variant = normalized[key]

		if key == "grid_size":
			if value is int or value is float:
				normalized[key] = int(value)
			continue

		if key == "likes" or key == "dislikes":
			if value is int or value is float:
				normalized[key] = int(value)
			continue

		if key == "name" or key == "description" or key == "sprite" \
				or key == "created_at" or key == "updated_at" or key == "published_at":
			continue

		if value is Array:
			var converted: Array = []
			var changed := false
			for item in value as Array:
				if item is int or item is float:
					converted.append(int(item))
					changed = true
				else:
					converted.append(item)
			if changed:
				normalized[key] = converted

	return normalized


static func level_key(entry: Dictionary) -> String:
	var val: Variant = entry.get("value", {})
	if val is Dictionary:
		var n := str((val as Dictionary).get("name", "")).strip_edges()
		if not n.is_empty():
			return n
	return str(entry.get("key", "")).strip_edges()


static func display_level_name(entry: Dictionary) -> String:
	return level_key(entry)


static func is_published(entry: Dictionary) -> bool:
	var val: Variant = entry.get("value", {})
	if not (val is Dictionary):
		return false
	var published_variant: Variant = (val as Dictionary).get("published_at", "")
	return not str(published_variant).strip_edges().is_empty()


static func timestamp_to_unix(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float:
		return int(value)
	var text := str(value).strip_edges()
	if text.is_empty():
		return 0
	if text.is_valid_int():
		return text.to_int()
	return int(Time.get_unix_time_from_datetime_string(text))


static func entry_updated_at(entry: Dictionary) -> int:
	var val: Variant = entry.get("value", {})
	if val is Dictionary:
		var value := val as Dictionary
		var ts := timestamp_to_unix(value.get("updated_at", ""))
		if ts > 0:
			return ts
		ts = timestamp_to_unix(value.get("created_at", ""))
		if ts > 0:
			return ts
	var top_ts := timestamp_to_unix(entry.get("updated_at", ""))
	if top_ts > 0:
		return top_ts
	return timestamp_to_unix(entry.get("created_at", ""))
