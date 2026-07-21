class_name CampaignController
extends RefCounted

var own_levels: Array = []

var _friend_levels_cache: Dictionary = {}
var _friend_levels_cache_ready: bool = false


func load_own_levels() -> void:
	var result: Variant = await OnlineSession.call_rpc("list_single_player_levels", "")
	own_levels = _extract_levels(result)


func load_levels_for_user(user_id: String) -> Array:
	if user_id.is_empty():
		return []
	if _friend_levels_cache.has(user_id):
		return _friend_levels_cache[user_id]

	if not _friend_levels_cache_ready:
		await _load_friend_levels_cache()
		_friend_levels_cache_ready = true

	return _friend_levels_cache.get(user_id, [])


func warm_friend_level_cache() -> void:
	if _friend_levels_cache_ready:
		return
	await _load_friend_levels_cache()
	_friend_levels_cache_ready = true


func load_all_community_levels(resolve_owner_name: Callable = Callable()) -> Array:
	var all_levels: Array = []
	var cursor := ""
	while true:
		var payload_data := {"limit": 100}
		if not cursor.is_empty():
			payload_data["cursor"] = cursor
		var result: Variant = await OnlineSession.call_rpc("list_all_levels", JSON.stringify(payload_data))
		if not (result is Dictionary):
			break
		var response := result as Dictionary
		var levels_variant: Variant = response.get("levels", [])
		if levels_variant is Array:
			for entry_variant in (levels_variant as Array):
				if not (entry_variant is Dictionary):
					continue
				var entry := (entry_variant as Dictionary).duplicate(true)
				var owner_id := str(entry.get("user_id", "")).strip_edges()
				var owner_name := ""
				if resolve_owner_name.is_valid():
					owner_name = str(resolve_owner_name.call(owner_id))
				if owner_name.is_empty():
					if OnlineSession.session and owner_id == str(OnlineSession.session.user_id):
						owner_name = str(OnlineSession.session.username).strip_edges()
					if owner_name.is_empty():
						owner_name = owner_id.left(8)
				entry["owner_name"] = owner_name
				all_levels.append(entry)
		cursor = str(response.get("next_cursor", "")).strip_edges()
		if cursor.is_empty():
			break
	return all_levels


func get_campaign_next_level(current_key: String, current_owner_id: String) -> Dictionary:
	if own_levels.is_empty():
		return {"has_next": false}

	var current_index := -1
	for i in range(own_levels.size()):
		var entry_variant: Variant = own_levels[i]
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var entry_key := LevelData.level_key(entry)
		var entry_owner_id := str(entry.get("user_id", ""))
		if entry_key == current_key and (current_owner_id.is_empty() or entry_owner_id == current_owner_id):
			current_index = i
			break

	if current_index < 0 or current_index + 1 >= own_levels.size():
		return {"has_next": false}

	var next_entry_variant: Variant = own_levels[current_index + 1]
	if not (next_entry_variant is Dictionary):
		return {"has_next": false}
	var next_entry := next_entry_variant as Dictionary
	return {
		"has_next": true,
		"key": LevelData.level_key(next_entry),
		"owner_id": str(next_entry.get("user_id", "")),
	}


func invalidate_cache() -> void:
	_friend_levels_cache.clear()
	_friend_levels_cache_ready = false


func _extract_levels(result: Variant) -> Array:
	var out: Array = []
	if not (result is Dictionary):
		return out
	var levels: Array = result.get("levels", [])
	for entry in levels:
		if entry is Dictionary:
			out.append(entry)
	return out


func _load_friend_levels_cache() -> void:
	_friend_levels_cache.clear()

	var cursor := ""
	while true:
		var payload_data := {"limit": 100}
		if not cursor.is_empty():
			payload_data["cursor"] = cursor

		var result: Variant = await OnlineSession.call_rpc("list_friend_levels", JSON.stringify(payload_data))
		if not (result is Dictionary):
			break

		var response := result as Dictionary
		var entries: Array = response.get("levels", [])
		for entry_variant in entries:
			if not (entry_variant is Dictionary):
				continue
			var entry := entry_variant as Dictionary
			var owner_id := str(entry.get("user_id", "")).strip_edges()
			if owner_id.is_empty():
				continue
			if not _friend_levels_cache.has(owner_id):
				_friend_levels_cache[owner_id] = []
			var owner_levels: Array = _friend_levels_cache[owner_id]
			owner_levels.append(entry)
			_friend_levels_cache[owner_id] = owner_levels

		cursor = str(response.get("next_cursor", "")).strip_edges()
		if cursor.is_empty():
			break

	for owner_id in _friend_levels_cache.keys():
		var owner_levels: Array = _friend_levels_cache[owner_id]
		owner_levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return LevelData.display_level_name(a).nocasecmp_to(LevelData.display_level_name(b)) < 0
		)
		_friend_levels_cache[owner_id] = owner_levels
