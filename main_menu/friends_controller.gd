class_name FriendsController
extends RefCounted

const FRIEND_STATE_NONE := -1
const FRIEND_STATE_FRIEND := 0
const FRIEND_STATE_INVITE_SENT := 1
const FRIEND_STATE_INVITE_RECEIVED := 2
const FRIEND_STATE_BLOCKED := 3

var friends: Array = []
var selected_friend_id: String = ""


func load_friends() -> bool:
	friends.clear()
	var friends_result = await OnlineSession.client.list_friends_async(OnlineSession.session, null, 100, null)
	if friends_result == null or friends_result.is_exception():
		return false

	for friend in friends_result.friends:
		if friend == null or friend.user == null:
			continue
		var state_variant: Variant = friend.get("state")
		var state := FRIEND_STATE_FRIEND
		if state_variant is int or state_variant is float:
			state = int(state_variant)
		elif state_variant != null:
			var state_text := str(state_variant).strip_edges()
			if state_text.is_valid_int():
				state = state_text.to_int()
		friends.append({
			"user_id": str(friend.user.id),
			"name": display_name(friend.user),
			"online": bool(friend.user.online),
			"state": state,
		})

	friends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_state := int(a.get("state", FRIEND_STATE_FRIEND))
		var b_state := int(b.get("state", FRIEND_STATE_FRIEND))
		var a_rank := sort_rank(a_state)
		var b_rank := sort_rank(b_state)
		if a_rank != b_rank:
			return a_rank < b_rank
		if a_state == FRIEND_STATE_FRIEND and b_state == FRIEND_STATE_FRIEND:
			var a_online := bool(a.get("online", false))
			var b_online := bool(b.get("online", false))
			if a_online != b_online:
				return a_online and not b_online
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)

	if friends.is_empty():
		selected_friend_id = ""
	elif selected_friend_id == "" or not friend_exists(selected_friend_id):
		selected_friend_id = first_selectable_friend_id()

	if not selected_friend_id.is_empty() and state_for(selected_friend_id) != FRIEND_STATE_FRIEND:
		selected_friend_id = first_selectable_friend_id()

	return true


func state_for(user_id: String) -> int:
	if user_id.is_empty():
		return FRIEND_STATE_NONE
	for friend in friends:
		if str(friend.get("user_id", "")) == user_id:
			return int(friend.get("state", FRIEND_STATE_FRIEND))
	return FRIEND_STATE_NONE


func count_by_state(state: int) -> int:
	var count := 0
	for friend in friends:
		if int(friend.get("state", FRIEND_STATE_FRIEND)) == state:
			count += 1
	return count


func first_selectable_friend_id() -> String:
	for friend in friends:
		if int(friend.get("state", FRIEND_STATE_FRIEND)) == FRIEND_STATE_FRIEND:
			var user_id := str(friend.get("user_id", ""))
			if not user_id.is_empty():
				return user_id
	return ""


func friend_exists(user_id: String) -> bool:
	return state_for(user_id) == FRIEND_STATE_FRIEND


func name_by_id(user_id: String) -> String:
	if user_id.is_empty():
		return ""
	for friend in friends:
		if str(friend.get("user_id", "")) == user_id and int(friend.get("state", FRIEND_STATE_FRIEND)) == FRIEND_STATE_FRIEND:
			return str(friend.get("name", ""))
	return ""


static func sort_rank(state: int) -> int:
	match state:
		FRIEND_STATE_INVITE_RECEIVED:
			return 0
		FRIEND_STATE_FRIEND:
			return 1
		FRIEND_STATE_INVITE_SENT:
			return 2
		FRIEND_STATE_BLOCKED:
			return 3
		_:
			return 4


static func relation_suffix(state: int) -> String:
	match state:
		FRIEND_STATE_INVITE_RECEIVED:
			return "[incoming request]"
		FRIEND_STATE_INVITE_SENT:
			return ""
		FRIEND_STATE_BLOCKED:
			return "[blocked]"
		_:
			return ""


static func display_name(user: NakamaAPI.ApiUser) -> String:
	var d := str(user.display_name).strip_edges()
	if not d.is_empty():
		return d
	var u := str(user.username).strip_edges()
	if not u.is_empty():
		return u
	return str(user.id).left(8)
