class_name AuthFlow
extends RefCounted

static func needs_custom_account_gate() -> bool:
	if not OnlineSession.session:
		await OnlineSession.session_ready
	if OnlineSession.session == null:
		return false

	var account = await OnlineSession.client.get_account_async(OnlineSession.session)
	if account == null or account.is_exception():
		var fallback_username := str(OnlineSession.session.username).strip_edges()
		return fallback_username.is_empty()

	var username := str(OnlineSession.session.username).strip_edges()
	if account.user != null:
		username = str(account.user.username).strip_edges()
	var has_email := not str(account.email).strip_edges().is_empty()
	return not has_email or username.is_empty()
