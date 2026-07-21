class_name CommunityLevelsController
extends RefCounted

signal entries_ready
signal stats_updated(identity: String)

const LIST_FILTER_FRIENDS := "friends"
const LIST_FILTER_BEST_SCORE := "best_score"
const LIST_FILTER_NEWEST := "newest"
const LEADERBOARD_FILTER_ALL_TIME := "all_time"

var entries: Array = []
var friends: Array = []
var vote_rank_by_id: Dictionary = {}
var entry_stats_by_id: Dictionary = {}
var list_filter: String = LIST_FILTER_NEWEST

var _load_seq: int = 0
var _stats_fetch_seq: int = 0
var _stats_fetch_active := false
var _entry_stats_inflight: Dictionary = {}
var _entry_stats_queue: Array[Dictionary] = []


func reset() -> void:
	_load_seq += 1
	_stats_fetch_seq += 1
	entries.clear()
	friends.clear()
	vote_rank_by_id.clear()
	entry_stats_by_id.clear()
	_entry_stats_inflight.clear()
	_entry_stats_queue.clear()
	_stats_fetch_active = false


func load_entries() -> void:
	_load_seq += 1
	var seq := _load_seq

	entries.clear()
	friends.clear()
	vote_rank_by_id.clear()
	entry_stats_by_id.clear()
	_entry_stats_inflight.clear()
	_entry_stats_queue.clear()
	_stats_fetch_active = false
	_stats_fetch_seq += 1

	if not OnlineSession.session:
		await OnlineSession.session_ready
	if seq != _load_seq:
		return

	var friends_result = await OnlineSession.client.list_friends_async(
		OnlineSession.session, null, 100, null
	)
	if seq != _load_seq:
		return

	var owner_name_by_id: Dictionary = {}
	if friends_result != null and not friends_result.is_exception():
		for friend in friends_result.friends:
			if friend == null or friend.user == null:
				continue
			var friend_id := str(friend.user.id)
			var name := FriendsController.display_name(friend.user)
			friends.append({"user_id": friend_id, "name": name})
			owner_name_by_id[friend_id] = name

	var cursor := ""
	while true:
		var payload_data := {"limit": 100}
		if not cursor.is_empty():
			payload_data["cursor"] = cursor
		var rpc_name := "list_all_levels" if list_filter == LIST_FILTER_NEWEST else "list_friend_levels"
		var result: Variant = await OnlineSession.call_rpc(rpc_name, JSON.stringify(payload_data))
		if seq != _load_seq:
			return
		if not (result is Dictionary):
			break

		var response := result as Dictionary
		for entry in response.get("levels", []):
			if not (entry is Dictionary):
				continue
			var e: Dictionary = (entry as Dictionary).duplicate(true)
			var owner_id := str(e.get("user_id", ""))
			if owner_id.is_empty():
				continue
			var entry_username := str(e.get("username", "")).strip_edges()
			if not entry_username.is_empty():
				e["owner_name"] = entry_username
			else:
				e["owner_name"] = str(owner_name_by_id.get(owner_id, owner_id.left(8)))
			entries.append(e)

		cursor = str(response.get("next_cursor", "")).strip_edges()
		if cursor.is_empty():
			break

	apply_filter()
	entries_ready.emit()


func apply_filter() -> void:
	recompute_vote_rankings()
	match list_filter:
		LIST_FILTER_BEST_SCORE:
			entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return _is_higher_vote_rank(a, b)
			)
		LIST_FILTER_NEWEST:
			entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var a_updated := LevelData.entry_updated_at(a)
				var b_updated := LevelData.entry_updated_at(b)
				if a_updated != b_updated:
					return a_updated > b_updated
				var oc := str(a.get("owner_name", "")).nocasecmp_to(str(b.get("owner_name", "")))
				if oc != 0:
					return oc < 0
				return LevelData.level_key(a).nocasecmp_to(LevelData.level_key(b)) < 0
			)
		_:
			entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var oc := str(a.get("owner_name", "")).nocasecmp_to(str(b.get("owner_name", "")))
				if oc != 0:
					return oc < 0
				return LevelData.level_key(a).nocasecmp_to(LevelData.level_key(b)) < 0
			)


func recompute_vote_rankings() -> void:
	vote_rank_by_id.clear()
	if entries.is_empty():
		return
	var ranked := entries.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _is_higher_vote_rank(a, b)
	)
	for i in range(ranked.size()):
		if not (ranked[i] is Dictionary):
			continue
		var identity := entry_identity(ranked[i] as Dictionary)
		if identity.is_empty():
			continue
		vote_rank_by_id[identity] = i + 1


func queue_missing_stats() -> void:
	if entries.is_empty():
		return
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry := entry_variant as Dictionary
		var identity := entry_identity(entry)
		if identity.is_empty():
			continue
		if entry_stats_by_id.has(identity) or _entry_stats_inflight.has(identity):
			continue
		if _is_stat_queued(identity):
			continue
		var owner_id := str(entry.get("user_id", "")).strip_edges()
		var level_key := LevelData.level_key(entry).strip_edges()
		if owner_id.is_empty() or level_key.is_empty():
			continue
		_entry_stats_queue.append({"id": identity, "owner_id": owner_id, "level_key": level_key})
	if not _stats_fetch_active:
		_process_stats_queue(_stats_fetch_seq)


func entry_identity(entry: Dictionary) -> String:
	var owner_id := str(entry.get("user_id", "")).strip_edges()
	var key := LevelData.level_key(entry).strip_edges()
	if owner_id.is_empty() or key.is_empty():
		return ""
	return "%s::%s" % [owner_id, key]


func default_stats() -> Dictionary:
	return {"best_slide_count": 0, "best_time_ms": 0, "play_count": 0}


func entry_vote_score(entry: Dictionary) -> int:
	var val: Variant = entry.get("value", {})
	if not (val is Dictionary):
		return 0
	return int((val as Dictionary).get("likes", 0)) - int((val as Dictionary).get("dislikes", 0))


func entry_likes(entry: Dictionary) -> int:
	var val: Variant = entry.get("value", {})
	if not (val is Dictionary):
		return 0
	return int((val as Dictionary).get("likes", 0))


func entry_total_votes(entry: Dictionary) -> int:
	var val: Variant = entry.get("value", {})
	if not (val is Dictionary):
		return 0
	return maxi(0, int((val as Dictionary).get("likes", 0))) + maxi(0, int((val as Dictionary).get("dislikes", 0)))


func entry_vote_rating(entry: Dictionary) -> float:
	var val: Variant = entry.get("value", {})
	if not (val is Dictionary):
		return 0.0
	var likes := maxi(0, int((val as Dictionary).get("likes", 0)))
	var dislikes := maxi(0, int((val as Dictionary).get("dislikes", 0)))
	var total := likes + dislikes
	if total <= 0:
		return 0.0
	return clampf((float(likes) / float(total)) * 5.0, 0.0, 5.0)


func _is_higher_vote_rank(a: Dictionary, b: Dictionary) -> bool:
	var a_score := entry_vote_score(a)
	var b_score := entry_vote_score(b)
	if a_score != b_score:
		return a_score > b_score
	var a_likes := entry_likes(a)
	var b_likes := entry_likes(b)
	if a_likes != b_likes:
		return a_likes > b_likes
	var owner_cmp := str(a.get("owner_name", "")).nocasecmp_to(str(b.get("owner_name", "")))
	if owner_cmp != 0:
		return owner_cmp < 0
	return LevelData.level_key(a).nocasecmp_to(LevelData.level_key(b)) < 0


func _is_stat_queued(identity: String) -> bool:
	for queued in _entry_stats_queue:
		if str(queued.get("id", "")) == identity:
			return true
	return false


func _process_stats_queue(seq: int) -> void:
	_stats_fetch_active = true
	while not _entry_stats_queue.is_empty():
		if seq != _stats_fetch_seq:
			break
		var queued: Dictionary = _entry_stats_queue.pop_front()
		var identity := str(queued.get("id", "")).strip_edges()
		var owner_id := str(queued.get("owner_id", "")).strip_edges()
		var level_key := str(queued.get("level_key", "")).strip_edges()
		if identity.is_empty() or owner_id.is_empty() or level_key.is_empty():
			continue
		if entry_stats_by_id.has(identity):
			stats_updated.emit(identity)
			continue

		_entry_stats_inflight[identity] = true
		var payload := JSON.stringify({
			"level_owner_id": owner_id,
			"level_key": level_key,
			"filter": LEADERBOARD_FILTER_ALL_TIME,
		})
		var result: Variant = await OnlineSession.call_rpc("get_leaderboard", payload)
		if seq != _stats_fetch_seq:
			_entry_stats_inflight.erase(identity)
			break

		entry_stats_by_id[identity] = _parse_stats(result)
		_entry_stats_inflight.erase(identity)
		stats_updated.emit(identity)

	if seq == _stats_fetch_seq:
		_stats_fetch_active = false


func _parse_stats(result: Variant) -> Dictionary:
	var stats := default_stats()
	if not (result is Dictionary):
		return stats

	var dict := result as Dictionary
	stats["best_slide_count"] = maxi(0, int(dict.get("best_slide_count", 0)))
	stats["best_time_ms"] = maxi(0, int(dict.get("best_time_ms", 0)))
	stats["play_count"] = maxi(0, int(dict.get("play_count", 0)))

	var entries_variant: Variant = dict.get("entries", [])
	if entries_variant is Array:
		var arr := entries_variant as Array
		if not arr.is_empty():
			var first_variant: Variant = arr[0]
			if first_variant is Dictionary:
				var first := first_variant as Dictionary
				if int(stats["best_time_ms"]) <= 0:
					stats["best_time_ms"] = maxi(0, int(first.get("time_ms", 0)))
				if int(stats["best_slide_count"]) <= 0:
					stats["best_slide_count"] = maxi(0, int(first.get("slide_count", 0)))
			if int(stats["play_count"]) <= 0:
				stats["play_count"] = arr.size()

	return stats
