@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const MAIN_SCENE := "res://scenes/main.tscn"


func test_create_logout_login_uses_hidden_email_auth() -> void:
	var suffix := str(Time.get_ticks_usec())
	var username := "username%s" % suffix
	var password := "password%s" % suffix
	var expected_email := "%s@email.com" % username.to_lower()
	var device_id := "it-custom-email-auth-%s" % suffix

	OnlineSession.session = null
	OnlineSession.client = null
	OnlineSession.set("_device_id", device_id)

	var runner := scene_runner(_load_main_scene_localhost())
	await runner.simulate_frames(6)
	await _wait_until(
		runner,
		func() -> bool: return OnlineSession.session != null,
		360,
		"OnlineSession was not ready in Main scene."
	)

	var main_scene: Node = runner.scene()
	var account_entry := main_scene.find_child("CustomAccountEntry", true, false) as CanvasLayer
	var account_gate := main_scene.find_child("CustomAccountGate", true, false) as CanvasLayer
	var account_login := main_scene.find_child("CustomAccountLogin", true, false) as CanvasLayer
	var main_menu := main_scene.find_child("MainMenu", true, false) as CanvasLayer
	assert_object(account_entry).is_not_null()
	assert_object(account_gate).is_not_null()
	assert_object(account_login).is_not_null()
	assert_object(main_menu).is_not_null()

	await _wait_until(
		runner,
		func() -> bool: return account_entry.visible,
		360,
		"Custom account entry did not become visible."
	)

	var create_btn := account_entry.find_child("CreateBtn", true, false) as Button
	assert_object(create_btn).is_not_null()
	create_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return account_gate.visible,
		360,
		"Custom account gate did not open after pressing Create."
	)

	var gate_username_field := account_gate.find_child("UsernameField", true, false) as LineEdit
	var gate_password_field := account_gate.find_child("PasswordField", true, false) as LineEdit
	var gate_submit_btn := account_gate.find_child("SubmitBtn", true, false) as Button
	assert_object(gate_username_field).is_not_null()
	assert_object(gate_password_field).is_not_null()
	assert_object(gate_submit_btn).is_not_null()

	_set_line_edit(gate_username_field, username)
	_set_line_edit(gate_password_field, password)

	await _wait_until(
		runner,
		func() -> bool: return not gate_submit_btn.disabled,
		600,
		"Create submit button did not enable."
	)
	gate_submit_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return main_menu.visible,
		720,
		"Main menu did not become visible after account creation."
	)

	var created_account = await OnlineSession.client.get_account_async(OnlineSession.session)
	assert_object(created_account).is_not_null()
	assert_bool(created_account.is_exception()).is_false()
	assert_str(str(created_account.email).to_lower()).is_equal(expected_email)
	assert_str(str(created_account.user.username)).is_equal(username)
	var created_user_id := str(created_account.user.id)

	var logout_btn := main_menu.find_child("LogoutBtn", true, false) as Button
	assert_object(logout_btn).is_not_null()
	logout_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return account_entry.visible and not main_menu.visible,
		360,
		"Logout did not return to account entry."
	)

	var pre_login_device_session = await OnlineSession.client.authenticate_device_async(device_id, null, false)
	assert_object(pre_login_device_session).is_not_null()
	assert_bool(pre_login_device_session.is_exception()).is_false()
	OnlineSession.session = pre_login_device_session

	var login_btn := account_entry.find_child("LoginBtn", true, false) as Button
	assert_object(login_btn).is_not_null()
	login_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return account_login.visible,
		360,
		"Custom account login form did not open."
	)

	var login_username_field := account_login.find_child("UsernameField", true, false) as LineEdit
	var login_password_field := account_login.find_child("PasswordField", true, false) as LineEdit
	var login_submit_btn := account_login.find_child("SubmitBtn", true, false) as Button
	assert_object(login_username_field).is_not_null()
	assert_object(login_password_field).is_not_null()
	assert_object(login_submit_btn).is_not_null()

	_set_line_edit(login_username_field, username)
	_set_line_edit(login_password_field, password)

	await _wait_until(
		runner,
		func() -> bool: return not login_submit_btn.disabled,
		600,
		"Login submit button did not enable."
	)
	login_submit_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return main_menu.visible and not account_login.visible,
		720,
		"Main menu did not become visible after login."
	)

	assert_str(str(OnlineSession.session.user_id)).is_equal(created_user_id)
	var logged_in_account = await OnlineSession.client.get_account_async(OnlineSession.session)
	assert_object(logged_in_account).is_not_null()
	assert_bool(logged_in_account.is_exception()).is_false()
	assert_str(str(logged_in_account.email).to_lower()).is_equal(expected_email)

	var device_auth_session = await OnlineSession.client.authenticate_device_async(device_id, null, false)
	assert_object(device_auth_session).is_not_null()
	assert_bool(device_auth_session.is_exception()).is_false()
	var device_auth_account = await OnlineSession.client.get_account_async(device_auth_session)
	assert_object(device_auth_account).is_not_null()
	assert_bool(device_auth_account.is_exception()).is_false()
	assert_str(str(device_auth_account.user.id)).is_equal(created_user_id)

	await OnlineSession.client.delete_account_async(OnlineSession.session)


func test_failed_login_shows_error_and_create_account_button() -> void:
	var suffix := str(Time.get_ticks_usec())
	var username := "missing%s" % suffix
	var password := "password%s" % suffix
	var device_id := "it-custom-email-auth-fail-%s" % suffix

	OnlineSession.session = null
	OnlineSession.client = null
	OnlineSession.set("_device_id", device_id)

	var runner := scene_runner(_load_main_scene_localhost())
	await runner.simulate_frames(6)
	await _wait_until(
		runner,
		func() -> bool: return OnlineSession.session != null,
		360,
		"OnlineSession was not ready in Main scene."
	)

	var main_scene: Node = runner.scene()
	var account_entry := main_scene.find_child("CustomAccountEntry", true, false) as CanvasLayer
	var account_gate := main_scene.find_child("CustomAccountGate", true, false) as CanvasLayer
	var account_login := main_scene.find_child("CustomAccountLogin", true, false) as CanvasLayer
	assert_object(account_entry).is_not_null()
	assert_object(account_gate).is_not_null()
	assert_object(account_login).is_not_null()

	await _wait_until(
		runner,
		func() -> bool: return account_entry.visible,
		360,
		"Custom account entry did not become visible."
	)

	var login_btn := account_entry.find_child("LoginBtn", true, false) as Button
	assert_object(login_btn).is_not_null()
	login_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return account_login.visible,
		360,
		"Custom account login form did not open."
	)

	var login_username_field := account_login.find_child("UsernameField", true, false) as LineEdit
	var login_password_field := account_login.find_child("PasswordField", true, false) as LineEdit
	var login_submit_btn := account_login.find_child("SubmitBtn", true, false) as Button
	var login_status_label := account_login.find_child("StatusLabel", true, false) as Label
	var create_account_btn := account_login.find_child("CreateAccountBtn", true, false) as Button
	assert_object(login_username_field).is_not_null()
	assert_object(login_password_field).is_not_null()
	assert_object(login_submit_btn).is_not_null()
	assert_object(login_status_label).is_not_null()
	assert_object(create_account_btn).is_not_null()

	_set_line_edit(login_username_field, username)
	_set_line_edit(login_password_field, password)

	await _wait_until(
		runner,
		func() -> bool: return not login_submit_btn.disabled,
		600,
		"Login submit button did not enable."
	)
	login_submit_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return login_status_label.visible and create_account_btn.visible,
		600,
		"Failed login did not show status and create account button."
	)
	assert_str(login_status_label.text.to_lower()).contains("not found")

	create_account_btn.emit_signal("pressed")
	await _wait_until(
		runner,
		func() -> bool: return account_gate.visible and not account_login.visible,
		360,
		"Create account button did not open custom account gate."
	)

	await OnlineSession.client.delete_account_async(OnlineSession.session)


func _load_main_scene_localhost() -> Node2D:
	var main_scene := auto_free(load(MAIN_SCENE).instantiate()) as Node2D
	main_scene.set("use_local_server", true)
	return main_scene


func _set_line_edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.emit_signal("text_changed", value)


func _wait_until(runner, predicate: Callable, max_frames: int, failure_message: String) -> void:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return
		await runner.simulate_frames(1)
	assert_bool(bool(predicate.call())).override_failure_message(failure_message).is_true()
