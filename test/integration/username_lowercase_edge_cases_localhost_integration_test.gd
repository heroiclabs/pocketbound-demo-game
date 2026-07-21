extends GdUnitTestSuite


# --- beforeAuthenticateEmail edge cases ---


func test_before_authenticate_email_rejects_profane_username() -> void:
	# goaway v1.1.9 detects known compound profane words (e.g. "asshole")
	# and profane words followed by only digits (e.g. "asshole123").
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var profane_username := "asshole%s" % suffix
	var email := "it-profane-auth-%s@email.com" % suffix
	var password := "password%s" % suffix

	var session := await client.authenticate_email_async(email, password, profane_username, true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_true()


func test_before_authenticate_email_rejects_profane_username_uppercase() -> void:
	# Same profane word but UPPER-CASED. The hook lowercases before checking
	# profanity. goaway is itself case-insensitive, so this verifies the full
	# normalization + profanity pipeline end-to-end.
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var profane_username := "ASSHOLE%s" % suffix
	var email := "it-profane-upper-%s@email.com" % suffix
	var password := "password%s" % suffix

	var session := await client.authenticate_email_async(email, password, profane_username, true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_true()


func test_before_authenticate_email_allows_login_without_username() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var username := "loginnouser%s" % suffix
	var email := "it-no-username-%s@email.com" % suffix
	var password := "password%s" % suffix

	# Create account first.
	var create_session := await client.authenticate_email_async(email, password, username, true)
	assert_object(create_session).is_not_null()
	assert_bool(create_session.is_exception()).is_false()

	# Login again without specifying a username; beforeAuthenticateEmail should
	# skip normalization and the request should succeed.
	var login_session := await client.authenticate_email_async(email, password, "", false)
	assert_object(login_session).is_not_null()
	assert_bool(login_session.is_exception()).is_false()
	assert_bool(login_session.is_valid()).is_true()

	var account = await client.get_account_async(login_session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.user.username)).is_equal(username)

	await client.delete_account_async(login_session)


func test_before_authenticate_email_create_without_username_succeeds() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var email := "it-auto-gen-%s@email.com" % suffix
	var password := "password%s" % suffix

	# Create with empty username — Nakama auto-generates one.
	# beforeAuthenticateEmail skips (username is ""), afterAuthenticateEmail
	# skips (out.Created is true). Nakama generates mixed-case random names
	# which are NOT normalized by either hook; the client UI is expected to
	# prompt for a username after the first device-auth login anyway.
	var session := await client.authenticate_email_async(email, password, "", true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()
	assert_bool(session.is_valid()).is_true()

	var account = await client.get_account_async(session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	var auto_username := str(account.user.username)
	assert_bool(auto_username.is_empty()).is_false()

	await client.delete_account_async(session)


# --- afterAuthenticateEmail edge cases ---


func test_after_authenticate_email_skips_already_lowercase_username() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var lowercase_username := "alreadylower%s" % suffix
	var device_id := "it-already-lower-%s" % suffix
	var email := "it-already-lower-%s@email.com" % suffix
	var password := "password%s" % suffix

	# Create a device account that is already lowercase.
	var device_session := await client.authenticate_device_async(device_id, lowercase_username, true)
	assert_object(device_session).is_not_null()
	assert_bool(device_session.is_exception()).is_false()

	var link_result := await client.link_email_async(device_session, email, password)
	assert_object(link_result).is_not_null()
	assert_bool(link_result.is_exception()).is_false()

	# Login via email; afterAuthenticateEmail should detect normalized == username
	# and skip the UPDATE entirely.
	var email_session := await client.authenticate_email_async(email, password, "", false)
	assert_object(email_session).is_not_null()
	assert_bool(email_session.is_exception()).is_false()

	var account = await client.get_account_async(email_session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.user.username)).is_equal(lowercase_username)

	await client.delete_account_async(email_session)


func test_after_authenticate_email_skips_newly_created_account() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var username := "newcreate%s" % suffix
	var email := "it-new-create-%s@email.com" % suffix
	var password := "password%s" % suffix

	# Create via email auth. beforeAuthenticateEmail lowercases the username.
	# afterAuthenticateEmail sees out.Created == true and skips.
	var session := await client.authenticate_email_async(email, password, username, true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()

	var account = await client.get_account_async(session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.user.username)).is_equal(username)

	await client.delete_account_async(session)


func test_after_authenticate_email_second_login_is_noop() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var legacy_username := "SecondLogin%s" % suffix
	var expected_username := legacy_username.to_lower()
	var device_id := "it-second-login-%s" % suffix
	var email := "it-second-login-%s@email.com" % suffix
	var password := "password%s" % suffix

	# Create legacy mixed-case account via device auth.
	var device_session := await client.authenticate_device_async(device_id, legacy_username, true)
	assert_object(device_session).is_not_null()
	assert_bool(device_session.is_exception()).is_false()

	var link_result := await client.link_email_async(device_session, email, password)
	assert_object(link_result).is_not_null()
	assert_bool(link_result.is_exception()).is_false()

	# First email login — normalizes the username.
	var first_login := await client.authenticate_email_async(email, password, "", false)
	assert_object(first_login).is_not_null()
	assert_bool(first_login.is_exception()).is_false()

	var after_first = await client.get_account_async(first_login)
	assert_str(str(after_first.user.username)).is_equal(expected_username)

	# Second email login — username is already lowercase, so it should be a no-op.
	var second_login := await client.authenticate_email_async(email, password, "", false)
	assert_object(second_login).is_not_null()
	assert_bool(second_login.is_exception()).is_false()

	var after_second = await client.get_account_async(second_login)
	assert_str(str(after_second.user.username)).is_equal(expected_username)

	await client.delete_account_async(second_login)


func test_after_authenticate_email_resolves_collision_with_fallback_name() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var canonical_username := "collide%s" % suffix
	var mixed_case_username := "Collide%s" % suffix
	var device_id_a := "it-collide-a-%s" % suffix
	var device_id_b := "it-collide-b-%s" % suffix
	var email_b := "it-collide-b-%s@email.com" % suffix
	var password_b := "password%s" % suffix

	# User A owns the canonical lowercase username.
	var session_a := await client.authenticate_device_async(device_id_a, canonical_username, true)
	assert_object(session_a).is_not_null()
	assert_bool(session_a.is_exception()).is_false()

	# User B has a mixed-case variant (legacy account via device auth).
	var session_b := await client.authenticate_device_async(device_id_b, mixed_case_username, true)
	assert_object(session_b).is_not_null()
	assert_bool(session_b.is_exception()).is_false()

	# Grab user B's ID before the rename.
	var account_b_before = await client.get_account_async(session_b)
	assert_object(account_b_before).is_not_null()
	assert_bool(account_b_before.is_exception()).is_false()
	var user_b_id := str(account_b_before.user.id)
	assert_str(str(account_b_before.user.username)).is_equal(mixed_case_username)

	# Link email to user B so we can trigger afterAuthenticateEmail.
	var link_result := await client.link_email_async(session_b, email_b, password_b)
	assert_object(link_result).is_not_null()
	assert_bool(link_result.is_exception()).is_false()

	# Login user B via email. The after-hook tries "collide<suffix>" (taken by A),
	# so it falls back to "collide<suffix>_<B_id_no_dashes>".
	var email_session := await client.authenticate_email_async(email_b, password_b, "", false)
	assert_object(email_session).is_not_null()
	assert_bool(email_session.is_exception()).is_false()

	var account_b_after = await client.get_account_async(email_session)
	assert_object(account_b_after).is_not_null()
	assert_bool(account_b_after.is_exception()).is_false()
	var final_username := str(account_b_after.user.username)

	# Must not be the original mixed-case or the canonical (taken by A).
	assert_str(final_username).is_not_equal(mixed_case_username)
	assert_str(final_username).is_not_equal(canonical_username)

	# Verify the fallback format: base + "_" + id_token.
	var id_token := user_b_id.replace("-", "").to_lower()
	var expected_fallback := canonical_username + "_" + id_token
	assert_str(final_username).is_equal(expected_fallback)

	# Cleanup both accounts.
	await client.delete_account_async(email_session)
	await client.delete_account_async(session_a)


func test_after_authenticate_email_deep_collision_uses_numeric_suffix() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var canonical_username := "deep%s" % suffix
	var mixed_case_username := "Deep%s" % suffix
	var device_id_a := "it-deep-a-%s" % suffix
	var device_id_b := "it-deep-b-%s" % suffix
	var device_id_x := "it-deep-x-%s" % suffix
	var email_b := "it-deep-b-%s@email.com" % suffix
	var password_b := "password%s" % suffix

	# User A owns the canonical lowercase name (blocks attempt=0).
	var session_a := await client.authenticate_device_async(device_id_a, canonical_username, true)
	assert_object(session_a).is_not_null()
	assert_bool(session_a.is_exception()).is_false()

	# User B — the one who will be renamed (legacy mixed-case).
	var session_b := await client.authenticate_device_async(device_id_b, mixed_case_username, true)
	assert_object(session_b).is_not_null()
	assert_bool(session_b.is_exception()).is_false()

	# Get B's user ID so we can pre-occupy B's first fallback candidate.
	var account_b = await client.get_account_async(session_b)
	var user_b_id := str(account_b.user.id)
	var id_token := user_b_id.replace("-", "").to_lower()

	# User X takes the name that would be B's attempt=1 candidate.
	var first_fallback := canonical_username + "_" + id_token
	var session_x := await client.authenticate_device_async(device_id_x, first_fallback, true)
	assert_object(session_x).is_not_null()
	assert_bool(session_x.is_exception()).is_false()

	# Link email to B.
	var link_result := await client.link_email_async(session_b, email_b, password_b)
	assert_object(link_result).is_not_null()
	assert_bool(link_result.is_exception()).is_false()

	# Login B via email. attempt=0 "deep<suffix>" taken by A,
	# attempt=1 "deep<suffix>_<B_id>" taken by X,
	# attempt=2 should produce "deep<suffix>_<B_id>_1".
	var email_session := await client.authenticate_email_async(email_b, password_b, "", false)
	assert_object(email_session).is_not_null()
	assert_bool(email_session.is_exception()).is_false()

	var account_b_after = await client.get_account_async(email_session)
	assert_object(account_b_after).is_not_null()
	assert_bool(account_b_after.is_exception()).is_false()

	var expected_deep_fallback := canonical_username + "_" + id_token + "_1"
	assert_str(str(account_b_after.user.username)).is_equal(expected_deep_fallback)

	# Cleanup all three accounts.
	await client.delete_account_async(email_session)
	await client.delete_account_async(session_x)
	await client.delete_account_async(session_a)


# --- beforeUpdateAccount ---


func test_before_update_account_normalizes_mixed_case_username() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var original_username := "updateuser%s" % suffix
	var new_mixed_case := "UpdatedName%s" % suffix
	var expected_username := new_mixed_case.to_lower()
	var email := "it-update-lower-%s@email.com" % suffix
	var password := "password%s" % suffix

	var session := await client.authenticate_email_async(email, password, original_username, true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()

	# Update username to mixed case; beforeUpdateAccount should normalize it.
	var update_result = await client.update_account_async(session, new_mixed_case)
	assert_object(update_result).is_not_null()
	assert_bool(update_result.is_exception()).is_false()

	var account = await client.get_account_async(session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.user.username)).is_equal(expected_username)

	await client.delete_account_async(session)


func test_before_update_account_rejects_profane_username() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var original_username := "cleanuser%s" % suffix
	var profane_update := "asshole%s" % suffix
	var email := "it-update-profane-%s@email.com" % suffix
	var password := "password%s" % suffix

	var session := await client.authenticate_email_async(email, password, original_username, true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()

	# Attempt to update username to something profane; should be rejected.
	var update_result = await client.update_account_async(session, profane_update)
	assert_object(update_result).is_not_null()
	assert_bool(update_result.is_exception()).is_true()

	# Verify original username is unchanged.
	var account = await client.get_account_async(session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.user.username)).is_equal(original_username)

	await client.delete_account_async(session)


func test_before_update_account_allows_null_username() -> void:
	var client: NakamaClient = _new_local_client()
	var suffix := str(Time.get_ticks_usec())
	var original_username := "nullupdate%s" % suffix
	var email := "it-null-update-%s@email.com" % suffix
	var password := "password%s" % suffix

	var session := await client.authenticate_email_async(email, password, original_username, true)
	assert_object(session).is_not_null()
	assert_bool(session.is_exception()).is_false()

	# Update account with null username (only other fields); the hook should skip.
	var update_result = await client.update_account_async(session, null, "SomeDisplayName")
	assert_object(update_result).is_not_null()
	assert_bool(update_result.is_exception()).is_false()

	# Username should be unchanged.
	var account = await client.get_account_async(session)
	assert_object(account).is_not_null()
	assert_bool(account.is_exception()).is_false()
	assert_str(str(account.user.username)).is_equal(original_username)

	await client.delete_account_async(session)


# --- Helpers ---


func _new_local_client() -> NakamaClient:
	var client := Nakama.create_client(
		"defaultkey",
		"127.0.0.1",
		7350,
		"http"
	)
	assert_object(client).is_not_null()
	return client
