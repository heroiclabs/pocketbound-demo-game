@warning_ignore_start("redundant_await")
extends GdUnitTestSuite

const MAIN_SCENE := "res://scenes/main.tscn"


func test_account_setup_form_create_with_lowercase_email() -> void:
	var suffix := str(Time.get_ticks_usec())
	var username := "setupuser%s" % suffix
	var password := "password%s" % suffix
	var email_input := "setup%s@email.com" % suffix
	var expected_email := email_input.to_lower()
	var device_id := "it-setup-email-lower-%s" % suffix

	await _create_account_via_setup_form(device_id, username, email_input, password, expected_email)


func test_account_setup_form_create_with_uppercase_email_normalizes_to_lowercase() -> void:
	var suffix := str(Time.get_ticks_usec())
	var username := "setupusercaps%s" % suffix
	var password := "password%s" % suffix
	var email_input := "Setup.Email.%s@Example.COM" % suffix
	var expected_email := email_input.to_lower()
	var device_id := "it-setup-email-caps-%s" % suffix

	await _create_account_via_setup_form(device_id, username, email_input, password, expected_email)


func _create_account_via_setup_form(
	device_id: String,
	username: String,
	email_input: String,
	password: String,
	expected_email: String
) -> void:
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
	var main_menu := main_scene.find_child("MainMenu", true, false) as CanvasLayer
	assert_object(main_menu).is_not_null()
	main_menu.call("_show_friends_content", false)

	var setup_form := main_menu.find_child("AccountSetupForm", true, false) as VBoxContainer
	var setup_username_field := main_menu.find_child("SetupUsernameField", true, false) as LineEdit
	var setup_email_field := main_menu.find_child("SetupEmailField", true, false) as LineEdit
	var setup_password_field := main_menu.find_child("SetupPasswordField", true, false) as LineEdit
	var setup_submit_btn := main_menu.find_child("SetupSubmitBtn", true, false) as Button
	assert_object(setup_form).is_not_null()
	assert_object(setup_username_field).is_not_null()
	assert_object(setup_email_field).is_not_null()
	assert_object(setup_password_field).is_not_null()
	assert_object(setup_submit_btn).is_not_null()
	assert_bool(setup_form.visible).is_true()

	_set_line_edit(setup_username_field, username)
	_set_line_edit(setup_email_field, email_input)
	_set_line_edit(setup_password_field, password)

	await _wait_until(
		runner,
		func() -> bool: return not setup_submit_btn.disabled,
		720,
		"Account setup submit button did not enable."
	)
	setup_submit_btn.emit_signal("pressed")

	await _wait_until(
		runner,
		func() -> bool: return bool(main_menu.get("_has_email")),
		720,
		"Main menu did not mark account as linked after setup submit."
	)

	var account = await OnlineSession.client.get_account_async(OnlineSession.session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.email)).is_equal(expected_email)

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
