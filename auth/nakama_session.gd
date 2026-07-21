extends Node

var client: NakamaClient
var session: NakamaSession
var last_rpc_error: String = ""

signal session_ready
signal session_failed(error: String)

const TOKEN_REFRESH_SKEW_SECONDS := 30

var _device_id: String


func _ready() -> void:
	_device_id = _get_or_create_device_id()


func start(use_local: bool) -> void:
	if use_local:
		client = Nakama.create_client(
			"defaultkey",
			"127.0.0.1",
			7350,
			"http"
		)
	else:
		client = Nakama.create_client(
			"JHRVkiPgIpqyxCTm",
			"brackeys-jam-bb2c.us-east1.nakamacloud.io",
			443,
			"https"
		)
	await _authenticate()


func _authenticate() -> bool:
	var auth_result := await client.authenticate_device_async(_device_id)
	if auth_result.is_exception():
		session = null
		var err_msg := "Nakama auth failed: %s" % auth_result.get_exception().message
		push_error(err_msg)
		session_failed.emit(err_msg)
		return false
	session = auth_result
	print("Nakama authenticated as: %s" % session.user_id)
	session_ready.emit()
	return true


func link_current_device_after_login(target_session: NakamaSession, previous_session: NakamaSession = null) -> String:
	if client == null:
		return "Nakama client unavailable."
	if target_session == null:
		return "Session unavailable."

	var device_id := _device_id.strip_edges()
	if device_id.is_empty():
		return "Device ID unavailable."

	var link_result = await client.link_device_async(target_session, device_id)
	if SessionController.result_ok(link_result):
		return ""

	var link_error := SessionController.result_error(link_result, "Could not link device.")

	var check_session = await client.authenticate_device_async(device_id, null, false)
	if check_session != null and not check_session.is_exception():
		if str(check_session.user_id) == str(target_session.user_id):
			return ""

	if previous_session != null and str(previous_session.user_id) != str(target_session.user_id):
		var unlink_result = await client.unlink_device_async(previous_session, device_id)
		if SessionController.result_ok(unlink_result):
			var relink_result = await client.link_device_async(target_session, device_id)
			if SessionController.result_ok(relink_result):
				return ""
			link_error = SessionController.result_error(relink_result, link_error)
		else:
			var unlink_error := SessionController.result_error(unlink_result, "")
			if "last account identifier" in unlink_error.to_lower():
				if await _delete_device_only_account(previous_session, device_id):
					var relink_after_delete = await client.link_device_async(target_session, device_id)
					if SessionController.result_ok(relink_after_delete):
						return ""
					link_error = SessionController.result_error(relink_after_delete, link_error)
				elif not unlink_error.is_empty():
					link_error = unlink_error
			elif not unlink_error.is_empty():
				link_error = unlink_error

	return link_error


func _delete_device_only_account(candidate_session: NakamaSession, device_id: String) -> bool:
	if client == null or candidate_session == null:
		return false

	var account = await client.get_account_async(candidate_session)
	if account == null or account.is_exception():
		return false
	if not str(account.email).strip_edges().is_empty():
		return false
	if not str(account.custom_id).strip_edges().is_empty():
		return false

	var has_target_device := false
	var device_count := 0
	for device in account.devices:
		device_count += 1
		if str(device.id).strip_edges() == device_id:
			has_target_device = true

	if not has_target_device or device_count != 1:
		return false

	var delete_result = await client.delete_account_async(candidate_session)
	return SessionController.result_ok(delete_result)


func _refresh_session_or_authenticate() -> bool:
	if session and session.refresh_token != "" and not session.is_refresh_expired():
		var refreshed := await client.session_refresh_async(session)
		if not refreshed.is_exception():
			session = refreshed
			session_ready.emit()
			return true
		push_warning("Session refresh failed: %s" % refreshed.get_exception().message)
	return await _authenticate()


func _ensure_valid_session() -> bool:
	if session and session.is_valid() and not session.is_expired():
		if session.would_expire_in(TOKEN_REFRESH_SKEW_SECONDS):
			return await _refresh_session_or_authenticate()
		return true
	return await _refresh_session_or_authenticate()


func call_rpc(id: String, payload: String = "") -> Variant:
	last_rpc_error = ""
	var has_session := await _ensure_valid_session()
	if not has_session:
		last_rpc_error = "authentication required"
		return null

	var result = await client.rpc_async(session, id, payload)
	if result.is_exception():
		var ex: NakamaException = result.get_exception()
		if SessionController.is_auth_error(ex):
			push_warning("RPC %s auth failed. Refreshing session and retrying." % id)
			if await _refresh_session_or_authenticate():
				result = await client.rpc_async(session, id, payload)

		if result.is_exception():
			last_rpc_error = str(result.get_exception().message)
			push_warning("RPC %s failed: %s" % [id, last_rpc_error])
			return null
	var parsed: Variant = JSON.parse_string(result.payload)
	return LevelData.normalize(id, parsed)


func _get_or_create_device_id() -> String:
	var path := "user://device_id.txt"
	if FileAccess.file_exists(path):
		var read_file := FileAccess.open(path, FileAccess.READ)
		var id := read_file.get_line().strip_edges()
		read_file.close()
		return id
	var id := _generate_uuid()
	var write_file := FileAccess.open(path, FileAccess.WRITE)
	write_file.store_line(id)
	write_file.close()
	return id


# NOTE: RandomNumberGenerator.randomize() seeds from system time, not a CSPRNG.
# For a sample project this is fine, but a production game storing a persistent
# auth credential should use Crypto.generate_random_bytes() instead.
func _generate_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hex := ""
	for i in 16:
		hex += "%02x" % rng.randi_range(0, 255)
	return hex
