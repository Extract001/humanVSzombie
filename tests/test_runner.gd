extends Node
## Headless test runner (no plugins). Runs every res://tests/test_*.gd file.
##
## Run:   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
## Prints "ALL TESTS PASSED (n)" or "TESTS FAILED", and exits with code 0 / 1.

const TEST_DIR: String = "res://tests"


func _ready() -> void:
	# Wait one frame so the scene tree and physics are fully running.
	await get_tree().process_frame
	# Tests always use the default key bindings, whatever the player saved in settings.cfg.
	Settings.reset_bindings(false)
	# Fun pass: no random street spawns in tests (tests that need them switch them on), no records.
	GameState.street_spawns_disabled = true
	GameState.records_disabled = true
	GameState.intro_disabled = true
	# Tests never touch your real save: they use their own file, removed at the end.
	SaveSystem.path = "user://test_runner_save.json"
	var total: int = 0
	var failed: Array[String] = []
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	files.sort()
	for file in files:
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd" \
				or file == "test_runner.gd":
			continue
		var script: GDScript = load(TEST_DIR.path_join(file))
		var suite: Node = script.new()
		suite.name = file.get_basename()
		add_child(suite)
		for method in script.get_script_method_list():
			var mname: String = method["name"]
			if not mname.begins_with("test_"):
				continue
			total += 1
			suite.current_test = "%s.%s" % [file.get_basename(), mname]
			var before: int = suite.failures.size()
			await suite.call(mname)
			# Clean up anything the test spawned, and any held inputs.
			for child in suite.get_children():
				child.queue_free()
			suite.release_all_actions()
			await get_tree().physics_frame
			var ok: bool = suite.failures.size() == before
			print(("  PASS  " if ok else "  FAIL  ") + suite.current_test)
		failed.append_array(suite.failures)
		suite.queue_free()

	for ext in ["", ".tmp", ".bak", ".broken", ".bak.broken"]:
		if FileAccess.file_exists(SaveSystem.path + ext):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveSystem.path + ext))
	# Stop sounds left playing so nothing leaks at exit.
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame
	print("")
	for f in failed:
		print("  ✗ " + f)
	if failed.is_empty():
		print("ALL TESTS PASSED (%d)" % total)
		get_tree().quit(0)
	else:
		print("TESTS FAILED (%d of %d checks failed)" % [failed.size(), total])
		get_tree().quit(1)
