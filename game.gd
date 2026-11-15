extends Node3D
# BALL - dodge the chasing ball
# one scene, one script, everything is built in code so there are no assets to import.
# if something feels too hard or too easy, the numbers at the top are the ones to mess with.

const ARENA = 12.0
const CEIL = 10.0            # ceiling height for zero-g
const PLAYER_SPEED = 9.0
const PLAYER_R = 0.55
const BALL_R = 0.75
const GRAV = 22.0
const BOUNCE_POWER = 10.0
const ZG_ACCEL = 38.0
const WINS_NEEDED = 3        # rounds you need to take the 2 player match
const PICKUP_LIFE = 11.0     # how long a powerup sits there before it fades
const REPEL_RANGE = 6.0
const BALL_COLORS = [Color(1.0, 0.2, 0.25), Color(1.0, 0.85, 0.1), Color(0.8, 0.25, 1.0), Color(0.2, 1.0, 0.45)]
const ROUND_EMOJI = ["🥶", "🔥", "⚡", "😈", "👑"]
const ROUND_COLORS = [Color(0.4, 0.85, 1.0), Color(1.0, 0.45, 0.15), Color(1.0, 0.9, 0.2), Color(0.85, 0.3, 1.0), Color(1.0, 0.25, 0.3)]

# the four powerups. shield and speed are the ones you asked for, mini + repel are mine
const PU_KEYS = ["shield", "speed", "mini", "repel"]
const PU = {
	"shield": {"name": "SHIELD", "color": Color(0.25, 0.7, 1.0), "dur": 3.0, "emoji": "🛡️"},
	"speed": {"name": "SPEED BOOST", "color": Color(1.0, 0.85, 0.1), "dur": 5.0, "emoji": "⚡"},
	"mini": {"name": "MINI ME", "color": Color(1.0, 0.3, 0.85), "dur": 6.0, "emoji": "🍄"},
	"repel": {"name": "REPEL BLAST", "color": Color(0.3, 1.0, 0.4), "dur": 4.0, "emoji": "💥"},
}

enum State { TITLE, MODE, DIFFICULTY, GRAVITY, NAMES, PLAYING, GAMEOVER }
var state = State.TITLE

# ---- what got picked in the menus ----
var num_players = 1
var no_mercy = false
var zero_g = false
var names = ["Player 1", "Player 2"]
var player_colors = [Color(0.15, 0.6, 1.0), Color(1.0, 0.4, 0.15)]
var best_time = {"normal": 0.0, "mercy": 0.0, "normal_zg": 0.0, "mercy_zg": 0.0}

# ---- difficulty numbers, set when a game starts ----
var ball_speed0 = 6.5
var turn_rate = 1.2
var speedup = 0.3
var max_speed = 10.5

# ---- general stuff ----
var t = 0.0
var font
var menu_cam
var arena_root
var low_fence
var zg_root
var sky_mat
var world_env
var glow_mats = []
var fence_mats = []
var floaters = []
var decor = []

# ---- menu ui ----
var menu_layer
var menu_root
var screen_root
var title_letters = []
var title_emojis = []
var sub_label = null
var menu_title_label = null
var name_inputs = []

# ---- game ----
var game3d
var vp_layer
var hud_layer
var hud_root
var over_layer
var players = []
var balls = []
var pickups = []
var views = []
var huds = []
var msg_label
var round_l
var vignette
var countdown = 3.0
var msg_t = 0.0
var extra_timer = 0.0
var pending_end = -1.0
var pu_timer = 5.0

# rounds (2 player)
var phase = "count"      # intro -> count -> play -> result
var round_num = 1
var scores = [0, 0]
var round_winner = -1
var card = {}

# ---- game over screen ----
var over_t = 0.0
var over_dim
var over_flash
var over_title
var over_sub = null
var over_loser = null
var over_panel
var over_buttons
var over_hint
var over_record = null
var over_counters = []
var over_winner = -1
var over_wcolor = Color.WHITE
var new_record = false


# ----------------------------------------------------------
# setup
# ----------------------------------------------------------
func _ready():
	randomize()
	get_window().title = "BALL"
	font = make_font()
	load_best()
	build_environment()
	build_arena()
	menu_cam = Camera3D.new()
	menu_cam.fov = 70
	add_child(menu_cam)
	menu_cam.current = true
	build_decor()

	menu_layer = CanvasLayer.new()
	menu_layer.layer = 5
	add_child(menu_layer)
	menu_root = Control.new()
	menu_layer.add_child(menu_root)
	menu_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.1, 0.3)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root = Control.new()
	menu_root.add_child(screen_root)
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_title()


func make_font():
	var f = SystemFont.new()
	f.font_names = PackedStringArray(["Impact", "Arial Black", "Segoe UI Black", "Verdana"])
	f.font_weight = 800
	# emojis need their own font or they show up as empty boxes
	var emo = SystemFont.new()
	emo.font_names = PackedStringArray(["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", "Twemoji Mozilla"])
	var fb: Array[Font] = [emo]
	f.fallbacks = fb
	return f


func load_best():
	var cf = ConfigFile.new()
	if cf.load("user://ball_best.cfg") == OK:
		for k in best_time.keys():
			best_time[k] = cf.get_value("best", k, 0.0)


func save_best():
	var cf = ConfigFile.new()
	for k in best_time.keys():
		cf.set_value("best", k, best_time[k])
	cf.save("user://ball_best.cfg")


func best_key():
	var k = "mercy" if no_mercy else "normal"
	if zero_g:
		k += "_zg"
	return k


func mode_text():
	var s = "NO MERCY" if no_mercy else "NORMAL"
	if zero_g:
		s += "  -  ZERO-G"
	return s


# ----------------------------------------------------------
# little helpers
# ----------------------------------------------------------
func make_mat(color, metal = 0.0, rough = 0.5, emit = 0.0):
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


func make_glass(color, alpha):
	# see-through unlit material, used for force fields / auras / shadows
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	return m


func flat(v):
	return Vector3(v.x, 0.0, v.z)


func any_key(list):
	for k in list:
		if Input.is_key_pressed(k):
			return true
	return false


func set_rect_anchors(c, l, tp, r, b):
	c.anchor_left = l
	c.anchor_top = tp
	c.anchor_right = r
	c.anchor_bottom = b
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


func make_label(text, size, color, outline = 10):
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.0, 0.1))
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", int(size * 0.05) + 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func make_style(color):
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(22)
	s.set_border_width_all(4)
	s.border_color = Color(1, 1, 1, 0.9)
	s.shadow_color = Color(color.r, color.g, color.b, 0.6)
	s.shadow_size = 16
	s.shadow_offset = Vector2(0, 5)
	return s


func make_button(text, color, w = 380, h = 78, fsize = 40):
	var b = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.pivot_offset = Vector2(w, h) / 2.0
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_outline_color", color.darkened(0.6))
	b.add_theme_constant_override("outline_size", 8)
	b.add_theme_stylebox_override("normal", make_style(color))
	b.add_theme_stylebox_override("hover", make_style(color.lightened(0.25)))
	b.add_theme_stylebox_override("pressed", make_style(color.darkened(0.25)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.mouse_entered.connect(_on_btn_hover.bind(b, true))
	b.mouse_exited.connect(_on_btn_hover.bind(b, false))
	return b


func _on_btn_hover(b, on):
	var tw = b.create_tween()
	tw.tween_property(b, "scale", Vector2(1.08, 1.08) if on else Vector2.ONE, 0.12)


func make_line_edit(color, placeholder):
	var le = LineEdit.new()
	le.placeholder_text = placeholder
	le.max_length = 12
	le.custom_minimum_size = Vector2(420, 66)
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.add_theme_font_override("font", font)
	le.add_theme_font_size_override("font_size", 34)
	le.add_theme_color_override("font_color", Color.WHITE)
	le.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.45))
	le.add_theme_color_override("caret_color", color)
	var s = StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.03, 0.12, 0.92)
	s.set_corner_radius_all(18)
	s.set_border_width_all(5)
	s.border_color = color
	s.content_margin_left = 16
	s.content_margin_right = 16
	le.add_theme_stylebox_override("normal", s)
	var s2 = s.duplicate()
	s2.border_color = color.lightened(0.5)
	s2.shadow_color = Color(color.r, color.g, color.b, 0.7)
	s2.shadow_size = 14
	le.add_theme_stylebox_override("focus", s2)
	return le


func make_keycap(text, color):
	var cap = PanelContainer.new()
	cap.custom_minimum_size = Vector2(52, 52)
	cap.pivot_offset = Vector2(26, 26)
	var s = StyleBoxFlat.new()
	s.bg_color = color.darkened(0.35)
	s.set_corner_radius_all(12)
	s.set_border_width_all(4)
	s.border_color = color.lightened(0.5)
	s.shadow_color = Color(color.r, color.g, color.b, 0.6)
	s.shadow_size = 8
	cap.add_theme_stylebox_override("panel", s)
	cap.add_child(make_label(text, 30, Color.WHITE, 6))
	return cap


func add_center(vb, node):
	node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(node)


func pop_in(nodes):
	var i = 0
	for n in nodes:
		n.modulate.a = 0.0
		n.scale = Vector2(0.5, 0.5)
		var tw = n.create_tween()
		tw.set_parallel(true)
		tw.tween_property(n, "modulate:a", 1.0, 0.25).set_delay(0.08 * i)
		tw.tween_property(n, "scale", Vector2.ONE, 0.45).set_delay(0.08 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


# ----------------------------------------------------------
# the 3d world (sky, arena, background junk)
# ----------------------------------------------------------
func build_environment():
	sky_mat = ProceduralSkyMaterial.new()
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# glow was way too strong before, now only the really bright stuff blooms
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.12, 0.4)
	env.fog_density = 0.005
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.08
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	set_space_look(false)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.92, 0.85)
	sun.shadow_enabled = true
	add_child(sun)


func set_space_look(on):
	# zero-g gets a darker, spacier sky so it feels different
	if on:
		sky_mat.sky_top_color = Color(0.01, 0.0, 0.07)
		sky_mat.sky_horizon_color = Color(0.1, 0.08, 0.32)
		sky_mat.ground_horizon_color = Color(0.1, 0.08, 0.32)
		sky_mat.ground_bottom_color = Color(0.01, 0.0, 0.05)
	else:
		sky_mat.sky_top_color = Color(0.05, 0.03, 0.22)
		sky_mat.sky_horizon_color = Color(0.55, 0.18, 0.5)
		sky_mat.ground_horizon_color = Color(0.55, 0.18, 0.5)
		sky_mat.ground_bottom_color = Color(0.03, 0.02, 0.1)


func add_panel(parent, size, pos, mat):
	var bm = BoxMesh.new()
	bm.size = size
	bm.material = mat
	var mi = MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func build_arena():
	arena_root = Node3D.new()
	add_child(arena_root)

	# checker + grid texture, drawn in code
	var img = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for x in 64:
		for y in 64:
			var c = Color(0.10, 0.12, 0.30)
			if ((x >> 5) + (y >> 5)) % 2 == 1:
				c = Color(0.06, 0.07, 0.20)
			if x < 2 or y < 2:
				c = Color(0.2, 0.7, 0.85)
			elif (x >= 32 and x < 34) or (y >= 32 and y < 34):
				c = Color(0.5, 0.18, 0.62)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex = ImageTexture.create_from_image(img)

	var fm = StandardMaterial3D.new()
	fm.albedo_texture = tex
	fm.uv1_scale = Vector3(6, 6, 1)
	fm.metallic = 0.3
	fm.roughness = 0.4
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	fm.emission_enabled = true
	fm.emission_texture = tex
	fm.emission = Color(1, 1, 1)
	fm.emission_energy_multiplier = 0.4
	var pm = PlaneMesh.new()
	pm.size = Vector2(ARENA * 2.0, ARENA * 2.0)
	pm.material = fm
	var floor_node = MeshInstance3D.new()
	floor_node.mesh = pm
	arena_root.add_child(floor_node)

	# dark slab under the floor
	add_panel(arena_root, Vector3(ARENA * 2.0 + 1.2, 3.0, ARENA * 2.0 + 1.2), Vector3(0, -1.52, 0), make_mat(Color(0.03, 0.03, 0.08), 0.6, 0.4))

	# glowing wall rails (colors cycle in animate_world)
	var span = ARENA * 2.0 + 0.8
	var wall_defs = [
		[Vector3(span, 1.1, 0.5), Vector3(0, 0.55, -ARENA - 0.25)],
		[Vector3(span, 1.1, 0.5), Vector3(0, 0.55, ARENA + 0.25)],
		[Vector3(0.5, 1.1, span), Vector3(-ARENA - 0.25, 0.55, 0)],
		[Vector3(0.5, 1.1, span), Vector3(ARENA + 0.25, 0.55, 0)],
	]
	for wd in wall_defs:
		var mat = make_mat(Color(0.2, 0.8, 0.9), 0.2, 0.3, 1.1)
		glow_mats.append(mat)
		add_panel(arena_root, wd[0], wd[1], mat)

	# force field so you can actually see where the edge is.
	# low version for normal gravity, full cage for zero-g
	low_fence = Node3D.new()
	arena_root.add_child(low_fence)
	zg_root = Node3D.new()
	arena_root.add_child(zg_root)
	zg_root.visible = false
	var fence_defs = [
		[Vector3(ARENA * 2.0, 1.0, 0.04), Vector3(0, 0, -ARENA)],
		[Vector3(ARENA * 2.0, 1.0, 0.04), Vector3(0, 0, ARENA)],
		[Vector3(0.04, 1.0, ARENA * 2.0), Vector3(-ARENA, 0, 0)],
		[Vector3(0.04, 1.0, ARENA * 2.0), Vector3(ARENA, 0, 0)],
	]
	for fd in fence_defs:
		var m1 = make_glass(Color(0.3, 0.8, 1.0), 0.13)
		fence_mats.append(m1)
		var sz = fd[0]
		sz.y = 3.6
		add_panel(low_fence, sz, Vector3(fd[1].x, 1.8, fd[1].z), m1)
		var m2 = make_glass(Color(0.5, 0.4, 1.0), 0.1)
		fence_mats.append(m2)
		sz.y = CEIL
		add_panel(zg_root, sz, Vector3(fd[1].x, CEIL / 2.0, fd[1].z), m2)
	# ceiling + rails along the top edge
	var cm = make_glass(Color(0.5, 0.4, 1.0), 0.07)
	fence_mats.append(cm)
	add_panel(zg_root, Vector3(ARENA * 2.0, 0.04, ARENA * 2.0), Vector3(0, CEIL, 0), cm)
	for rd in wall_defs:
		var rmat = make_mat(Color(0.5, 0.4, 1.0), 0.2, 0.3, 1.0)
		glow_mats.append(rmat)
		var rs = rd[0]
		rs.y = 0.3
		add_panel(zg_root, rs, Vector3(rd[1].x, CEIL, rd[1].z), rmat)

	# corner pillars with orbs
	var pcols = [Color(1.0, 0.2, 0.8), Color(0.2, 0.9, 1.0)]
	var idx = 0
	for sx in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			var cyl = CylinderMesh.new()
			cyl.top_radius = 0.35
			cyl.bottom_radius = 0.45
			cyl.height = 3.0
			cyl.material = make_mat(Color(0.1, 0.1, 0.2), 0.8, 0.25)
			var cn = MeshInstance3D.new()
			cn.mesh = cyl
			cn.position = Vector3(sx * (ARENA + 0.25), 1.5, sz2 * (ARENA + 0.25))
			arena_root.add_child(cn)
			var orb = SphereMesh.new()
			orb.radius = 0.5
			orb.height = 1.0
			var omat = make_mat(pcols[idx % 2], 0.0, 0.2, 1.6)
			orb.material = omat
			glow_mats.append(omat)
			var on = MeshInstance3D.new()
			on.mesh = orb
			on.position = Vector3(0, 1.8, 0)
			cn.add_child(on)
			var ol = OmniLight3D.new()
			ol.light_color = pcols[idx % 2]
			ol.light_energy = 1.2
			ol.omni_range = 14.0
			ol.position = Vector3(0, 1.8, 0)
			cn.add_child(ol)
			idx += 1

	# floating shapes far away, just for looks
	for i in 28:
		var mesh
		var kind = i % 4
		if kind == 0:
			mesh = TorusMesh.new()
			mesh.inner_radius = 0.7
			mesh.outer_radius = 1.2
		elif kind == 1:
			mesh = BoxMesh.new()
			mesh.size = Vector3(1.4, 1.4, 1.4)
		elif kind == 2:
			mesh = SphereMesh.new()
			mesh.radius = 0.8
			mesh.height = 1.6
		else:
			mesh = PrismMesh.new()
			mesh.size = Vector3(1.6, 1.6, 1.6)
		var col = Color.from_hsv(randf(), 0.7, 0.9)
		mesh.material = make_mat(col, 0.2, 0.3, 0.8)
		var fn = MeshInstance3D.new()
		fn.mesh = mesh
		var ang = randf() * TAU
		var rad = randf_range(22.0, 48.0)
		var y0 = randf_range(2.0, 25.0)
		fn.position = Vector3(cos(ang) * rad, y0, sin(ang) * rad)
		var sc = randf_range(0.8, 2.2)
		fn.scale = Vector3(sc, sc, sc)
		arena_root.add_child(fn)
		floaters.append({"node": fn, "y": y0, "spd": randf_range(0.5, 1.5), "ph": randf() * TAU, "rx": randf_range(-1.0, 1.0), "ry": randf_range(-1.0, 1.0)})


func build_decor():
	# the bouncing balls behind the menus
	for i in 6:
		var col = Color.from_hsv(float(i) / 6.0, 0.85, 1.0)
		var made = make_ball_node(col)
		made["node"].position = Vector3(randf_range(-8, 8), randf_range(1, 5), randf_range(-8, 8))
		add_child(made["node"])
		decor.append({"node": made["node"], "body": made["body"], "ring": made["ring"], "vel": Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)), "vy": randf_range(0, 8), "age": 10.0, "grace": 0.0})


func animate_world(delta):
	for i in glow_mats.size():
		var c = Color.from_hsv(fmod(t * 0.07 + i * 0.125, 1.0), 0.7, 0.85)
		glow_mats[i].albedo_color = c
		glow_mats[i].emission = c
	for i in fence_mats.size():
		var c2 = Color.from_hsv(fmod(t * 0.07 + i * 0.1, 1.0), 0.6, 1.0)
		fence_mats[i].albedo_color = Color(c2.r, c2.g, c2.b, fence_mats[i].albedo_color.a)
	for f in floaters:
		var n = f["node"]
		n.rotation.x += delta * f["rx"]
		n.rotation.y += delta * f["ry"]
		n.position.y = f["y"] + sin(t * f["spd"] + f["ph"]) * 1.2


# ----------------------------------------------------------
# balls, players, pickups (the 3d objects)
# ----------------------------------------------------------
func make_particles(color, size, amount, life):
	var p = CPUParticles3D.new()
	var sm = SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	sm.material = make_mat(color, 0.0, 0.4, 2.5)
	p.mesh = sm
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.gravity = Vector3.ZERO
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	return p


func make_shadow(color, r):
	# flat glowing disc on the floor, helps a lot to see where things are in zero-g
	var cm = CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	cm.material = make_glass(color, 0.4)
	var mi = MeshInstance3D.new()
	mi.mesh = cm
	return mi


func make_ball_node(color):
	var node = Node3D.new()
	var body = Node3D.new()
	node.add_child(body)

	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	sm.material = make_mat(color, 0.1, 0.12, 1.0)
	mi.mesh = sm
	body.add_child(mi)

	# soft aura
	var am = MeshInstance3D.new()
	var asph = SphereMesh.new()
	asph.radius = BALL_R * 1.35
	asph.height = BALL_R * 2.7
	asph.material = make_glass(color, 0.22)
	am.mesh = asph
	body.add_child(am)

	# spinning ring
	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = BALL_R * 1.1
	tm.outer_radius = BALL_R * 1.25
	tm.material = make_mat(Color(1, 1, 1), 0.0, 0.3, 1.6)
	ring.mesh = tm
	ring.rotation_degrees = Vector3(70, 0, 0)
	body.add_child(ring)

	var light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.8
	light.omni_range = 10.0
	body.add_child(light)

	node.add_child(make_particles(color, 0.28, 45, 0.6))
	return {"node": node, "body": body, "ring": ring}


func step_ball(d, delta):
	if d.get("zg", false):
		step_ball_zg(d, delta)
		return
	var node = d["node"]
	d["age"] += delta
	d["grace"] -= delta
	node.position += d["vel"] * delta
	d["vy"] -= GRAV * delta
	node.position.y += d["vy"] * delta
	if node.position.y < BALL_R:
		node.position.y = BALL_R
		d["vy"] = BOUNCE_POWER

	var w = ARENA - BALL_R
	var v = d["vel"]
	if node.position.x < -w:
		node.position.x = -w
		v.x = abs(v.x)
	elif node.position.x > w:
		node.position.x = w
		v.x = -abs(v.x)
	if node.position.z < -w:
		node.position.z = -w
		v.z = abs(v.z)
	elif node.position.z > w:
		node.position.z = w
		v.z = -abs(v.z)
	d["vel"] = v
	ball_visual(d, delta)


func step_ball_zg(d, delta):
	# no gravity: ball just flies around in 3d and bounces off all six sides
	var node = d["node"]
	d["age"] += delta
	d["grace"] -= delta
	node.position += d["vel"] * delta
	var w = ARENA - BALL_R
	var v = d["vel"]
	var p = node.position
	if p.x < -w:
		p.x = -w
		v.x = abs(v.x)
	elif p.x > w:
		p.x = w
		v.x = -abs(v.x)
	if p.z < -w:
		p.z = -w
		v.z = abs(v.z)
	elif p.z > w:
		p.z = w
		v.z = -abs(v.z)
	if p.y < BALL_R:
		p.y = BALL_R
		v.y = abs(v.y)
	elif p.y > CEIL - BALL_R:
		p.y = CEIL - BALL_R
		v.y = -abs(v.y)
	node.position = p
	d["vel"] = v
	ball_visual(d, delta)


func ball_visual(d, delta):
	var g = clamp(d["age"] / 0.6, 0.02, 1.0)
	if d.get("zg", false):
		d["body"].scale = Vector3.ONE * g
		d["body"].position.y = 0.0
	else:
		var node = d["node"]
		var h = node.position.y - BALL_R
		var sq = clamp(h / 0.5, 0.0, 1.0)
		var sy = lerp(0.65, 1.0, sq)
		var sxz = lerp(1.22, 1.0, sq)
		d["body"].scale = Vector3(sxz, sy, sxz) * g
		d["body"].position.y = -BALL_R * (1.0 - sy * g)
	d["ring"].rotation.y += delta * 6.0


func make_player_node(color, pname):
	var root = Node3D.new()
	var holder = Node3D.new()
	root.add_child(holder)

	var body = MeshInstance3D.new()
	var cm = CapsuleMesh.new()
	cm.radius = PLAYER_R
	cm.height = 1.7
	cm.radial_segments = 32
	cm.rings = 12
	cm.material = make_mat(color, 0.3, 0.22, 0.3)
	body.mesh = cm
	body.position.y = 0.85
	holder.add_child(body)

	var visor = MeshInstance3D.new()
	var vm = SphereMesh.new()
	vm.radius = 0.4
	vm.height = 0.8
	vm.material = make_mat(Color(0.02, 0.03, 0.08), 0.8, 0.05, 0.0)
	visor.mesh = vm
	visor.scale = Vector3(1.0, 0.62, 0.6)
	visor.position = Vector3(0, 1.2, -0.36)
	holder.add_child(visor)

	for sx in [-1.0, 1.0]:
		var eye = MeshInstance3D.new()
		var em = SphereMesh.new()
		em.radius = 0.085
		em.height = 0.17
		em.material = make_mat(Color.WHITE, 0.0, 0.3, 2.0)
		eye.mesh = em
		eye.position = Vector3(sx * 0.16, 1.22, -0.58)
		holder.add_child(eye)

	# antenna
	var stick = MeshInstance3D.new()
	var sm = CylinderMesh.new()
	sm.top_radius = 0.03
	sm.bottom_radius = 0.03
	sm.height = 0.3
	sm.material = make_mat(Color(0.8, 0.8, 0.9), 0.8, 0.2)
	stick.mesh = sm
	stick.position = Vector3(0, 1.85, 0)
	holder.add_child(stick)
	var tip = MeshInstance3D.new()
	var tm = SphereMesh.new()
	tm.radius = 0.1
	tm.height = 0.2
	tm.material = make_mat(color.lightened(0.3), 0.0, 0.2, 2.0)
	tip.mesh = tm
	tip.position = Vector3(0, 2.05, 0)
	holder.add_child(tip)

	# glowing ring (floor ring normally, halo around the waist in zero-g)
	var ring = MeshInstance3D.new()
	var rm = TorusMesh.new()
	rm.inner_radius = 0.75
	rm.outer_radius = 0.95
	rm.material = make_mat(color, 0.0, 0.3, 1.8)
	ring.mesh = rm
	ring.position.y = 0.06
	root.add_child(ring)

	var light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.0
	light.omni_range = 6.0
	light.position.y = 1.0
	root.add_child(light)

	var trail = make_particles(color, 0.14, 30, 0.5)
	trail.emitting = false
	trail.position.y = 0.2
	root.add_child(trail)

	# yellow trail that only shows with the speed boost
	var boost = make_particles(Color(1.0, 0.85, 0.15), 0.2, 40, 0.45)
	boost.emitting = false
	boost.position.y = 0.5
	root.add_child(boost)

	# shield bubble, invisible until you grab a shield
	var sh = MeshInstance3D.new()
	var shm = SphereMesh.new()
	shm.radius = 1.25
	shm.height = 2.5
	var shmat = make_glass(Color(0.3, 0.75, 1.0), 0.0)
	shm.material = shmat
	sh.mesh = shm
	sh.position.y = 0.9
	sh.visible = false
	root.add_child(sh)

	# repel pulse ring
	var rr = MeshInstance3D.new()
	var rrm = TorusMesh.new()
	rrm.inner_radius = 0.93
	rrm.outer_radius = 1.0
	var rrmat = make_glass(Color(0.3, 1.0, 0.4), 0.0)
	rrm.material = rrmat
	rr.mesh = rrm
	rr.position.y = 0.15
	rr.visible = false
	root.add_child(rr)

	var l3 = Label3D.new()
	l3.text = pname
	l3.font = font
	l3.font_size = 64
	l3.pixel_size = 0.012
	l3.outline_size = 18
	l3.modulate = color.lightened(0.35)
	l3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l3.no_depth_test = true
	l3.position.y = 2.6
	root.add_child(l3)

	return {"root": root, "holder": holder, "ring": ring, "light": light, "trail": trail, "label": l3,
		"boost": boost, "shield": sh, "shield_mat": shmat, "rring": rr, "rring_mat": rrmat}


func make_pickup(kind, pos):
	var info = PU[kind]
	var col = info["color"]
	var root = Node3D.new()
	var holder = Node3D.new()
	root.add_child(holder)

	# every powerup has its own core shape so you can tell them apart from far away
	var mesh
	if kind == "shield":
		mesh = SphereMesh.new()
		mesh.radius = 0.42
		mesh.height = 0.84
		mesh.radial_segments = 12
		mesh.rings = 6
	elif kind == "speed":
		mesh = PrismMesh.new()
		mesh.size = Vector3(0.8, 0.95, 0.8)
	elif kind == "mini":
		mesh = BoxMesh.new()
		mesh.size = Vector3(0.62, 0.62, 0.62)
	else:
		mesh = TorusMesh.new()
		mesh.inner_radius = 0.22
		mesh.outer_radius = 0.46
	mesh.material = make_mat(col, 0.1, 0.2, 2.4)
	var core = MeshInstance3D.new()
	core.mesh = mesh
	holder.add_child(core)

	var rings = []
	for i in 2:
		var tm = TorusMesh.new()
		tm.inner_radius = 0.72 + i * 0.12
		tm.outer_radius = 0.78 + i * 0.12
		tm.material = make_mat(col.lightened(0.3), 0.0, 0.3, 1.8)
		var rn = MeshInstance3D.new()
		rn.mesh = tm
		rn.rotation_degrees = Vector3(60 * i, 30 * i, 0)
		holder.add_child(rn)
		rings.append({"node": rn, "axis": Vector3(1.4, 2.0 - i * 3.0, 0.8)})

	var am = MeshInstance3D.new()
	var asph = SphereMesh.new()
	asph.radius = 1.0
	asph.height = 2.0
	asph.material = make_glass(col, 0.15)
	am.mesh = asph
	holder.add_child(am)

	# light beam going up
	var bm = CylinderMesh.new()
	bm.top_radius = 0.08
	bm.bottom_radius = 0.16
	bm.height = 5.0
	bm.material = make_glass(col, 0.13)
	var beam = MeshInstance3D.new()
	beam.mesh = bm
	beam.position.y = 2.4
	root.add_child(beam)

	# marker on the floor under it
	var base = MeshInstance3D.new()
	var btm = TorusMesh.new()
	btm.inner_radius = 0.8
	btm.outer_radius = 0.95
	btm.material = make_glass(col, 0.6)
	base.mesh = btm
	base.position.y = 0.05 - pos.y
	root.add_child(base)

	var light = OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.0
	light.omni_range = 7.0
	root.add_child(light)

	holder.add_child(make_particles(col, 0.07, 16, 1.2))

	var l3 = Label3D.new()
	l3.text = info["name"]
	l3.font = font
	l3.font_size = 56
	l3.pixel_size = 0.01
	l3.outline_size = 14
	l3.modulate = col.lightened(0.4)
	l3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l3.no_depth_test = true
	l3.position.y = 1.7
	root.add_child(l3)

	return {"root": root, "holder": holder, "core": core, "rings": rings, "label": l3, "kind": kind, "age": 0.0, "ph": randf() * TAU}


func burst(pos, color):
	var pt = make_particles(color, 0.14, 70, 1.0)
	pt.one_shot = true
	pt.explosiveness = 1.0
	pt.initial_velocity_min = 4.0
	pt.initial_velocity_max = 11.0
	pt.gravity = Vector3(0, -14, 0) if not zero_g else Vector3.ZERO
	pt.position = pos
	game3d.add_child(pt)
	pt.emitting = true
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(pt):
			pt.queue_free())


func shock_ring(pos, col):
	var tm = TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	var mat = make_glass(col, 0.9)
	tm.material = mat
	var m = MeshInstance3D.new()
	m.mesh = tm
	m.position = pos
	m.scale = Vector3(0.3, 0.3, 0.3)
	game3d.add_child(m)
	var tw = m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(6, 6, 6), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	tw.chain().tween_callback(m.queue_free)


func popup3d(pos, text, col):
	var l3 = Label3D.new()
	l3.text = text
	l3.font = font
	l3.font_size = 96
	l3.pixel_size = 0.014
	l3.outline_size = 24
	l3.modulate = col.lightened(0.3)
	l3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l3.no_depth_test = true
	l3.position = pos
	l3.scale = Vector3(0.3, 0.3, 0.3)
	game3d.add_child(l3)
	var tw = l3.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l3, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l3, "position:y", pos.y + 1.8, 1.4)
	tw.tween_property(l3, "modulate:a", 0.0, 0.5).set_delay(0.9)
	tw.chain().tween_callback(l3.queue_free)


# ----------------------------------------------------------
# menus
# ----------------------------------------------------------
func clear_screen():
	for c in screen_root.get_children():
		screen_root.remove_child(c)
		c.queue_free()
	title_letters = []
	title_emojis = []
	sub_label = null
	menu_title_label = null


func new_column(sep = 16):
	var cc = CenterContainer.new()
	screen_root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", sep)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	return vb


func make_choice(text, desc, color, callback):
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(560, 124)
	box.pivot_offset = Vector2(280, 62)
	var b = make_button(text, color, 560, 84, 44)
	box.add_child(b)
	box.add_child(make_label(desc, 24, Color(1, 1, 1, 0.9), 5))
	b.pressed.connect(callback)
	return box


func show_title():
	state = State.TITLE
	clear_screen()
	var vb = new_column(10)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)

	var el = make_label("🥶", 75, Color.WHITE, 0)
	el.custom_minimum_size = Vector2(95, 130)
	el.pivot_offset = Vector2(47, 65)
	row.add_child(el)
	title_emojis.append(el)

	var word = "BALL RIGHT"
	for i in word.length():
		var l = make_label(word[i], 100, Color.WHITE, 16)
		var char_w = 35 if word[i] == " " else 72
		l.custom_minimum_size = Vector2(char_w, 130)
		l.pivot_offset = Vector2(char_w / 2.0, 65)
		row.add_child(l)
		title_letters.append(l)

	var er = make_label("🔥", 75, Color.WHITE, 0)
	er.custom_minimum_size = Vector2(95, 130)
	er.pivot_offset = Vector2(47, 65)
	row.add_child(er)
	title_emojis.append(er)
	sub_label = make_label("DODGE.  SURVIVE.  BOUNCE BACK!", 32, Color(1, 0.9, 0.3), 8)
	vb.add_child(sub_label)
	var sp = Control.new()
	sp.custom_minimum_size = Vector2(0, 14)
	vb.add_child(sp)
	var play = make_button("PLAY 😎", Color(0.15, 0.8, 0.35), 360, 78, 46)
	play.pressed.connect(show_mode)
	add_center(vb, play)
	var quit = make_button("QUIT", Color(0.85, 0.2, 0.4), 360, 66, 38)
	quit.pressed.connect(func(): get_tree().quit())
	add_center(vb, quit)
	if best_time["normal"] > 0.0 or best_time["mercy"] > 0.0:
		var txt = "BEST   NORMAL: %.1fs     NO MERCY: %.1fs" % [best_time["normal"], best_time["mercy"]]
		vb.add_child(make_label(txt, 24, Color(0.8, 0.95, 1.0), 6))
	if best_time["normal_zg"] > 0.0 or best_time["mercy_zg"] > 0.0:
		var txt2 = "ZERO-G   NORMAL: %.1fs     NO MERCY: %.1fs" % [best_time["normal_zg"], best_time["mercy_zg"]]
		vb.add_child(make_label(txt2, 24, Color(0.75, 0.7, 1.0), 6))
	pop_in([play, quit])


func show_mode():
	state = State.MODE
	clear_screen()
	var vb = new_column(14)
	menu_title_label = make_label("CHOOSE YOUR MODE", 64, Color.WHITE, 14)
	vb.add_child(menu_title_label)
	var c1 = make_choice("1 PLAYER 🙂", "Survive alone and beat your best time", Color(0.1, 0.65, 1.0), choose_players.bind(1))
	var c2 = make_choice("2 PLAYERS 🥊", "Split screen. First to 3 round wins takes it", Color(1.0, 0.4, 0.15), choose_players.bind(2))
	vb.add_child(c1)
	vb.add_child(c2)
	var back = make_button("BACK", Color(0.45, 0.3, 0.8), 240, 58, 32)
	back.pressed.connect(show_title)
	add_center(vb, back)
	pop_in([c1, c2, back])


func choose_players(n):
	num_players = n
	show_difficulty()


func show_difficulty():
	state = State.DIFFICULTY
	clear_screen()
	var vb = new_column(14)
	menu_title_label = make_label("PICK YOUR POISON", 64, Color.WHITE, 14)
	vb.add_child(menu_title_label)
	var c1 = make_choice("NORMAL MODE 😌", "The ball chases you. Stay cool.", Color(0.15, 0.8, 0.5), choose_difficulty.bind(false))
	var c2 = make_choice("NO MERCY MODE 😈", "Faster. Smarter. More balls. Good luck.", Color(0.95, 0.15, 0.2), choose_difficulty.bind(true))
	vb.add_child(c1)
	vb.add_child(c2)
	var back = make_button("BACK", Color(0.45, 0.3, 0.8), 240, 58, 32)
	back.pressed.connect(show_mode)
	add_center(vb, back)
	pop_in([c1, c2, back])


func choose_difficulty(mercy):
	no_mercy = mercy
	show_gravity()


func show_gravity():
	state = State.GRAVITY
	clear_screen()
	var vb = new_column(14)
	menu_title_label = make_label("GRAVITY?", 64, Color.WHITE, 14)
	vb.add_child(menu_title_label)
	var c1 = make_choice("NORMAL GRAVITY 🌍", "Feet on the floor. Balls bounce around.", Color(0.2, 0.6, 0.9), choose_gravity.bind(false))
	var c2 = make_choice("ZERO GRAVITY 🚀", "Float anywhere. Balls hunt you in 3D.", Color(0.55, 0.35, 1.0), choose_gravity.bind(true))
	vb.add_child(c1)
	vb.add_child(c2)
	var back = make_button("BACK", Color(0.45, 0.3, 0.8), 240, 58, 32)
	back.pressed.connect(show_difficulty)
	add_center(vb, back)
	pop_in([c1, c2, back])


func choose_gravity(zg):
	zero_g = zg
	show_names()


func updown_hint(i):
	if num_players == 1:
		return "Q / SPACE = UP     E / SHIFT = DOWN"
	if i == 0:
		return "Q = UP     E = DOWN"
	return ".  = UP     ,  = DOWN"


func show_names():
	state = State.NAMES
	clear_screen()
	name_inputs = []
	var vb = new_column(10)
	menu_title_label = make_label("WHO'S PLAYING?", 64, Color.WHITE, 14)
	vb.add_child(menu_title_label)
	for i in num_players:
		var col = player_colors[i]
		var hint = "WASD  or  ARROW KEYS"
		if num_players == 2:
			hint = "WASD" if i == 0 else "ARROW KEYS"
		var who = "YOUR NAME" if num_players == 1 else "PLAYER " + str(i + 1)
		vb.add_child(make_label(who + "  -  " + hint, 28, col.lightened(0.3), 8))
		if zero_g:
			vb.add_child(make_label(updown_hint(i), 22, Color(1, 1, 1, 0.7), 5))
		var le = make_line_edit(col, "Player " + str(i + 1))
		add_center(vb, le)
		name_inputs.append(le)
	var go = make_button("START! 🔥", Color(1.0, 0.65, 0.1), 360, 80, 48)
	go.pressed.connect(start_from_names)
	var back = make_button("BACK", Color(0.45, 0.3, 0.8), 240, 58, 32)
	back.pressed.connect(show_gravity)
	add_center(vb, go)
	add_center(vb, back)
	pop_in([go, back])


func start_from_names():
	for i in num_players:
		var txt = name_inputs[i].text.strip_edges()
		names[i] = txt if txt != "" else "Player " + str(i + 1)
	start_game()


# ----------------------------------------------------------
# starting / stopping a game
# ----------------------------------------------------------
func start_game():
	state = State.PLAYING
	menu_root.visible = false
	for d in decor:
		d["node"].visible = false
	menu_cam.current = false
	set_space_look(zero_g)
	zg_root.visible = zero_g
	low_fence.visible = not zero_g

	if no_mercy:
		ball_speed0 = 9.5
		turn_rate = 2.8
		speedup = 0.9
		max_speed = 15.5
	else:
		ball_speed0 = 6.5
		turn_rate = 1.2
		speedup = 0.3
		max_speed = 10.5

	scores = [0, 0]
	round_num = 1
	round_winner = -1
	players = []
	make_world()
	build_viewports()
	build_hud()
	begin_round(false)


func make_world():
	# (re)builds players + first ball. gets called once per round
	if is_instance_valid(game3d):
		game3d.queue_free()
	game3d = Node3D.new()
	add_child(game3d)
	balls = []
	pickups = []
	build_players()
	spawn_ball(0.6)


func begin_round(rebuild):
	if rebuild:
		make_world()
		for v in views:
			var pn = players[v["pi"]]["node"].position
			v["pos"] = pn + v["offset"]
			v["look"] = pn
		reset_hud()
	countdown = 3.0
	msg_t = 0.0
	extra_timer = 0.0
	pending_end = -1.0
	pu_timer = 6.0
	round_winner = -1
	phase = "count"
	if num_players == 2:
		round_l.text = "ROUND %d  %s" % [round_num, ROUND_EMOJI[min(round_num - 1, ROUND_EMOJI.size() - 1)]]
		phase = "intro"
		show_round_intro()


func cleanup_game():
	free_card()
	for n in [game3d, vp_layer, hud_layer, over_layer]:
		if is_instance_valid(n):
			n.queue_free()
	players = []
	balls = []
	pickups = []
	views = []
	huds = []
	game3d = null
	vp_layer = null
	hud_layer = null
	over_layer = null
	over_sub = null
	over_loser = null
	over_record = null


func go_to_menu():
	cleanup_game()
	set_space_look(false)
	zg_root.visible = false
	low_fence.visible = true
	menu_cam.current = true
	for d in decor:
		d["node"].visible = true
	menu_root.visible = true
	show_title()


func play_again():
	cleanup_game()
	start_game()


func build_players():
	players = []
	for i in num_players:
		var made = make_player_node(player_colors[i], names[i])
		game3d.add_child(made["root"])
		var p = {
			"idx": i, "node": made["root"], "holder": made["holder"], "ring": made["ring"],
			"light": made["light"], "trail": made["trail"], "label": made["label"],
			"boost": made["boost"], "shield": made["shield"], "shield_mat": made["shield_mat"],
			"rring": made["rring"], "rring_mat": made["rring_mat"],
			"alive": true, "time": 0.0, "name": names[i], "color": player_colors[i],
			"facing": PI, "moving": false, "bob": 0.0, "vel": Vector3.ZERO,
			"fx": {"shield": 0.0, "speed": 0.0, "mini": 0.0, "repel": 0.0},
			"mini_s": 1.0, "sh_a": 0.0, "rr_a": 0.0, "sh_flash": 0.0, "shadow": null,
		}
		var y0 = 3.0 if zero_g else 0.0
		if num_players == 1:
			p["left"] = [KEY_A, KEY_LEFT]
			p["right"] = [KEY_D, KEY_RIGHT]
			p["up"] = [KEY_W, KEY_UP]
			p["down"] = [KEY_S, KEY_DOWN]
			p["vup"] = [KEY_Q, KEY_SPACE]
			p["vdown"] = [KEY_E, KEY_SHIFT]
			made["root"].position = Vector3(0, y0, 6)
		elif i == 0:
			p["left"] = [KEY_A]
			p["right"] = [KEY_D]
			p["up"] = [KEY_W]
			p["down"] = [KEY_S]
			p["vup"] = [KEY_Q]
			p["vdown"] = [KEY_E]
			made["root"].position = Vector3(-5, y0, 6)
		else:
			p["left"] = [KEY_LEFT]
			p["right"] = [KEY_RIGHT]
			p["up"] = [KEY_UP]
			p["down"] = [KEY_DOWN]
			p["vup"] = [KEY_PERIOD]
			p["vdown"] = [KEY_COMMA]
			made["root"].position = Vector3(5, y0, 6)
		if zero_g:
			made["ring"].position.y = 0.85
			var sd = make_shadow(player_colors[i], 0.8)
			game3d.add_child(sd)
			p["shadow"] = sd
		players.append(p)


func build_viewports():
	views = []
	vp_layer = CanvasLayer.new()
	vp_layer.layer = 0
	add_child(vp_layer)
	var hb = HBoxContainer.new()
	vp_layer.add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 0)
	var k = 1.0 if num_players == 1 else 1.25
	var offset = Vector3(0, 15.0, 12.0) * k
	for i in num_players:
		var c = SubViewportContainer.new()
		c.stretch = true
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.add_child(c)
		var vp = SubViewport.new()
		vp.msaa_3d = Viewport.MSAA_4X
		c.add_child(vp)
		var cam = Camera3D.new()
		cam.fov = 62
		vp.add_child(cam)
		cam.current = true
		var start = players[i]["node"].position + offset
		cam.position = start
		views.append({"cam": cam, "pi": i, "pos": start, "look": players[i]["node"].position, "shake": 0.0, "offset": offset})


func build_hud():
	huds = []
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 2
	add_child(hud_layer)
	hud_root = Control.new()
	hud_layer.add_child(hud_root)
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# red pulsing edges in no mercy
	if no_mercy:
		var grad = Gradient.new()
		grad.set_color(0, Color(1, 0, 0, 0))
		grad.set_color(1, Color(1, 0.05, 0.05, 0.45))
		grad.add_point(0.6, Color(1, 0, 0, 0))
		var gt = GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 256
		gt.height = 256
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		vignette = TextureRect.new()
		vignette.texture = gt
		vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		vignette.stretch_mode = TextureRect.STRETCH_SCALE
		vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(vignette)
		vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		vignette = null

	for i in num_players:
		var p = players[i]
		var panel = Control.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(panel)
		set_rect_anchors(panel, float(i) / num_players, 0.0, float(i + 1) / num_players, 1.0)

		# name, wins, time, active powerups
		var top = CenterContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(top)
		set_rect_anchors(top, 0.0, 0.0, 1.0, 0.0)
		top.offset_top = 6
		top.offset_bottom = 200
		var tv = VBoxContainer.new()
		tv.add_theme_constant_override("separation", -6)
		top.add_child(tv)
		tv.add_child(make_label(p["name"], 38, p["color"].lightened(0.25), 12))
		var wins_l = null
		if num_players == 2:
			wins_l = make_label("", 28, Color(1, 0.85, 0.25), 8)
			tv.add_child(wins_l)
		var time_l = make_label("0.0", 80, Color.WHITE, 16)
		tv.add_child(time_l)
		var fx_l = make_label("", 26, Color(1, 1, 1), 8)
		tv.add_child(fx_l)

		# mode tag, top left
		var tag = make_label(mode_text(), 24, Color(1, 0.3, 0.25) if no_mercy else Color(0.4, 1, 0.6), 8)
		panel.add_child(tag)
		set_rect_anchors(tag, 0.0, 0.0, 0.0, 0.0)
		tag.offset_left = 14
		tag.offset_top = 8
		tag.offset_right = 270
		tag.offset_bottom = 40
		tag.pivot_offset = Vector2(40, 16)

		# best time, 1 player only
		if num_players == 1:
			var bl = make_label("BEST  %.1f" % best_time[best_key()], 24, Color(0.8, 0.95, 1.0), 6)
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			panel.add_child(bl)
			set_rect_anchors(bl, 1.0, 0.0, 1.0, 0.0)
			bl.offset_left = -260
			bl.offset_right = -14
			bl.offset_top = 8
			bl.offset_bottom = 40

		# key hints at the bottom
		var kp = CenterContainer.new()
		kp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(kp)
		set_rect_anchors(kp, 0.0, 1.0, 1.0, 1.0)
		kp.offset_top = -250 if zero_g else -190
		kp.offset_bottom = -10
		var kv = VBoxContainer.new()
		kv.add_theme_constant_override("separation", 4)
		kp.add_child(kv)
		var grid = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		kv.add_child(grid)
		var arrows = (num_players == 2 and i == 1)
		var labels = ["", "W", "", "A", "S", "D"]
		if arrows:
			labels = ["", "↑", "", "←", "↓", "→"]
		var keysets = [[], p["up"], [], p["left"], p["down"], p["right"]]
		var caps = []
		for j in 6:
			if labels[j] == "":
				var spc = Control.new()
				spc.custom_minimum_size = Vector2(52, 52)
				grid.add_child(spc)
			else:
				var cap = make_keycap(labels[j], p["color"])
				grid.add_child(cap)
				caps.append({"panel": cap, "keys": keysets[j]})
		if zero_g:
			var vrow = HBoxContainer.new()
			vrow.add_theme_constant_override("separation", 6)
			vrow.alignment = BoxContainer.ALIGNMENT_CENTER
			kv.add_child(vrow)
			var ul = "Q"
			var dl = "E"
			if arrows:
				ul = "."
				dl = ","
			var capu = make_keycap(ul, p["color"])
			var capd = make_keycap(dl, p["color"])
			vrow.add_child(capu)
			vrow.add_child(capd)
			caps.append({"panel": capu, "keys": p["vup"]})
			caps.append({"panel": capd, "keys": p["vdown"]})
			kv.add_child(make_label("UP  /  DOWN", 20, p["color"].lightened(0.3), 5))
		var hint = "WASD  or  ARROW KEYS"
		if num_players == 2:
			hint = "ARROW KEYS" if i == 1 else "WASD"
		kv.add_child(make_label(hint, 22, p["color"].lightened(0.3), 6))

		# big CAUGHT text
		var caught = make_label("CAUGHT! ☠️", 100, Color(1, 0.25, 0.3), 20)
		panel.add_child(caught)
		set_rect_anchors(caught, 0.0, 0.0, 1.0, 1.0)
		caught.visible = false

		# "SHIELD!" style popup when you grab something
		var pick = make_label("", 80, Color.WHITE, 16)
		panel.add_child(pick)
		set_rect_anchors(pick, 0.0, 0.28, 1.0, 0.44)
		pick.modulate.a = 0.0

		huds.append({"time": time_l, "caps": caps, "caught": caught, "tag": tag, "wins": wins_l, "fx": fx_l, "pick": pick, "pick_tw": null})

	if num_players == 2:
		var div = ColorRect.new()
		div.color = Color(1, 1, 1, 0.9)
		div.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_root.add_child(div)
		set_rect_anchors(div, 0.5, 0.0, 0.5, 1.0)
		div.offset_left = -3
		div.offset_right = 3

	round_l = make_label("", 34, Color(1, 0.9, 0.3), 8)
	hud_root.add_child(round_l)
	set_rect_anchors(round_l, 0.5, 0.0, 0.5, 0.0)
	round_l.offset_left = -150
	round_l.offset_right = 150
	round_l.offset_top = 8
	round_l.offset_bottom = 48
	round_l.visible = num_players == 2

	# 3 2 1 GO
	msg_label = make_label("3", 210, Color(1, 0.3, 0.3), 30)
	hud_root.add_child(msg_label)
	set_rect_anchors(msg_label, 0.0, 0.0, 1.0, 1.0)
	update_wins()


func update_wins():
	for i in huds.size():
		var w = huds[i]["wins"]
		if w != null:
			w.text = "WINS  " + ("🏆".repeat(scores[i]) if scores[i] > 0 else "-")


func reset_hud():
	for h in huds:
		h["caught"].visible = false
		h["time"].add_theme_color_override("font_color", Color.WHITE)
		h["fx"].text = ""
	update_wins()


func spawn_ball(grace):
	var idx = balls.size() % BALL_COLORS.size()
	var made = make_ball_node(BALL_COLORS[idx])
	game3d.add_child(made["node"])
	var pos = Vector3(0, BALL_R, -ARENA + 3.0)
	var best_far = -1.0
	for k in 12:
		var cand = Vector3(randf_range(-ARENA + 2.0, ARENA - 2.0), BALL_R, randf_range(-ARENA + 2.0, ARENA - 2.0))
		if zero_g:
			cand.y = randf_range(2.0, CEIL - 2.0)
		var mind = 1000000.0
		for p in players:
			mind = min(mind, flat(cand - p["node"].position).length())
		if mind > best_far:
			best_far = mind
			pos = cand
	made["node"].position = pos
	var tgt = players[0]["node"].position + Vector3(0, 0.85, 0)
	var dir = tgt - pos
	if not zero_g:
		dir.y = 0.0
	dir = dir.normalized()
	var mark = null
	if zero_g:
		mark = make_shadow(BALL_COLORS[idx], 0.9)
		game3d.add_child(mark)
	balls.append({"node": made["node"], "body": made["body"], "ring": made["ring"], "vel": dir * ball_speed0, "vy": 0.0, "age": 0.0, "grace": grace, "zg": zero_g, "mark": mark})


# ----------------------------------------------------------
# main loop
# ----------------------------------------------------------
func _process(delta):
	t += delta
	animate_world(delta)
	if state == State.PLAYING:
		process_game(delta)
	elif state == State.GAMEOVER:
		process_over(delta)
	else:
		process_menu(delta)


func process_menu(delta):
	var a = t * 0.18
	menu_cam.position = Vector3(cos(a) * 30.0, 13.0 + sin(t * 0.4) * 2.0, sin(a) * 30.0)
	menu_cam.look_at(Vector3(0, 1.5, 0))
	for d in decor:
		step_ball(d, delta)
	for i in title_letters.size():
		var l = title_letters[i]
		if is_instance_valid(l):
			var col = Color.from_hsv(fmod(t * 0.25 + i * 0.18, 1.0), 0.75, 1.0)
			l.add_theme_color_override("font_color", col)
			l.rotation = sin(t * 2.5 + i * 1.1) * 0.07
			var s = 1.0 + 0.08 * sin(t * 4.0 + i * 0.9)
			l.scale = Vector2(s, s)
	for i in title_emojis.size():
		var e = title_emojis[i]
		if is_instance_valid(e):
			e.rotation = sin(t * 3.0 + i * 3.0) * 0.22
			var s2 = 1.0 + 0.12 * sin(t * 5.0 + i * 2.0)
			e.scale = Vector2(s2, s2)
	if is_instance_valid(sub_label):
		sub_label.add_theme_color_override("font_color", Color.from_hsv(fmod(t * 0.3, 1.0), 0.5, 1.0))
	if is_instance_valid(menu_title_label):
		menu_title_label.add_theme_color_override("font_color", Color.from_hsv(fmod(t * 0.15, 1.0), 0.45, 1.0))


func tick_balls_idle(delta):
	for b in balls:
		b["age"] += delta
		ball_visual(b, delta)


func process_game(delta):
	if phase == "intro":
		tick_balls_idle(delta)
		if update_card(delta):
			phase = "count"
			countdown = 3.0
	elif phase == "count":
		tick_balls_idle(delta)
		countdown -= delta
		if countdown <= 0.0:
			phase = "play"
			show_msg("GO!", Color(0.3, 1.0, 0.4))
	elif phase == "play":
		play_step(delta)
	elif phase == "result":
		if update_card(delta):
			after_result()
			if state != State.PLAYING:
				return

	update_player_visuals(delta)
	update_effects(delta)
	update_pickups(delta)
	update_marks()
	update_cameras(delta)
	update_hud(delta)
	update_msg(delta)

	if pending_end > 0.0 and phase == "play":
		pending_end -= delta
		if pending_end <= 0.0:
			end_round()


func play_step(delta):
	for p in players:
		if not p["alive"]:
			continue
		p["time"] += delta
		var d = Vector3.ZERO
		if any_key(p["left"]):
			d.x -= 1.0
		if any_key(p["right"]):
			d.x += 1.0
		if any_key(p["up"]):
			d.z -= 1.0
		if any_key(p["down"]):
			d.z += 1.0
		var mult = 1.7 if p["fx"]["speed"] > 0.0 else 1.0
		var lim = ARENA - PLAYER_R - 0.3
		if d.length() > 0.1:
			p["facing"] = atan2(-d.x, -d.z)

		if zero_g:
			var dy = 0.0
			if any_key(p["vup"]):
				dy += 1.0
			if any_key(p["vdown"]):
				dy -= 1.0
			var wish = Vector3(d.x, dy, d.z)
			p["moving"] = wish.length() > 0.1
			var vv = p["vel"]
			if p["moving"]:
				vv += wish.normalized() * ZG_ACCEL * mult * delta
			vv *= exp(-1.4 * delta)   # light drag so you drift a bit but not forever
			var cap = PLAYER_SPEED * 1.1 * mult
			if vv.length() > cap:
				vv = vv.normalized() * cap
			var np = p["node"].position + vv * delta
			if abs(np.x) > lim:
				np.x = clamp(np.x, -lim, lim)
				vv.x = 0.0
			if abs(np.z) > lim:
				np.z = clamp(np.z, -lim, lim)
				vv.z = 0.0
			if np.y < 0.0 or np.y > CEIL - 2.0:
				np.y = clamp(np.y, 0.0, CEIL - 2.0)
				vv.y = 0.0
			p["vel"] = vv
			p["node"].position = np
		else:
			p["moving"] = d.length() > 0.1
			if p["moving"]:
				d = d.normalized()
				var np2 = p["node"].position + d * PLAYER_SPEED * mult * delta
				np2.x = clamp(np2.x, -lim, lim)
				np2.z = clamp(np2.z, -lim, lim)
				p["node"].position = np2
		p["trail"].emitting = p["moving"]
		p["boost"].emitting = p["moving"] and p["fx"]["speed"] > 0.0

	# powerups
	if pending_end < 0.0:
		pu_timer -= delta
		if pu_timer <= 0.0:
			pu_timer = randf_range(5.0, 8.0)
			if pickups.size() < 3:
				spawn_pickup()
		check_pickups()

	update_balls(delta)
	check_hits()

	if no_mercy and pending_end < 0.0:
		extra_timer += delta
		if extra_timer > 10.0 and balls.size() < 4:
			extra_timer = 0.0
			spawn_ball(1.2)
			show_msg("ANOTHER BALL!", Color(1.0, 0.8, 0.2))


func update_balls(delta):
	for b in balls:
		var node = b["node"]
		var target = null
		var best_d = 1000000.0
		for p in players:
			if p["alive"]:
				var c = p["node"].position + Vector3(0, 0.85, 0)
				var dd = (c - node.position).length() if zero_g else flat(c - node.position).length()
				if dd < best_d:
					best_d = dd
					target = c
		var v = b["vel"]
		var spd = v.length()
		var dirv = v.normalized()
		if target != null:
			var to = target - node.position
			if not zero_g:
				to.y = 0.0
			if to.length() > 0.05:
				var desired = to.normalized()
				if spd < 0.01:
					dirv = desired
				var nd = dirv.lerp(desired, clamp(turn_rate * delta, 0.0, 1.0))
				if nd.length() < 0.001:
					nd = desired
				dirv = nd.normalized()
		b["vel"] = dirv * min(spd + speedup * delta, max_speed)

		# repel blast shoves balls away from whoever has it
		for p in players:
			if p["alive"] and p["fx"]["repel"] > 0.0:
				var away = node.position - p["node"].position
				if not zero_g:
					away.y = 0.0
				var dist = away.length()
				if dist < REPEL_RANGE and dist > 0.01:
					b["vel"] += away / dist * (1.0 - dist / REPEL_RANGE) * 90.0 * delta
		step_ball(b, delta)


func check_hits():
	for b in balls:
		if b["grace"] > 0.0:
			continue
		for i in players.size():
			var p = players[i]
			if not p["alive"]:
				continue
			var s = p["mini_s"]
			var pc = p["node"].position + Vector3(0, 0.85 * s, 0)
			var reach = (BALL_R + PLAYER_R * s) * 0.85
			if b["node"].position.distance_to(pc) < reach:
				if p["fx"]["shield"] > 0.0:
					bounce_off(b, p, pc)
				else:
					catch_player(i)


func bounce_off(b, p, pc):
	var away = b["node"].position - pc
	if not zero_g:
		away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(0, 0, 1)
	away = away.normalized()
	var spd = max(b["vel"].length(), ball_speed0)
	b["vel"] = away * min(spd * 1.1, max_speed)
	b["grace"] = 0.2
	b["node"].position += away * 0.5
	p["sh_flash"] = 0.5
	var col = PU["shield"]["color"]
	burst(pc + away * 0.9, col)
	shock_ring(pc, col)
	for v in views:
		if v["pi"] == p["idx"]:
			v["shake"] = 0.4


func catch_player(i):
	var p = players[i]
	p["alive"] = false
	p["holder"].visible = false
	p["ring"].visible = false
	p["light"].visible = false
	p["trail"].emitting = false
	p["boost"].emitting = false
	p["shield"].visible = false
	p["rring"].visible = false
	for k in PU_KEYS:
		p["fx"][k] = 0.0
	p["label"].text = "OUT"
	burst(p["node"].position + Vector3(0, 0.9, 0), p["color"])
	for v in views:
		if v["pi"] == i:
			v["shake"] = 1.0
		else:
			v["shake"] = 0.35
	var h = huds[i]
	h["caught"].visible = true
	h["caught"].pivot_offset = h["caught"].size / 2.0
	h["caught"].scale = Vector2(3, 3)
	var tw = h["caught"].create_tween()
	tw.tween_property(h["caught"], "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	h["time"].add_theme_color_override("font_color", Color(1, 0.35, 0.35))
	# in 2 player the round ends right after the first catch
	if pending_end < 0.0:
		pending_end = 1.3


# ----------------------------------------------------------
# powerups
# ----------------------------------------------------------
func spawn_pickup():
	var kind = PU_KEYS[randi() % PU_KEYS.size()]
	var lim = ARENA - 3.0
	var y = 1.1
	if zero_g:
		y = randf_range(1.5, CEIL - 3.0)
	var pos = Vector3(randf_range(-lim, lim), y, randf_range(-lim, lim))
	var made = make_pickup(kind, pos)
	game3d.add_child(made["root"])
	made["root"].position = pos
	made["root"].scale = Vector3(0.01, 0.01, 0.01)
	pickups.append(made)


func check_pickups():
	for i in range(pickups.size() - 1, -1, -1):
		var pk = pickups[i]
		if not is_instance_valid(pk["root"]):
			pickups.remove_at(i)
			continue
		for p in players:
			if not p["alive"]:
				continue
			var pc = p["node"].position + Vector3(0, 0.85 * p["mini_s"], 0)
			if pc.distance_to(pk["root"].position) < 1.5:
				collect(p, pk)
				pickups.remove_at(i)
				break


func collect(p, pk):
	var info = PU[pk["kind"]]
	p["fx"][pk["kind"]] = info["dur"]    # grabbing the same one again just refreshes the timer
	var pos = pk["root"].position
	burst(pos, info["color"])
	shock_ring(pos, info["color"])
	popup3d(p["node"].position + Vector3(0, 3.1, 0), info["name"] + "!", info["color"])
	hud_pick(p["idx"], info)
	pk["root"].queue_free()


func hud_pick(i, info):
	var h = huds[i]
	var l = h["pick"]
	if h["pick_tw"] != null and h["pick_tw"].is_valid():
		h["pick_tw"].kill()
	l.text = info["emoji"] + " " + info["name"] + "!"
	l.add_theme_color_override("font_color", info["color"].lightened(0.3))
	l.pivot_offset = l.size / 2.0
	l.modulate.a = 1.0
	l.scale = Vector2(1.9, 1.9)
	var tw = l.create_tween()
	h["pick_tw"] = tw
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.45)


func update_pickups(delta):
	for i in range(pickups.size() - 1, -1, -1):
		var pk = pickups[i]
		if not is_instance_valid(pk["root"]):
			pickups.remove_at(i)
			continue
		pk["age"] += delta
		var remaining = PICKUP_LIFE - pk["age"]
		var s = clamp(pk["age"] / 0.4, 0.0, 1.0)
		pk["root"].visible = true
		if remaining < 2.0:
			# about to disappear: blink and shrink away
			s *= clamp(remaining / 2.0, 0.0, 1.0)
			pk["root"].visible = int(pk["age"] * 9.0) % 2 == 0
		pk["root"].scale = Vector3.ONE * max(s, 0.01)
		pk["holder"].position.y = sin(t * 2.0 + pk["ph"]) * 0.25
		pk["core"].rotation.y += delta * 2.5
		pk["core"].rotation.x += delta * 1.2
		for r in pk["rings"]:
			r["node"].rotation += r["axis"] * delta
		pk["label"].modulate.a = clamp(remaining, 0.0, 1.0)
		if remaining <= 0.0:
			pk["root"].queue_free()
			pickups.remove_at(i)


func update_effects(delta):
	for p in players:
		var fx = p["fx"]
		for k in PU_KEYS:
			if fx[k] > 0.0:
				fx[k] = max(0.0, fx[k] - delta)

		# shield bubble fades in and out
		var sh_target = 0.3 if fx["shield"] > 0.0 else 0.0
		p["sh_a"] = move_toward(p["sh_a"], sh_target, delta * 0.9)
		p["sh_flash"] = max(0.0, p["sh_flash"] - delta * 2.0)
		var sa = p["sh_a"] + p["sh_flash"] * 0.5
		if fx["shield"] > 0.0 and fx["shield"] < 0.8:
			sa *= 0.55 + 0.45 * sin(t * 30.0)    # flickers right before it runs out
		p["shield"].visible = sa > 0.01 and p["alive"]
		var sm = p["shield_mat"]
		sm.albedo_color = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, clamp(sa, 0.0, 0.8))
		p["shield"].scale = Vector3.ONE * (1.0 + 0.04 * sin(t * 8.0) + p["sh_flash"] * 0.2)

		# repel pulse
		var rr_target = 0.7 if fx["repel"] > 0.0 else 0.0
		p["rr_a"] = move_toward(p["rr_a"], rr_target, delta * 2.0)
		var k2 = fmod(t * 1.4, 1.0)
		var rs = lerp(0.6, REPEL_RANGE, k2)
		p["rring"].scale = Vector3(rs, 1.0, rs)
		p["rring"].position.y = 0.85 if zero_g else 0.15
		var rm = p["rring_mat"]
		rm.albedo_color = Color(rm.albedo_color.r, rm.albedo_color.g, rm.albedo_color.b, p["rr_a"] * (1.0 - k2))
		p["rring"].visible = p["rr_a"] > 0.01 and p["alive"]

		# mini shrinks and grows back smoothly
		var mini_target = 0.55 if fx["mini"] > 0.0 else 1.0
		p["mini_s"] = move_toward(p["mini_s"], mini_target, delta * 1.8)


func update_marks():
	if not zero_g:
		return
	for b in balls:
		if b["mark"] != null:
			var bp = b["node"].position
			b["mark"].position = Vector3(bp.x, 0.04, bp.z)
	for p in players:
		if p["shadow"] != null:
			var pp = p["node"].position
			p["shadow"].position = Vector3(pp.x, 0.04, pp.z)
			p["shadow"].visible = p["alive"]


func update_player_visuals(delta):
	for p in players:
		var h = p["holder"]
		h.rotation.y = lerp_angle(h.rotation.y, p["facing"], 1.0 - exp(-14.0 * delta))
		var base = p["mini_s"]
		if p["alive"]:
			if zero_g:
				h.position.y = 0.1 * sin(t * 2.5 + p["idx"])
				h.scale = Vector3.ONE * base
			elif p["moving"]:
				p["bob"] += delta * 14.0
				h.position.y = abs(sin(p["bob"])) * 0.16 * base
				var sq = 0.06 * sin(p["bob"] * 2.0)
				h.scale = Vector3(1.0 - sq, 1.0 + sq, 1.0 - sq) * base
			else:
				h.position.y = 0.04 * sin(t * 3.0)
				h.scale = Vector3.ONE * base
			p["ring"].rotation.y += delta * 3.0


func update_cameras(delta):
	for v in views:
		var p = players[v["pi"]]
		var focus = p
		if not p["alive"]:
			for q in players:
				if q["alive"]:
					focus = q
		var fp = focus["node"].position
		v["pos"] = v["pos"].lerp(fp + v["offset"], 1.0 - exp(-6.0 * delta))
		v["look"] = v["look"].lerp(fp + Vector3(0, 0.5, 0), 1.0 - exp(-8.0 * delta))
		var sh = Vector3.ZERO
		if v["shake"] > 0.0:
			sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * v["shake"] * 0.5
			v["shake"] = max(0.0, v["shake"] - delta * 2.5)
		v["cam"].position = v["pos"] + sh
		v["cam"].look_at(v["look"])


func update_hud(delta):
	for i in huds.size():
		var h = huds[i]
		var p = players[i]
		h["time"].text = "%.1f" % p["time"]
		for c in h["caps"]:
			var down = any_key(c["keys"])
			c["panel"].modulate = Color(1.8, 1.8, 1.8) if down else Color.WHITE
			var s = 1.12 if down else 1.0
			c["panel"].scale = Vector2(s, s)
		if no_mercy:
			var s2 = 1.0 + 0.08 * sin(t * 8.0)
			h["tag"].scale = Vector2(s2, s2)
		var txt = ""
		for k in PU_KEYS:
			if p["fx"][k] > 0.0:
				txt += PU[k]["emoji"] + " " + PU[k]["name"] + " %.1f    " % p["fx"][k]
		h["fx"].text = txt
	if vignette != null:
		vignette.modulate.a = 0.55 + 0.45 * sin(t * 4.0)


func show_msg(text, color):
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", color)
	msg_t = 1.0


func update_msg(delta):
	msg_label.pivot_offset = msg_label.size / 2.0
	if phase == "count" and countdown > 0.0:
		var n = int(ceil(countdown))
		msg_label.text = str(n)
		var cols = [Color(0.3, 1.0, 0.4), Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.3)]
		msg_label.add_theme_color_override("font_color", cols[clamp(n, 1, 3) - 1])
		var frac = countdown - floor(countdown)
		msg_label.scale = Vector2.ONE * (1.0 + 0.5 * frac)
		msg_label.modulate.a = 1.0
	elif msg_t > 0.0:
		msg_t -= delta
		msg_label.scale = Vector2.ONE * (1.0 + 0.4 * clamp(msg_t - 0.5, 0.0, 1.0))
		msg_label.modulate.a = clamp(msg_t * 2.5, 0.0, 1.0)
	else:
		msg_label.modulate.a = 0.0


# ----------------------------------------------------------
# dramatic round cards (round intro + round result)
# ----------------------------------------------------------
func show_card(big_text, sub_text, small_text, emo_l, emo_r, color, dur):
	free_card()
	var layer = CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.06, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# cinema bars that slide in
	var bar_t = ColorRect.new()
	bar_t.color = Color(0, 0, 0, 1)
	bar_t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_t)
	set_rect_anchors(bar_t, 0.0, 0.0, 1.0, 0.0)
	var strip_t = ColorRect.new()
	strip_t.color = color
	strip_t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_t.add_child(strip_t)
	set_rect_anchors(strip_t, 0.0, 1.0, 1.0, 1.0)
	strip_t.offset_top = -6
	var bar_b = ColorRect.new()
	bar_b.color = Color(0, 0, 0, 1)
	bar_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_b)
	set_rect_anchors(bar_b, 0.0, 1.0, 1.0, 1.0)
	var strip_b = ColorRect.new()
	strip_b.color = color
	strip_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_b.add_child(strip_b)
	set_rect_anchors(strip_b, 0.0, 0.0, 1.0, 0.0)
	strip_b.offset_bottom = 6

	var cc = CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)

	var bs = max(70, 150 - max(0, big_text.length() - 7) * 8)
	var el = make_label(emo_l, 140, Color.WHITE, 0)
	row.add_child(el)
	var big = make_label(big_text, bs, color, 28)
	row.add_child(big)
	var er = make_label(emo_r, 140, Color.WHITE, 0)
	row.add_child(er)
	var sub = make_label(sub_text, 58, Color.WHITE, 12)
	vb.add_child(sub)
	var small = make_label(small_text, 36, Color(1, 0.9, 0.4), 8)
	vb.add_child(small)

	var flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0.9)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for n in [bar_t, bar_b]:
		n.custom_minimum_size = Vector2(0, 130)
	card = {"layer": layer, "root": root, "dim": dim, "bar_t": bar_t, "bar_b": bar_b, "big": big, "el": el, "er": er,
		"sub": sub, "small": small, "flash": flash, "t": 0.0, "dur": dur, "color": color, "slammed": false}


func free_card():
	if not card.is_empty() and is_instance_valid(card["layer"]):
		card["layer"].queue_free()
	card = {}


func update_card(delta):
	# returns true once the card is finished
	if card.is_empty():
		return true
	card["t"] += delta
	var ct = card["t"]
	var dur = card["dur"]
	card["root"].modulate.a = clamp((dur - ct) / 0.4, 0.0, 1.0)
	card["dim"].color.a = 0.7 * clamp(ct / 0.25, 0.0, 1.0)

	# bars
	var ek = clamp(ct / 0.35, 0.0, 1.0)
	var ee = 1.0 - pow(1.0 - ek, 3.0)
	card["bar_t"].offset_top = -130.0 * (1.0 - ee)
	card["bar_t"].offset_bottom = card["bar_t"].offset_top + 130.0
	card["bar_b"].offset_bottom = 130.0 * (1.0 - ee)
	card["bar_b"].offset_top = card["bar_b"].offset_bottom - 130.0

	# main text slams in
	var big = card["big"]
	big.pivot_offset = big.size / 2.0
	var bk = clamp(ct / 0.4, 0.0, 1.0)
	var be = 1.0 - pow(1.0 - bk, 4.0)
	big.scale = Vector2.ONE * lerp(7.0, 1.0, be) * (1.0 + 0.03 * sin(ct * 9.0) * bk)
	big.rotation = sin(ct * 55.0) * 0.05 * (1.0 - bk)
	big.modulate.a = clamp(ct / 0.15, 0.0, 1.0)
	big.add_theme_color_override("font_color", card["color"].lightened(0.2 + 0.2 * sin(ct * 12.0)))

	if ct > 0.38 and not card["slammed"]:
		card["slammed"] = true
		for v in views:
			v["shake"] = 0.9
	var fa = 0.9 * max(0.0, 1.0 - ct / 0.3)
	if ct > 0.38:
		fa += 0.4 * max(0.0, 1.0 - (ct - 0.38) / 0.25)
	card["flash"].color.a = fa

	# emojis pop in a little later and wiggle
	var ek2 = clamp((ct - 0.3) / 0.4, 0.0, 1.0)
	var ee2 = 1.0 - pow(1.0 - ek2, 3.0)
	var idx = 0
	for e in [card["el"], card["er"]]:
		e.pivot_offset = e.size / 2.0
		e.scale = Vector2.ONE * ee2 * (1.0 + 0.1 * sin(ct * 6.0 + idx))
		e.rotation = sin(ct * 4.0 + idx * 3.0) * 0.18
		e.modulate.a = ek2
		idx += 1

	var sk = clamp((ct - 0.6) / 0.35, 0.0, 1.0)
	card["sub"].pivot_offset = card["sub"].size / 2.0
	card["sub"].modulate.a = sk
	card["sub"].scale = Vector2.ONE * lerp(1.8, 1.0, 1.0 - pow(1.0 - sk, 3.0))
	card["small"].modulate.a = clamp((ct - 0.85) / 0.35, 0.0, 1.0)

	if ct >= dur:
		free_card()
		return true
	return false


func show_round_intro():
	var i = min(round_num - 1, ROUND_EMOJI.size() - 1)
	var emo = ROUND_EMOJI[i]
	var big = "ROUND %d" % round_num
	var small = "FIRST TO %d WINS" % WINS_NEEDED
	var match_pt = WINS_NEEDED - 1
	if scores[0] == match_pt and scores[1] == match_pt:
		big = "FINAL ROUND"
		small = "☠️  NEXT POINT WINS THE MATCH  ☠️"
	elif scores[0] == match_pt or scores[1] == match_pt:
		small = "⚠️  MATCH POINT  ⚠️"
	if round_num > 1:
		small += "      SCORE  %d - %d" % [scores[0], scores[1]]
	var sub = names[0].to_upper() + "   🆚   " + names[1].to_upper()
	show_card(big, sub, small, emo, emo, ROUND_COLORS[i], 2.7)


func end_round():
	if num_players == 1:
		end_game()
		return
	var w = -1
	var a = players[0]
	var b = players[1]
	if a["alive"] and not b["alive"]:
		w = 0
	elif b["alive"] and not a["alive"]:
		w = 1
	else:
		# both got caught, longest survivor takes it
		var diff = a["time"] - b["time"]
		if abs(diff) >= 0.05:
			w = 0 if diff > 0.0 else 1
	round_winner = w
	phase = "result"
	pending_end = -1.0
	if w == -1:
		show_card("DRAW", "NOBODY SCORES", "REPLAYING ROUND %d" % round_num, "🤝", "🤝", Color(1.0, 0.85, 0.2), 2.4)
		return
	scores[w] += 1
	update_wins()
	var loser = 1 - w
	var champ = scores[w] >= WINS_NEEDED
	var sub = "ROUND %d" % round_num
	var emo = "🏆"
	if champ:
		sub = "TAKES THE MATCH!"
		emo = "👑"
	var small = "%s  ☠️        SCORE  %d - %d" % [names[loser].to_upper(), scores[0], scores[1]]
	show_card(names[w].to_upper() + (" WINS" if not champ else ""), sub, small, emo, emo, player_colors[w], 2.6)


func after_result():
	if round_winner != -1 and scores[round_winner] >= WINS_NEEDED:
		end_game()
	else:
		if round_winner != -1:
			round_num += 1
		begin_round(true)


# ----------------------------------------------------------
# game over
# ----------------------------------------------------------
func end_game():
	state = State.GAMEOVER
	over_t = 0.0
	new_record = false
	if num_players == 1:
		var key = best_key()
		var tm = players[0]["time"]
		if tm > best_time[key]:
			best_time[key] = tm
			new_record = true
			save_best()
		over_winner = -1
	else:
		over_winner = round_winner
	build_over_screen()


func make_confetti(vsize):
	var c = CPUParticles2D.new()
	c.position = Vector2(vsize.x / 2.0, -20.0)
	c.amount = 140
	c.lifetime = 5.0
	c.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	c.emission_rect_extents = Vector2(vsize.x / 2.0, 10.0)
	c.direction = Vector2(0, 1)
	c.spread = 20.0
	c.gravity = Vector2(0, 260)
	c.initial_velocity_min = 120.0
	c.initial_velocity_max = 300.0
	c.angular_velocity_min = -360.0
	c.angular_velocity_max = 360.0
	c.scale_amount_min = 6.0
	c.scale_amount_max = 12.0
	var g = Gradient.new()
	g.set_color(0, Color(1, 0.2, 0.3))
	g.set_color(1, Color(1, 0.3, 0.9))
	g.add_point(0.2, Color(1, 0.9, 0.2))
	g.add_point(0.4, Color(0.3, 1, 0.4))
	g.add_point(0.6, Color(0.2, 0.9, 1))
	g.add_point(0.8, Color(0.3, 0.4, 1))
	c.color_initial_ramp = g
	c.emitting = true
	return c


func make_embers(vsize):
	var c = CPUParticles2D.new()
	c.position = Vector2(vsize.x / 2.0, vsize.y + 10.0)
	c.amount = 90
	c.lifetime = 4.0
	c.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	c.emission_rect_extents = Vector2(vsize.x / 2.0, 5.0)
	c.direction = Vector2(0, -1)
	c.spread = 25.0
	c.gravity = Vector2(0, -40)
	c.initial_velocity_min = 80.0
	c.initial_velocity_max = 220.0
	c.scale_amount_min = 3.0
	c.scale_amount_max = 8.0
	var g = Gradient.new()
	g.set_color(0, Color(1, 0.15, 0.1))
	g.set_color(1, Color(1, 0.9, 0.3))
	g.add_point(0.5, Color(1, 0.5, 0.1))
	c.color_initial_ramp = g
	c.emitting = true
	return c


func build_over_screen():
	over_layer = CanvasLayer.new()
	over_layer.layer = 10
	add_child(over_layer)
	var root = Control.new()
	over_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	over_dim = ColorRect.new()
	over_dim.color = Color(0.03, 0.0, 0.1, 0.0)
	over_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(over_dim)
	over_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vsize = get_viewport().get_visible_rect().size
	var celebrate = new_record or over_winner != -1
	root.add_child(make_confetti(vsize) if celebrate else make_embers(vsize))

	over_counters = []
	over_record = null
	over_sub = null
	over_loser = null

	var cc = CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)

	var pcolor = Color(1.0, 0.3, 0.3)
	if num_players == 1:
		over_title = make_label("☠️ GAME OVER ☠️", 120, Color(1, 0.2, 0.25), 26)
		vb.add_child(over_title)
	else:
		var loser = 1 - over_winner
		over_wcolor = player_colors[over_winner]
		pcolor = over_wcolor
		over_loser = make_label(names[loser].to_upper() + " HAS ☠️", 84, player_colors[loser].lightened(0.2), 20)
		vb.add_child(over_loser)
		over_title = make_label("GAME OVER", 120, Color(1, 0.2, 0.25), 26)
		vb.add_child(over_title)
		over_sub = make_label("👑 " + names[over_winner].to_upper() + " WINS THE MATCH", 52, over_wcolor, 14)
		vb.add_child(over_sub)

	over_panel = PanelContainer.new()
	var ps = StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.03, 0.16, 0.88)
	ps.set_corner_radius_all(32)
	ps.set_border_width_all(6)
	ps.border_color = pcolor
	ps.shadow_color = Color(pcolor.r, pcolor.g, pcolor.b, 0.5)
	ps.shadow_size = 30
	ps.content_margin_left = 40
	ps.content_margin_right = 40
	ps.content_margin_top = 14
	ps.content_margin_bottom = 14
	over_panel.add_theme_stylebox_override("panel", ps)
	over_panel.custom_minimum_size = Vector2(700, 0)
	add_center(vb, over_panel)
	var pv = VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	over_panel.add_child(pv)

	var key = best_key()
	if num_players == 1:
		pv.add_child(make_label(mode_text(), 24, Color(1, 0.5, 0.4) if no_mercy else Color(0.5, 1, 0.7), 6))
		pv.add_child(make_label("YOU SURVIVED", 32, Color(0.8, 0.9, 1.0), 8))
		var tl = make_label("0.0 s", 100, Color(1, 0.85, 0.2), 18)
		pv.add_child(tl)
		over_counters.append({"label": tl, "target": players[0]["time"], "int": false})
		pv.add_child(make_label("BEST: %.1f s" % best_time[key], 34, Color(0.6, 1.0, 0.8), 8))
		if new_record:
			over_record = make_label("NEW RECORD!", 44, Color(1, 0.4, 0.9), 12)
			pv.add_child(over_record)
	else:
		pv.add_child(make_label(mode_text() + "   -   ROUNDS WON", 24, Color(1, 0.5, 0.4) if no_mercy else Color(0.5, 1, 0.7), 6))
		for i in 2:
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 20)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			pv.add_child(row)
			var nl = make_label(names[i], 44, player_colors[i].lightened(0.2), 12)
			nl.custom_minimum_size = Vector2(280, 0)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			row.add_child(nl)
			var tl2 = make_label("0", 64, Color.WHITE, 14)
			tl2.custom_minimum_size = Vector2(120, 0)
			row.add_child(tl2)
			over_counters.append({"label": tl2, "target": scores[i], "int": true})
			var wl = make_label("WINNER" if over_winner == i else "", 30, Color(1, 0.85, 0.2), 8)
			wl.custom_minimum_size = Vector2(150, 0)
			row.add_child(wl)
			if over_winner == i:
				over_record = wl

	over_buttons = HBoxContainer.new()
	over_buttons.add_theme_constant_override("separation", 24)
	over_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var again = make_button("PLAY AGAIN", Color(0.15, 0.8, 0.35), 330, 72, 38)
	again.pressed.connect(play_again)
	var menu = make_button("MAIN MENU", Color(0.2, 0.5, 1.0), 330, 72, 38)
	menu.pressed.connect(go_to_menu)
	over_buttons.add_child(again)
	over_buttons.add_child(menu)
	vb.add_child(over_buttons)
	over_hint = make_label("R = play again      ESC = menu", 20, Color(1, 1, 1, 0.6), 4)
	vb.add_child(over_hint)

	over_flash = ColorRect.new()
	over_flash.color = Color(1, 1, 1, 0.8)
	over_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(over_flash)
	over_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func process_over(delta):
	over_t += delta
	var k = clamp(over_t / 0.7, 0.0, 1.0)
	var e = 1.0 - pow(1.0 - k, 3.0)
	over_dim.color.a = 0.75 * clamp(over_t / 0.4, 0.0, 1.0)
	over_flash.color.a = 0.8 * max(0.0, 1.0 - over_t / 0.5)

	# big shaking, pulsing title
	over_title.pivot_offset = over_title.size / 2.0
	var pulse = 1.0 + 0.045 * sin(over_t * 6.0)
	over_title.scale = Vector2.ONE * lerp(3.5, 1.0, e) * pulse
	over_title.rotation = sin(over_t * 45.0) * 0.05 * (1.0 - k)
	over_title.modulate.a = k
	over_title.add_theme_color_override("font_color", Color.from_hsv(0.07 * (0.5 + 0.5 * sin(over_t * 5.0)), 0.9, 1.0))

	if over_loser != null:
		var kl = clamp((over_t - 0.15) / 0.5, 0.0, 1.0)
		over_loser.pivot_offset = over_loser.size / 2.0
		over_loser.scale = Vector2.ONE * lerp(2.2, 1.0, 1.0 - pow(1.0 - kl, 3.0)) * (1.0 + 0.03 * sin(over_t * 5.0))
		over_loser.modulate.a = kl

	if over_sub != null:
		var k2 = clamp((over_t - 0.45) / 0.5, 0.0, 1.0)
		var e2 = 1.0 - pow(1.0 - k2, 3.0)
		over_sub.pivot_offset = over_sub.size / 2.0
		over_sub.scale = Vector2.ONE * lerp(2.5, 1.0, e2) * (1.0 + 0.04 * sin(over_t * 7.0))
		over_sub.modulate.a = k2
		over_sub.add_theme_color_override("font_color", over_wcolor.lightened(0.3 * (0.5 + 0.5 * sin(over_t * 6.0))))

	# panel pops in
	var pk = clamp((over_t - 0.7) / 0.4, 0.0, 1.0)
	over_panel.pivot_offset = over_panel.size / 2.0
	over_panel.modulate.a = pk
	over_panel.scale = Vector2.ONE * lerp(0.7, 1.0, pk)

	# numbers count up
	var ck = clamp((over_t - 0.8) / 1.0, 0.0, 1.0)
	var ce = 1.0 - pow(1.0 - ck, 3.0)
	for c in over_counters:
		if c["int"]:
			c["label"].text = str(int(round(c["target"] * ce)))
		else:
			c["label"].text = "%.1f s" % (c["target"] * ce)

	if over_record != null:
		over_record.pivot_offset = over_record.size / 2.0
		over_record.scale = Vector2.ONE * (1.0 + 0.1 * sin(over_t * 8.0))
		over_record.add_theme_color_override("font_color", Color.from_hsv(fmod(over_t * 0.8, 1.0), 0.6, 1.0))
		over_record.modulate.a = pk

	var bk = clamp((over_t - 1.1) / 0.4, 0.0, 1.0)
	over_buttons.modulate.a = bk
	over_hint.modulate.a = bk * 0.6


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if state == State.PLAYING and event.keycode == KEY_ESCAPE:
			go_to_menu()
		elif state == State.GAMEOVER:
			if event.keycode == KEY_R or event.keycode == KEY_ENTER:
				play_again()
			elif event.keycode == KEY_ESCAPE or event.keycode == KEY_M:
				go_to_menu()
