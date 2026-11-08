extends "res://tests/test_case.gd"
## Phase 9: final art/animation/audio checks (QA Phase 9 automated items).

const PLAYER_ANIMS: Array[String] = ["idle", "walk", "run", "melee", "shoot", "reload", "hurt", "shove", "death"]
const WALKER_ANIMS: Array[String] = ["idle", "walk", "attack", "hurt", "death"]
const DIRS: Array[String] = ["down", "left", "right", "up"]


func _text_files(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["tscn", "tres", "gd", "cfg", "godot"]:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in ["tests", "documentation", "export", "logs"]:
			continue
		_text_files(dir.path_join(d), out)


func test_no_placeholder_assets_referenced() -> void:
	var files: Array[String] = []
	_text_files("res://", files)
	files.append("res://project.godot")
	var bad: Array[String] = []
	var re := RegEx.create_from_string("res://[^\"]*placeholder[^\"]*")
	for f in files:
		var text: String = FileAccess.get_file_as_string(f)
		for m in re.search_all(text):
			bad.append("%s -> %s" % [f, m.get_string()])
	check(files.size() > 50, "scanned the project (%d files)" % files.size())
	check_eq(bad.size(), 0, "no scene/script/resource uses a placeholder file: %s" % str(bad))


func _check_frames(sf: SpriteFrames, anims: Array[String], who: String) -> void:
	for a in anims:
		for d in DIRS:
			var name := StringName(a + "_" + d)
			if not sf.has_animation(name):
				check(false, "%s has animation %s" % [who, name])
				continue
			var n: int = sf.get_frame_count(name)
			check(n >= 1, "%s %s has frames" % [who, name])
			var empty := 0
			for i in n:
				var at := sf.get_frame_texture(name, i) as AtlasTexture
				var img: Image = at.atlas.get_image().get_region(Rect2i(at.region))
				if img.is_invisible():
					empty += 1
			check_eq(empty, 0, "%s %s: no empty frames" % [who, name])


func test_every_required_animation_exists_and_is_drawn() -> void:
	_check_frames(load("res://assets/sprites/player_frames.tres"), PLAYER_ANIMS, "player")
	_check_frames(load("res://assets/sprites/walker_frames.tres"), WALKER_ANIMS, "walker")
	var sf: SpriteFrames = load("res://assets/sprites/player_frames.tres")
	check(not sf.get_animation_loop(&"death_down"), "death plays once")
	check(sf.get_animation_loop(&"walk_left"), "walking loops")


func test_walker_eyes_sit_on_the_head_in_every_frame() -> void:
	var sf: SpriteFrames = load("res://assets/sprites/walker_frames.tres")
	var eyes: Image = (load("res://assets/sprites/walker_eyes.png") as Texture2D).get_image()
	for di in DIRS.size():
		var eye_px: Array[Vector2i] = []
		for y in 24:
			for x in 16:
				if eyes.get_pixel(di * 16 + x, y).a > 0.9:
					eye_px.append(Vector2i(x, y))
		if DIRS[di] == "up":
			check(eye_px.is_empty(), "no eyes when facing away")
			continue
		check(not eye_px.is_empty(), "eyes drawn facing %s" % DIRS[di])
		for a in ["idle", "walk", "attack", "hurt"]:
			var name := StringName(a + "_" + DIRS[di])
			for i in sf.get_frame_count(name):
				var at := sf.get_frame_texture(name, i) as AtlasTexture
				var img: Image = at.atlas.get_image().get_region(Rect2i(at.region))
				for p in eye_px:
					check(img.get_pixelv(p).a > 0.9, "eye overlay on the head: %s frame %d at %s" % [name, i, p])


func test_player_animation_follows_state() -> void:
	var p := spawn_player(make_sandbox(), Vector2(100, 100))
	await physics_frames(2)
	p.aim_direction = Vector2.RIGHT
	check_eq(p.animation_for(false), &"idle_right", "idle")
	check_eq(p.animation_for(true), &"walk_right", "walking")
	p.is_running = true
	check_eq(p.animation_for(true), &"run_right", "running")
	p.is_running = false
	p.try_attack()  # bat
	check_eq(p.animation_for(false), &"melee_right", "bat swing")
	await physics_frames(40)
	p.try_switch(1)
	await physics_frames(30)  # switching takes a moment
	p.try_attack()  # pistol
	check_eq(p.animation_for(false), &"shoot_right", "pistol shot")
	check(p.muzzle_flash.visible, "muzzle flash shows when firing")
	await physics_frames(6)
	check(not p.muzzle_flash.visible, "muzzle flash is brief")
	await physics_frames(30)
	p.try_reload()
	check_eq(p.animation_for(false), &"reload_right", "reloading")
	await physics_frames(120)
	p.try_shove()
	check_eq(p.animation_for(false), &"shove_right", "shove")
	await physics_frames(30)
	p.health.take_damage(1000.0)
	await physics_frames(2)
	check(String(p.sprite.animation).begins_with("death_"), "death animation plays")
	check_eq(p.sprite.rotation, 0.0, "no more sprite rotation for dying")


func test_walker_animation_follows_state_and_hits_spawn_blood() -> void:
	var sb := make_sandbox()
	var p := spawn_player(sb, Vector2(100, 100))
	var z := spawn_walker(sb, Vector2(116, 100), Vector2.LEFT)
	await physics_frames(20)
	check(String(z.sprite.animation).begins_with("attack_"), "biting plays the attack animation (%s)" % z.sprite.animation)
	var before: int = sb.get_children().filter(func(n: Node) -> bool: return n is CPUParticles2D).size()
	z.hurtbox.receive_hit(10.0, p, Vector2(50, 0), 0.3)
	await physics_frames(1)
	check(String(z.sprite.animation).begins_with("hurt_"), "a hit plays the hurt animation")
	var after: int = sb.get_children().filter(func(n: Node) -> bool: return n is CPUParticles2D).size()
	check(after > before, "a hit sprays blood particles")
	z.health.take_damage(1000.0)
	await physics_frames(2)
	check(String(z.sprite.animation).begins_with("death_"), "zombie death animation")


func test_audio_assets_and_buses() -> void:
	for bus in [&"SFX", &"Music"]:
		check(AudioServer.get_bus_index(bus) >= 0, "audio bus %s exists" % bus)
	for path in Soundscape.TRACKS.values():
		for p in path:
			var s: AudioStream = load(p)
			check(s != null and s.get_length() >= 20.0, "%s loads (%.0f s)" % [p, s.get_length() if s else 0.0])
	for name in ["step_1", "step_2", "step_3", "zombie_shuffle", "groan_distant_1", "groan_distant_2", "ui_click",
			"pistol_shot", "zombie_grunt", "zombie_death", "player_hurt", "melee_hit", "flesh_hit"]:
		check(ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % name), "sound %s exists" % name)
	var old: float = Settings.music_volume
	Settings.music_volume = 0.5
	Settings.apply()
	check_near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Music")), linear_to_db(0.5), 0.01, "music slider sets the Music bus")
	Settings.music_volume = old
	Settings.apply()


func test_soundscape_mood_follows_the_safehouse() -> void:
	GameState.new_game(1)
	var game: Node = load("res://scenes/main/game.tscn").instantiate()
	add_child(game)
	await physics_frames(3)
	check_eq(Soundscape.mood, "safehouse", "calm mood inside the safehouse")
	game.get_node("World/Actors/Player").global_position = Vector2(78, 58) * 16.0
	await physics_frames(2)
	check_eq(Soundscape.mood, "outside", "outside mood on the street")
	game.queue_free()
	await physics_frames(2)
	check(Soundscape.player == null, "soundscape lets go of the player when the game ends")


func _media_files(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["png", "wav", "ogg"]:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_media_files(dir.path_join(d), out)


func test_every_asset_file_is_listed_in_asset_licenses() -> void:
	var doc: String = FileAccess.get_file_as_string("res://ASSET_LICENSES.md")
	check(doc.length() > 1000, "ASSET_LICENSES.md readable")
	var files: Array[String] = []
	_media_files("res://assets", files)
	files.append("res://icon.png")
	var missing: Array[String] = []
	for f in files:
		var name: String = f.get_file()
		var stem: String = name.get_basename()
		# Rows list files by name; numbered families are written like step_1..3 / groan_distant_1..2.
		var family: String = stem.rstrip("0123456789").trim_suffix("_")
		if not (doc.contains(name) or doc.contains(stem) or (family != stem and doc.contains(family + "_1.."))
				or (f.begins_with("res://assets/audio/sfx/") and doc.contains("`assets/audio/sfx/*.wav`") and doc.contains(stem))
				or (f.begins_with("res://assets/ui/") and doc.contains("`assets/ui/*.png`"))):
			missing.append(f)
	check_eq(missing.size(), 0, "every art/audio file has a licence entry: %s" % str(missing))


func test_every_sound_the_code_uses_exists() -> void:
	var files: Array[String] = []
	_text_files("res://scripts", files)
	var re := RegEx.create_from_string("res://assets/audio/[^\"]+\\.(wav|ogg)")
	var used := 0
	for f in files:
		for m in re.search_all(FileAccess.get_file_as_string(f)):
			used += 1
			check(ResourceLoader.exists(m.get_string()), "%s uses an existing sound %s" % [f.get_file(), m.get_string()])
	check(used > 20, "sounds referenced from code (%d)" % used)
	for w in ["res://data/weapons/bat.tres", "res://data/weapons/pistol.tres"]:
		var wd: WeaponData = load(w)
		check(wd.attack_sound != null and wd.hit_sound != null, "%s has attack and hit sounds" % w.get_file())
