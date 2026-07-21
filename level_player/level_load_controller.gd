class_name LevelLoadController
extends RefCounted

func fetch_level(key: String, owner_id: String) -> Dictionary:
	var resolved_owner := owner_id if not owner_id.is_empty() else str(OnlineSession.session.user_id)
	var payload := JSON.stringify({"user_id": resolved_owner, "key": key})
	var result = await OnlineSession.call_rpc("get_level", payload)
	if result == null:
		return {}
	return result


func submit_score(level_owner_id: String, level_key: String, time_ms: int, slide_count: int) -> int:
	var payload := JSON.stringify({
		"level_owner_id": level_owner_id,
		"level_key": level_key,
		"time_ms": time_ms,
		"slide_count": slide_count,
	})
	var result = await OnlineSession.call_rpc("submit_score", payload)
	if result:
		return int(result.get("rank", 0))
	return 0
