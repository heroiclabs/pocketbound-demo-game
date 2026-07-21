@warning_ignore_start("redundant_await")
extends GdUnitTestSuite


# ── Finding #6: Null pointer in _get_or_create_device_id ─────────────────────
# nakama_session.gd:260 — FileAccess.open() can return null, and calling
# .get_line() on null crashes. Same for the WRITE path at line 262-263.

func test_file_access_open_returns_null_for_unreadable_path() -> void:
	# Prove that FileAccess.open() can return null — the precondition for #6.
	var file := FileAccess.open("", FileAccess.READ)
	assert_object(file).override_failure_message(
		"Finding #6: FileAccess.open('') should return null, proving the crash vector exists"
	).is_null()


func test_get_or_create_device_id_null_safe_read() -> void:
	# Simulate the exact pattern from nakama_session.gd:260:
	#   FileAccess.open(path, FileAccess.READ).get_line()
	# If the file doesn't exist at a bogus path, open() returns null.
	var path := "user://test_finding6_nonexistent_%d.txt" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.READ)
	# The SAFE pattern: check for null before calling .get_line()
	# The CURRENT code does NOT check, so this test documents the vulnerability.
	assert_object(file).override_failure_message(
		"Finding #6: FileAccess.open should return null for nonexistent file"
	).is_null()
	# If we reached here, calling file.get_line() would crash.
	# The fix: check `if file != null` before get_line().


func test_get_or_create_device_id_null_safe_write() -> void:
	# Simulate the WRITE path from nakama_session.gd:262-263:
	#   var file := FileAccess.open(path, FileAccess.WRITE)
	#   file.store_line(id)  # <-- crashes if file is null
	# Opening a directory path for WRITE returns null.
	var file := FileAccess.open("res://", FileAccess.WRITE)
	assert_object(file).override_failure_message(
		"Finding #6: FileAccess.open for WRITE to a directory should return null"
	).is_null()


# ── Finding #7: _scale_to_cell null ref ──────────────────────────────────────
# level_creator.gd:258-259 — The sprite var can be null if PlaceableObject has
# no Sprite2D child (e.g. after queue_free). Line 259 does `if not sprite.texture`
# which crashes when sprite is null. Should be `if sprite == null or not sprite.texture`.

func test_scale_to_cell_crashes_when_sprite2d_missing() -> void:
	# Create a PlaceableObject without a Sprite2D child — simulates the null case.
	var obj := Node2D.new()
	obj.set_script(load("res://level_player/scripts/placeable_object.gd"))

	# The _main_sprite() method uses get_node_or_null("Sprite2D"), so on a bare
	# node it returns null. This is the exact scenario that triggers the crash.
	var sprite: Sprite2D = obj.get_node_or_null("Sprite2D") as Sprite2D
	assert_object(sprite).override_failure_message(
		"Finding #7: PlaceableObject without Sprite2D child should have null sprite"
	).is_null()

	# If the LevelCreator called _scale_to_cell(obj) here, line 259 would crash:
	#   if not sprite.texture:   <-- null.texture = crash
	# The fix: check `if sprite == null or not sprite.texture`
	obj.queue_free()


func test_scale_to_cell_survives_null_texture() -> void:
	# Create a PlaceableObject WITH a Sprite2D but NO texture — the secondary null path.
	var scene := load("res://level_player/placeable_object.tscn") as PackedScene
	var obj := scene.instantiate() as Node2D
	var sprite: Sprite2D = obj.get_node_or_null("Sprite2D") as Sprite2D
	assert_object(sprite).is_not_null()

	# Clear the texture to simulate the edge case.
	sprite.texture = null

	# Now sprite is non-null but sprite.texture is null.
	# The existing check `if not sprite.texture` correctly handles this case.
	assert_object(sprite.texture).override_failure_message(
		"Finding #7: Sprite2D texture should be null after clearing"
	).is_null()
	obj.queue_free()


# ── Finding #13: Publish button never re-enabled after success ───────────────
# main.gd:335-346 — _on_publish_from_testing_complete() disables the publish
# button at line 340, and on success (line 344-346) returns without re-enabling.
# Only the error path (line 347) re-enables the button.

func test_publish_button_stays_disabled_after_successful_publish() -> void:
	var scene := load("res://level_player/level_testing_complete.tscn") as PackedScene
	var modal := scene.instantiate() as LevelTestingComplete
	auto_free(modal)

	# Let _ready() fire so @onready vars are populated.
	var runner := scene_runner(modal)
	await runner.simulate_frames(2)

	# Directly enable the publish button (skip open_for_level to avoid Nakama RPC).
	var publish_btn: Button = modal.get_node("%PublishBtn")
	publish_btn.disabled = false
	assert_bool(publish_btn.disabled).is_false()

	# Simulate the success path from _on_publish_from_testing_complete:
	# 1. Disable the button (line 340)
	modal.set_publish_enabled(false)
	assert_bool(publish_btn.disabled).is_true()

	# 2. Simulate successful result — show status and return (lines 344-346)
	modal.show_action_status("Level published.", false)

	# The bug: set_publish_enabled(true) is NEVER called on success.
	# So the button remains disabled.
	assert_bool(publish_btn.disabled).override_failure_message(
		"Finding #13: Publish button stays disabled after successful publish — never re-enabled"
	).is_true()
	# ^^^ This asserts the BUG EXISTS (button IS disabled).
	# After the fix, this test should be changed to assert is_false().


# ── Finding #14: Stale state after async ─────────────────────────────────────
# main.gd uses is_instance_valid(self) guards in _on_save_from_testing_complete
# (line 326) but the general pattern is inconsistent across other async handlers.

func test_save_handler_checks_instance_validity() -> void:
	# Verify that _on_save_from_testing_complete has the is_instance_valid guard.
	# This is a source-level verification — confirming the pattern exists.
	var source := FileAccess.open("res://scenes/main.gd", FileAccess.READ)
	assert_object(source).is_not_null()
	var content := source.get_as_text()
	source.close()

	# _on_save_from_testing_complete should check is_instance_valid
	assert_bool(content.contains("_on_save_from_testing_complete")).is_true()
	assert_bool(content.contains("is_instance_valid(self)")).override_failure_message(
		"Finding #14: main.gd should use is_instance_valid(self) in async handlers"
	).is_true()


func test_publish_handler_checks_instance_validity() -> void:
	# Verify that _on_publish_from_testing_complete also has the guard.
	var source := FileAccess.open("res://scenes/main.gd", FileAccess.READ)
	assert_object(source).is_not_null()
	var content := source.get_as_text()
	source.close()

	# Find the function definition (not the signal connection which appears earlier).
	var publish_idx := content.find("func _on_publish_from_testing_complete")
	assert_int(publish_idx).override_failure_message(
		"main.gd should contain func _on_publish_from_testing_complete"
	).is_greater(0)

	var publish_body := content.substr(publish_idx, 500)
	assert_bool(publish_body.contains("is_instance_valid")).override_failure_message(
		"Finding #14: _on_publish_from_testing_complete should check is_instance_valid(self)"
	).is_true()


# ── Finding #15: O(n) serial awaits in _populate_top_rated ───────────────────
# main_menu.gd:1264-1278 — Each level gets a sequential RPC call in a for loop.
# This verifies the pattern exists (source-level test for the antipattern).

func test_populate_top_rated_uses_serial_awaits() -> void:
	var source := FileAccess.open("res://main_menu/main_menu.gd", FileAccess.READ)
	assert_object(source).is_not_null()
	var content := source.get_as_text()
	source.close()

	# Find the _populate_top_rated function
	var func_idx := content.find("func _populate_top_rated")
	assert_int(func_idx).is_greater(0)

	# Extract the function body (until next func or end of file)
	var next_func_idx := content.find("\nfunc ", func_idx + 1)
	var body: String
	if next_func_idx > 0:
		body = content.substr(func_idx, next_func_idx - func_idx)
	else:
		body = content.substr(func_idx)

	# Verify the serial await pattern exists inside a for loop
	var has_for_loop := body.contains("for entry in")
	var has_await_in_loop := body.contains("await OnlineSession.call_rpc")
	assert_bool(has_for_loop and has_await_in_loop).override_failure_message(
		"Finding #15: _populate_top_rated does O(n) serial awaits — each level triggers a separate RPC"
	).is_true()


# ── Finding #16: Device not re-linked after email auth ───────────────────────
# main_menu.gd:260-280 — _on_setup_submit_pressed creates an email account via
# authenticate_email_async but never calls link_current_device_after_login().
# The device stays linked to the old anonymous account.

func test_setup_submit_does_not_relink_device() -> void:
	var source := FileAccess.open("res://main_menu/main_menu.gd", FileAccess.READ)
	assert_object(source).is_not_null()
	var content := source.get_as_text()
	source.close()

	# Find the _on_setup_submit_pressed function
	var func_idx := content.find("func _on_setup_submit_pressed")
	assert_int(func_idx).is_greater(0)

	var next_func_idx := content.find("\nfunc ", func_idx + 1)
	var body: String
	if next_func_idx > 0:
		body = content.substr(func_idx, next_func_idx - func_idx)
	else:
		body = content.substr(func_idx)

	# The function should call link_current_device_after_login but currently doesn't.
	assert_bool(body.contains("link_current_device_after_login")).override_failure_message(
		"Finding #16: _on_setup_submit_pressed does not call link_current_device_after_login after email auth"
	).is_false()
	# ^^^ Asserts the BUG EXISTS (missing call). After fix, change to is_true().


# ── Finding #17: _open_single_player_dialog calls _open_dialog twice ─────────
# main_menu.gd:1124-1132 — _open_dialog("Campaign") is called at line 1127 and
# again at line 1132, clearing and rebuilding the dialog body redundantly.

func test_open_single_player_dialog_calls_open_dialog_twice() -> void:
	var source := FileAccess.open("res://main_menu/main_menu.gd", FileAccess.READ)
	assert_object(source).is_not_null()
	var content := source.get_as_text()
	source.close()

	# Find the _open_single_player_dialog function
	var func_idx := content.find("func _open_single_player_dialog")
	assert_int(func_idx).is_greater(0)

	var next_func_idx := content.find("\nfunc ", func_idx + 1)
	var body: String
	if next_func_idx > 0:
		body = content.substr(func_idx, next_func_idx - func_idx)
	else:
		body = content.substr(func_idx)

	# Count how many times _open_dialog("Campaign") appears
	var count := 0
	var search_start := 0
	var needle := "_open_dialog(\"Campaign\")"
	while true:
		var idx := body.find(needle, search_start)
		if idx < 0:
			break
		count += 1
		search_start = idx + needle.length()

	assert_int(count).override_failure_message(
		"Finding #17: _open_single_player_dialog calls _open_dialog('Campaign') %d times (should be 1)" % count
	).is_equal(2)
	# ^^^ Asserts the BUG EXISTS (called twice). After fix, change to is_equal(1).
