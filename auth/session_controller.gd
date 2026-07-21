class_name SessionController
extends RefCounted

static func result_ok(result: Variant) -> bool:
	if result == null:
		return false
	return not result.is_exception()


static func result_error(result: Variant, fallback: String = "") -> String:
	if result != null and result.is_exception():
		var ex: NakamaException = result.get_exception()
		if ex != null:
			var msg := str(ex.message).strip_edges()
			if not msg.is_empty():
				return msg
	return fallback


static func is_auth_error(ex: NakamaException) -> bool:
	if ex == null:
		return false
	if ex.status_code == 401 or ex.grpc_status_code == 16:
		return true
	var msg := ex.message.to_lower()
	return "auth token invalid" in msg or "authentication required" in msg or "unauthorized" in msg


# Returns true if the username can be safely embedded in a synthetic email address.
# Allowed characters: letters, digits, '.', '_', '-'. '@' is always rejected.
static func is_username_email_compatible(username: String) -> bool:
	if username.contains("@"):
		return false
	for i in range(username.length()):
		var ch := username.substr(i, 1)
		var code := username.unicode_at(i)
		var is_alnum := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		if is_alnum:
			continue
		if ch == "." or ch == "_" or ch == "-":
			continue
		return false
	return true
