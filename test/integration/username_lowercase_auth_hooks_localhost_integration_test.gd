extends GdUnitTestSuite


func test_before_authenticate_email_forces_lowercase_username_on_create() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var username_input := "MixedCaseUser%s" % suffix
	var expected_username := username_input.to_lower()
	var email := "it-lower-create-%s@email.com" % suffix
	var password := "password%s" % suffix

	var session := await client.authenticate_email_async(email, password, username_input, true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()
	assert_bool(session.is_valid()).is_true()

	var account = await client.get_account_async(session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.user.username)).is_equal(expected_username)

	await client.delete_account_async(session)


func test_after_authenticate_email_lowercases_existing_username_on_login() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var legacy_username := "LegacyCaseUser%s" % suffix
	var expected_username := legacy_username.to_lower()
	var device_id := "it-lower-login-%s" % suffix
	var email := "it-lower-login-%s@email.com" % suffix
	var password := "password%s" % suffix

	# Use device auth to simulate a legacy account with mixed-case username.
	var device_session := await client.authenticate_device_async(device_id, legacy_username, true)
	assert_object(device_session).is_not_null()
	assert_bool(device_session.is_exception()).is_false()
	assert_bool(device_session.is_valid()).is_true()

	var link_result := await client.link_email_async(device_session, email, password)
	assert_object(link_result).is_not_null()
	assert_bool(link_result.is_exception()).is_false()

	var before_login_account = await client.get_account_async(device_session)
	assert_object(before_login_account).is_not_null()
	assert_bool(before_login_account.is_exception()).is_false()
	assert_str(str(before_login_account.user.username)).is_equal(legacy_username)

	# Login through email; after-auth hook should normalize stored username.
	var email_session = await client.authenticate_email_async(email, password, null, false)
	assert_object(email_session).is_not_null()
	assert_bool(email_session.is_exception()).is_false()
	assert_bool(email_session.is_valid()).is_true()

	var after_login_account = await client.get_account_async(email_session)
	assert_object(after_login_account).is_not_null()
	assert_bool(after_login_account.is_exception()).is_false()
	assert_str(str(after_login_account.user.username)).is_equal(expected_username)

	await client.delete_account_async(email_session)


func _new_local_client() -> NakamaClient:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()
	return client
