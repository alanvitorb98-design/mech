extends Node3D
# BornToMech, porte do protótipo 0.4 (navegador) para Godot 4.
# A cena inteira é montada em código, com as mesmas medidas da versão web:
# Y pra cima, -Z pra frente, metros.

const State = preload("res://scripts/state.gd")
const PanelDraw = preload("res://scripts/panel.gd")
const AudioKit = preload("res://scripts/audio.gd")

const DEG = PI / 180.0
const HIP = 19.3
const LEG = 9.45
const ANK = 1.8
const WAVES = [
	{"crawlers": 10, "colossi": []},
	{"crawlers": 8, "colossi": [0.0]},
	{"crawlers": 16, "colossi": [0.0]},
	{"crawlers": 12, "colossi": [0.0, 25.0]},
	{"crawlers": 22, "colossi": [0.0, 14.0]},
]
var SWITCHES = [
	{"id": "bat", "label": "BATERIA", "n": "1", "kind": "toggle"},
	{"id": "fuel", "label": "COMBUST.", "n": "2", "kind": "toggle"},
	{"id": "start", "label": "PARTIDA", "n": "3", "kind": "button"},
	{"id": "hyd", "label": "HIDRÁUL.", "n": "4", "kind": "toggle"},
	{"id": "reactor", "label": "REATOR", "n": "5", "kind": "guarded"},
	{"id": "locks", "label": "TRAVAS", "n": "6", "kind": "toggle"},
	{"id": "light", "label": "LUZ", "n": "", "kind": "toggle"},
]
const STEP_TEXT = {
	"bat": "Chave 1: bateria", "fuel": "Chave 2: bomba de combustível", "start": "Botão 3: partida da turbina",
	"hyd": "Chave 4: bomba hidráulica", "reactor": "Chave 5: reator (abra a tampa e ligue)", "locks": "Chave 6: soltar as travas das pernas",
}
const STEP_ORDER = ["bat", "fuel", "start", "hyd", "reactor", "locks"]

var S = null          # partida em andamento (ou a de fundo do menu)
var snd
var mouse_l = false
var mouse_r = false
var muted = false

# nós
var mech
var torso
var cockpit
var head
var cam
var legs = []
var arm_r
var arm_l
var pendulum
var pendulum2
var cabin_light
var alarm_light
var muzzle_light
var sight_lamp_mat
var panels = []
var q_levers = []
var sticks = []
var hovered_sw = null
var puffs = []
var puff_i = 0
var tracers = []
var tracer_i = 0
var enemy_nodes = []
var models = {}
var dust

# materiais
var m_metal
var m_dark
var m_rust
var m_hose
var m_hazard
var m_plate

# interface
var ui_layer
var ui_title
var ui_body
var ui_quick
var ui_button
var vignette


func hexc(h):
	return Color(((h >> 16) & 255) / 255.0, ((h >> 8) & 255) / 255.0, (h & 255) / 255.0)


func make_mat(h, rough = 0.85, metal = 0.3):
	var m = StandardMaterial3D.new()
	m.albedo_color = hexc(h)
	m.roughness = rough
	m.metallic = metal
	return m


func unlit(h):
	var m = StandardMaterial3D.new()
	m.albedo_color = hexc(h)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func glow_mat(h, emis, energy):
	var m = StandardMaterial3D.new()
	m.albedo_color = hexc(h)
	m.emission_enabled = true
	m.emission = hexc(emis)
	m.emission_energy_multiplier = energy
	return m


func box_at(parent, size, mat, pos):
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# caixa de altura 1 ao longo de Y, pra ser esticada entre dois pontos
func seg_new(parent, thick, mat):
	return box_at(parent, Vector3(thick, 1.0, thick), mat, Vector3.ZERO)


func place_seg(node, a, b):
	var d = b - a
	var ln = max(d.length(), 0.0001)
	node.position = a + d * 0.5
	node.basis = Basis(Quaternion(Vector3.UP, d / ln)) * Basis.from_scale(Vector3(1.0, ln, 1.0))


func seg_between(parent, a, b, thick, mat):
	var n = seg_new(parent, thick, mat)
	place_seg(n, a, b)
	return n


func approach(x, target, amount):
	return min(target, x + amount) if x < target else max(target, x - amount)


func smooth(t):
	return t * t * (3.0 - 2.0 * t)


func ang_wrap(a):
	return wrapf(a, -PI, PI)


func key(k):
	return Input.is_physical_key_pressed(k)


# cinemática inversa de dois ossos: devolve a posição da junta do meio
func ik2(root, target, l1, l2, hint):
	var d = target - root
	var ln = clamp(d.length(), 0.001, (l1 + l2) * 0.999)
	d = d.normalized()
	var x = (l1 * l1 - l2 * l2 + ln * ln) / (2.0 * ln)
	var hgt = sqrt(max(0.0, l1 * l1 - x * x))
	var hh = hint - d * hint.dot(d)
	if hh.length_squared() < 0.000001:
		hh = Vector3(0, 0, 1)
	hh = hh.normalized()
	return root + d * x + hh * hgt


# ============================== MONTAGEM ==============================
func _ready():
	randomize()
	m_metal = make_mat(0x55543a, 0.8, 0.35)
	m_dark = make_mat(0x2d2c23, 0.85, 0.35)
	m_rust = make_mat(0x6a3e26, 0.95, 0.2)
	m_hose = make_mat(0x161512, 0.9, 0.0)
	m_hazard = make_mat(0x8f7a2c, 0.85, 0.25)
	m_plate = make_mat(0x8a8a78, 0.85, 0.3)
	if ResourceLoader.exists("res://assets/texturas/chapa.jpg"):
		m_plate.albedo_texture = load("res://assets/texturas/chapa.jpg")
		m_plate.albedo_color = hexc(0xb8b8a8)
		m_plate.uv1_triplanar = true
		m_plate.uv1_scale = Vector3(0.476, 0.476, 0.476)
	snd = AudioKit.new()
	add_child(snd)
	lowpass = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 18000.0
	AudioServer.add_bus_effect(0, lowpass)
	# estado de fundo do menu: mech parado e ligado
	S = State.new()
	quick_start(S)
	S.P = 160.0
	S.rpm = 0.4
	load_models()
	build_world()
	build_mech()
	build_cockpit()
	build_switch_panel()
	build_controls()
	build_fx()
	build_ui()
	update_legs(0.0)
	update_punch(0.0)
	apply_camera()


func build_world():
	var env = Environment.new()
	var fogc = hexc(0x8f7558)
	env.background_mode = Environment.BG_COLOR
	env.background_color = fogc
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = hexc(0xb89a78)
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_light_color = fogc
	env.fog_density = 0.0045
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun = DirectionalLight3D.new()
	sun.light_color = hexc(0xffd2a0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)
	sun.look_at_from_position(Vector3(-300, 220, -180), Vector3.ZERO, Vector3.UP)
	# chão com textura de terra rachada gerada em código
	var img = Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in range(256):
		for x in range(256):
			var v = randf_range(-0.12, 0.12)
			img.set_pixel(x, y, Color(0.42 + v, 0.33 + v, 0.24 + v))
	for i in range(14):
		var px = randi_range(0, 255)
		var py = randi_range(0, 255)
		for k in range(160):
			px = posmod(px + randi_range(-1, 1), 256)
			py = posmod(py + randi_range(-1, 1), 256)
			img.set_pixel(px, py, Color(0.2, 0.15, 0.1))
	img.generate_mipmaps()
	var gm = StandardMaterial3D.new()
	gm.albedo_texture = ImageTexture.create_from_image(img)
	gm.uv1_scale = Vector3(300, 300, 1)
	gm.roughness = 1.0
	var ground = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	ground.mesh = pm
	ground.material_override = gm
	add_child(ground)
	# pedras
	var rock_mesh = SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 7
	rock_mesh.rings = 4
	var rock_mat = make_mat(0x5c5040, 1.0, 0.0)
	for i in range(260):
		var r = randf_range(25.0, 900.0)
		var a = randf_range(0.0, TAU)
		var sc = pow(randf(), 2.2) * 7.0 + 0.8
		var mi = MeshInstance3D.new()
		mi.mesh = rock_mesh
		mi.material_override = rock_mat
		mi.position = Vector3(cos(a) * r, sc * 0.3, sin(a) * r)
		mi.rotation = Vector3(randf_range(0, 3), randf_range(0, 3), randf_range(0, 3))
		mi.scale = Vector3(sc * randf_range(0.8, 1.5), sc * randf_range(0.5, 1.0), sc * randf_range(0.8, 1.4))
		add_child(mi)
	# ruínas de concreto: referência de escala
	var conc = make_mat(0x7d766a, 1.0, 0.0)
	var dark = make_mat(0x3c3934, 1.0, 0.0)
	for i in range(46):
		var r = randf_range(90.0, 850.0)
		var a = randf_range(0.0, TAU)
		var sz = Vector3(randf_range(8, 26), randf_range(6, 34), randf_range(8, 22))
		var b = box_at(self, sz, conc if randf() < 0.7 else dark, Vector3(cos(a) * r, sz.y / 2.0 - randf_range(0, 3), sin(a) * r))
		b.rotation = Vector3(randf_range(-0.08, 0.08), randf_range(0, 3), randf_range(-0.12, 0.12))
	# torres de energia
	var steel = make_mat(0x2b2a27, 0.9, 0.3)
	for i in range(14):
		var g = Node3D.new()
		var th = 46.0
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var lg = box_at(g, Vector3(0.5, th, 0.5), steel, Vector3(c.x * 1.65, th / 2.0, c.y * 1.65))
			lg.rotation = Vector3(c.y * -0.075, 0, c.x * 0.075)
		for k in range(1, 6):
			box_at(g, Vector3(5.0 - k * 0.4, 0.35, 0.35), steel, Vector3(0, k * 8.0, 0))
		box_at(g, Vector3(18, 0.6, 0.6), steel, Vector3(0, th - 4.0, 0))
		var a = (i / 14.0) * TAU + randf_range(-0.1, 0.1)
		var r = randf_range(260.0, 420.0)
		g.position = Vector3(cos(a) * r, 0, sin(a) * r)
		g.rotation.y = randf_range(0, 3)
		add_child(g)


func build_mech():
	mech = Node3D.new()
	add_child(mech)
	box_at(mech, Vector3(9.5, 4.5, 6), m_metal, Vector3(0, 20, 0))
	box_at(mech, Vector3(5, 3.4, 6.4), m_rust, Vector3(0, 16.6, 0))
	torso = Node3D.new()
	torso.position = Vector3(0, 24, 0)
	mech.add_child(torso)
	box_at(torso, Vector3(13, 10, 12), m_metal, Vector3(0, 5, 3))
	cockpit = Node3D.new()
	cockpit.position = Vector3(0, 8, -4.2)
	torso.add_child(cockpit)
	head = Node3D.new()
	cockpit.add_child(head)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 2000.0
	head.add_child(cam)
	cam.current = true
	# pernas (em coordenadas do mundo)
	for side in [-1.0, 1.0]:
		var foot = Node3D.new()
		add_child(foot)
		box_at(foot, Vector3(5.2, 2, 7.5), m_metal, Vector3(0, 1, 0))
		box_at(foot, Vector3(5.4, 1.2, 1.4), m_hazard, Vector3(0, 0.6, -4))
		legs.append({
			"side": side, "thigh": seg_new(self, 2.8, m_metal), "shin": seg_new(self, 2.3, m_dark), "foot": foot,
			"x": side * 3.6, "z": -0.5, "yaw": 0.0, "y": 0.0, "stepping": false, "t": 0.0, "dur": 1.0,
			"sx": 0.0, "sz": 0.0, "syaw": 0.0, "tx": 0.0, "tz": 0.0, "tyaw": 0.0, "ix": 0.0, "iz": 0.0, "hx": 0.0, "hz": 0.0,
		})
	# joelheiras arredondadas
	# braços (em coordenadas da cabine)
	arm_r = make_arm(1.0)
	arm_l = make_arm(-1.0)
	# canhão de ombro
	box_at(cockpit, Vector3(1.1, 1.1, 7), m_dark, Vector3(5.5, 2.6, -2.5))
	box_at(cockpit, Vector3(1.8, 1.8, 3), m_metal, Vector3(5.5, 2.6, 0.5))


func make_arm(side):
	var a = {"side": side}
	a.shoulder = Vector3(side * 8.0, -1.5, 6.4)
	a.upper = seg_new(cockpit, 3.1, m_metal)
	a.fore = seg_new(cockpit, 2.7, m_dark)
	a.model = null
	box_at(cockpit, Vector3(5.4, 3.8, 6.2), m_hazard, Vector3(side * 8.5, -0.1, 6.4))   # ombreira
	a.rest = Vector3(side * 9.0, -16.3, 6.4)
	a.guard = Vector3(side * 6.2, -2.6, -7.8)
	a.pos = a.rest
	a.elbow = Vector3.ZERO
	a.hint = Vector3(side * 0.5, -1.0, 0.7)
	if models.has("braco"):
		var mi = MeshInstance3D.new()
		mi.mesh = models.braco
		cockpit.add_child(mi)
		a.model = mi
		a.fore.visible = false
	return a


func update_arm(a):
	a.elbow = ik2(a.shoulder, a.pos, 7.8, 7.8, a.hint)
	place_seg(a.upper, a.shoulder, a.elbow)
	if a.model != null:
		var d = (a.pos - a.elbow).normalized()
		a.model.position = a.elbow
		a.model.basis = Basis(Quaternion(Vector3(0, 0, 1), d)) * Basis.from_scale(Vector3(a.side, 1.0, 1.0))
	else:
		place_seg(a.fore, a.elbow, a.pos)


func build_cockpit():
	var F = m_dark
	var c = cockpit
	box_at(c, Vector3(6.4, 0.38, 0.45), F, Vector3(0, 1.55, -2.25))       # viga do teto
	box_at(c, Vector3(0.42, 4.6, 0.42), F, Vector3(-2.7, -0.4, -2.2))    # colunas
	box_at(c, Vector3(0.42, 4.6, 0.42), F, Vector3(2.7, -0.4, -2.2))
	box_at(c, Vector3(0.13, 2.9, 0.13), F, Vector3(-1.05, 0.12, -2.3))   # montantes
	box_at(c, Vector3(0.13, 2.9, 0.13), F, Vector3(1.05, 0.12, -2.3))
	box_at(c, Vector3(6.4, 0.26, 0.45), F, Vector3(0, -1.35, -2.3))      # peitoril
	box_at(c, Vector3(5.4, 0.09, 0.09), F, Vector3(0, 0.78, -2.3))       # travessa do vidro
	# nariz de vidro inclinado até os pés, com nervuras
	var top = -1.35
	var top_z = -2.3
	var bot_y = -2.9
	var bot_z = 0.5
	for x in [-1.05, 1.05]:
		seg_between(c, Vector3(x, top, top_z), Vector3(x, bot_y, bot_z), 0.12, F)
	for x in [-1.9, 1.9]:
		seg_between(c, Vector3(x, top, top_z), Vector3(x * 0.95, bot_y, bot_z), 0.08, F)
	for x in [-2.7, 2.7]:
		seg_between(c, Vector3(x, top, top_z), Vector3(x * 0.9, bot_y, bot_z), 0.32, F)
	for t in [0.33, 0.66]:
		box_at(c, Vector3(6, 0.1, 0.1), F, Vector3(0, lerp(top, bot_y, t), lerp(top_z, bot_z, t)))
	box_at(c, Vector3(6.2, 0.3, 0.6), F, Vector3(0, bot_y, bot_z + 0.2))
	# chapa rebitada: teto, paredes, consoles laterais e fundo
	box_at(c, Vector3(6.4, 0.1, 3.4), m_plate, Vector3(0, 1.9, -0.6))
	box_at(c, Vector3(0.12, 3.6, 3.4), m_plate, Vector3(-3.12, -1.3, -0.4))
	box_at(c, Vector3(0.12, 3.6, 3.4), m_plate, Vector3(3.12, -1.3, -0.4))
	box_at(c, Vector3(0.9, 0.9, 1.6), m_plate, Vector3(-2.45, -1.35, -0.55))
	box_at(c, Vector3(0.9, 0.9, 1.6), m_plate, Vector3(2.45, -1.35, -0.55))
	box_at(c, Vector3(6.4, 3.6, 0.12), m_plate, Vector3(0, 0.1, 1.25))
	# vidros laterais com montantes
	for sx in [-1.0, 1.0]:
		for z in [-1.55, -0.55, 0.45]:
			box_at(c, Vector3(0.14, 1.55, 0.14), F, Vector3(sx * 2.98, 1.0, z))
		box_at(c, Vector3(0.16, 0.14, 3.1), F, Vector3(sx * 2.98, 0.25, -0.55))
		box_at(c, Vector3(0.16, 0.16, 3.1), F, Vector3(sx * 2.98, 1.75, -0.55))
	# rebites na viga
	var rivet = SphereMesh.new()
	rivet.radius = 0.05
	rivet.height = 0.1
	rivet.radial_segments = 6
	rivet.rings = 3
	for i in range(22):
		var r = MeshInstance3D.new()
		r.mesh = rivet
		r.material_override = m_metal
		r.position = Vector3(-3.0 + i * 0.285, 1.55, -2.5)
		c.add_child(r)
	# mangueiras
	seg_between(c, Vector3(-2.5, 1.7, -2.0), Vector3(-2.55, -1.8, -1.2), 0.09, m_hose)
	seg_between(c, Vector3(2.45, 1.7, -2.0), Vector3(2.6, -1.9, -1.3), 0.11, m_hose)
	# marca fixa no peitoril: mostra pra onde o torso aponta
	box_at(c, Vector3(0.07, 0.16, 0.04), unlit(0xffb547), Vector3(0, -1.14, -2.27))
	# placas de aviso (atlas 2x2 gerado no Higgsfield)
	if ResourceLoader.exists("res://assets/texturas/placas.jpg"):
		var tex = load("res://assets/texturas/placas.jpg")
		placard3d(tex, 0, 0.42, Vector3(-3.05, 0.9, -1.0), PI / 2.0)
		placard3d(tex, 1, 0.36, Vector3(2.0, -1.12, -2.06), 0.0)
		placard3d(tex, 2, 0.34, Vector3(-2.0, 1.55, -2.02), 0.0)
		placard3d(tex, 3, 0.4, Vector3(3.05, 0.9, -1.0), -PI / 2.0)
	# luzes
	cabin_light = OmniLight3D.new()
	cabin_light.light_color = hexc(0xffa040)
	cabin_light.omni_range = 7.0
	cabin_light.position = Vector3(0, 1.2, -0.5)
	c.add_child(cabin_light)
	alarm_light = OmniLight3D.new()
	alarm_light.light_color = hexc(0xff2a10)
	alarm_light.omni_range = 9.0
	alarm_light.light_energy = 0.0
	alarm_light.position = Vector3(0, 1.4, -1.0)
	c.add_child(alarm_light)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = hexc(0xffc070)
	muzzle_light.omni_range = 40.0
	muzzle_light.light_energy = 0.0
	muzzle_light.position = Vector3(5.5, 2.6, -4.0)
	c.add_child(muzzle_light)
	# peças penduradas no teto: balançam com a inércia
	pendulum = Node3D.new()
	pendulum.position = Vector3(1.75, 1.36, -2.12)
	c.add_child(pendulum)
	box_at(pendulum, Vector3(0.018, 0.62, 0.018), m_hose, Vector3(0, -0.31, 0))
	box_at(pendulum, Vector3(0.15, 0.21, 0.02), m_rust, Vector3(0, -0.7, 0))
	pendulum2 = Node3D.new()
	pendulum2.position = Vector3(-1.9, 1.36, -2.12)
	c.add_child(pendulum2)
	box_at(pendulum2, Vector3(0.03, 0.9, 0.03), m_hose, Vector3(0, -0.45, 0))
	box_at(pendulum2, Vector3(0.09, 0.09, 0.09), m_metal, Vector3(0, -0.92, 0))
	# mira de aro presa ao capacete
	var sight = Node3D.new()
	sight.position = Vector3(0, 0, -0.5)
	cam.add_child(sight)
	var sm = unlit(0x14120f)
	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 0.0418
	tm.outer_radius = 0.0462
	tm.rings = 48
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = sm
	ring.rotation.x = PI / 2.0
	sight.add_child(ring)
	for w in [[0.026, 0.0013, -0.031, 0.0], [0.026, 0.0013, 0.031, 0.0], [0.0013, 0.026, 0.0, 0.031], [0.0013, 0.026, 0.0, -0.031], [0.004, 0.07, 0.0, 0.081]]:
		box_at(sight, Vector3(w[0], w[1], 0.001), sm, Vector3(w[2], w[3], 0))
	sight_lamp_mat = unlit(0x3a2a14)
	var bead = MeshInstance3D.new()
	var bm = SphereMesh.new()
	bm.radius = 0.0045
	bm.height = 0.009
	bead.mesh = bm
	bead.material_override = sight_lamp_mat
	bead.position = Vector3(0, 0.052, 0)
	sight.add_child(bead)
	# painéis de instrumentos
	panels.append(make_panel("left", Vector2i(1024, 512), Vector2(1.3, 0.65), Vector3(-1.12, -0.8, -1.72), Vector3(-0.5, 0.5, 0)))
	panels.append(make_panel("right", Vector2i(1024, 512), Vector2(1.3, 0.65), Vector3(1.12, -0.8, -1.72), Vector3(-0.5, -0.5, 0)))
	panels.append(make_panel("top", Vector2i(1024, 128), Vector2(3.3, 0.4125), Vector3(0, 1.12, -2.12), Vector3(0.38, 0, 0)))


func placard3d(tex, i, sz, pos, ry):
	var m = StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = hexc(0xcfc8b8)
	m.roughness = 0.7
	m.uv1_scale = Vector3(0.5, 0.5, 1.0)
	m.uv1_offset = Vector3((i % 2) * 0.5, (i / 2) * 0.5, 0.0)
	var mi = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(sz, sz)
	mi.mesh = qm
	mi.material_override = m
	mi.position = pos
	mi.rotation.y = ry
	cockpit.add_child(mi)


# placa física com um SubViewport desenhando os instrumentos
func make_panel(mode, px, size, pos, rot):
	var vp = SubViewport.new()
	vp.size = px
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var ctl = PanelDraw.new()
	ctl.game = self
	ctl.mode = mode
	ctl.size = Vector2(px.x, px.y)
	vp.add_child(ctl)
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	var grp = Node3D.new()
	grp.position = pos
	grp.rotation = rot
	cockpit.add_child(grp)
	var face = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = size
	face.mesh = qm
	face.material_override = m
	grp.add_child(face)
	box_at(grp, Vector3(size.x + 0.1, size.y + 0.1, 0.3), m_dark, Vector3(0, 0, -0.16))
	return {"mat": m, "grp": grp}


func build_switch_panel():
	var p = make_panel("start", Vector2i(1024, 548), Vector2(1.16, 0.62), Vector3(-1.62, -0.56, -0.82), Vector3(-0.42, 1.05, 0))
	p.mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	p.mat.roughness = 0.8
	var base_mesh = CylinderMesh.new()
	base_mesh.top_radius = 0.04
	base_mesh.bottom_radius = 0.045
	base_mesh.height = 0.03
	var lever_mesh = BoxMesh.new()
	lever_mesh.size = Vector3(0.026, 0.026, 0.13)
	var btn_mesh = CylinderMesh.new()
	btn_mesh.top_radius = 0.045
	btn_mesh.bottom_radius = 0.05
	btn_mesh.height = 0.05
	var lamp_mesh = SphereMesh.new()
	lamp_mesh.radius = 0.024
	lamp_mesh.height = 0.048
	for i in range(SWITCHES.size()):
		var sw = SWITCHES[i]
		var g = Node3D.new()
		g.position = Vector3((i - 3) * 0.145, 0.02, 0)
		p.grp.add_child(g)
		var base = MeshInstance3D.new()
		base.mesh = base_mesh
		base.material_override = m_metal
		base.rotation.x = PI / 2.0
		base.position.z = 0.015
		g.add_child(base)
		var is_btn = sw.kind == "button"
		sw.mat = make_mat(0x8a1a10 if is_btn else 0xb8b4a4, 0.4, 0.1 if is_btn else 0.7)
		sw.mat.emission_enabled = true
		sw.mat.emission = Color(0, 0, 0)
		sw.lever = Node3D.new()
		sw.lever.position.z = 0.02
		g.add_child(sw.lever)
		var lm = MeshInstance3D.new()
		lm.material_override = sw.mat
		if is_btn:
			lm.mesh = btn_mesh
			lm.rotation.x = PI / 2.0
			lm.position.z = 0.045
		else:
			lm.mesh = lever_mesh
			lm.position.z = 0.065
		sw.lever.add_child(lm)
		sw.lamp_mat = unlit(0x2a2620)
		var lamp = MeshInstance3D.new()
		lamp.mesh = lamp_mesh
		lamp.material_override = sw.lamp_mat
		lamp.position = Vector3(0, -0.165, 0.015)
		g.add_child(lamp)
		sw.cover = null
		if sw.kind == "guarded":   # tampa vermelha articulada por cima da chave do reator
			sw.cover = Node3D.new()
			sw.cover.position = Vector3(0, 0.085, 0.02)
			g.add_child(sw.cover)
			var cm = make_mat(0x9a1c12, 0.6, 0.2)
			cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cm.albedo_color.a = 0.9
			box_at(sw.cover, Vector3(0.11, 0.17, 0.1), cm, Vector3(0, -0.085, 0.05))
		sw.hit = Node3D.new()   # ponto de mira da chave
		sw.hit.position = Vector3(0, -0.02, 0.06)
		g.add_child(sw.hit)
		sw.anim = 0.0


func build_controls():
	# alavancas de energia no console da direita
	var quad = Node3D.new()
	quad.position = Vector3(1.9, -0.82, -1.0)
	quad.rotation = Vector3(-0.3, -1.02, 0)
	cockpit.add_child(quad)
	box_at(quad, Vector3(0.62, 0.2, 0.4), m_plate, Vector3.ZERO)
	box_at(quad, Vector3(0.5, 0.02, 0.3), m_dark, Vector3(0, 0.105, 0))
	var rod = CylinderMesh.new()
	rod.top_radius = 0.014
	rod.bottom_radius = 0.018
	rod.height = 0.38
	var knob = SphereMesh.new()
	knob.radius = 0.045
	knob.height = 0.075
	var knob_cols = [0x1b1a16, 0x1b1a16, 0x7a1810]
	for i in range(3):
		var pv = Node3D.new()
		pv.position = Vector3(-0.16 + i * 0.16, 0.1, 0)
		quad.add_child(pv)
		var r = MeshInstance3D.new()
		r.mesh = rod
		r.material_override = m_metal
		r.position.y = 0.19
		pv.add_child(r)
		var k = MeshInstance3D.new()
		k.mesh = knob
		k.material_override = make_mat(knob_cols[i], 0.6, 0.0)
		k.position.y = 0.39
		pv.add_child(k)
		q_levers.append(pv)
	# manches
	var srod = CylinderMesh.new()
	srod.top_radius = 0.018
	srod.bottom_radius = 0.022
	srod.height = 0.32
	var grip = CylinderMesh.new()
	grip.top_radius = 0.034
	grip.bottom_radius = 0.03
	grip.height = 0.15
	var boot = CylinderMesh.new()
	boot.top_radius = 0.04
	boot.bottom_radius = 0.09
	boot.height = 0.12
	for side in [-1.0, 1.0]:
		var base = Node3D.new()
		base.position = Vector3(side * 0.78, -1.55, -0.6)
		cockpit.add_child(base)
		box_at(base, Vector3(0.24, 0.08, 0.24), m_dark, Vector3.ZERO)
		var pv = Node3D.new()
		pv.position.y = 0.05
		base.add_child(pv)
		for part in [[boot, m_hose, 0.05], [srod, m_metal, 0.2], [grip, m_hose, 0.42]]:
			var mi = MeshInstance3D.new()
			mi.mesh = part[0]
			mi.material_override = part[1]
			mi.position.y = part[2]
			pv.add_child(mi)
		box_at(pv, Vector3(0.02, 0.04, 0.03), make_mat(0x8a1a10, 0.5, 0.0), Vector3(0, 0.44, -0.035))
		sticks.append(pv)


func build_fx():
	var grad = Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt = GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	for i in range(60):
		var sp = Sprite3D.new()
		sp.texture = gt
		sp.pixel_size = 1.0 / 64.0
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.visible = false
		add_child(sp)
		puffs.append({"s": sp, "life": 0.0, "maxl": 1.0, "grow": 1.0, "vy": 0.0, "col": Color(1, 1, 1)})
	var tmat = unlit(0xffd080)
	for i in range(16):
		var tr = seg_new(self, 0.09, tmat)
		tr.visible = false
		tracers.append({"n": tr, "life": 0.0})
	# poeira em suspensão em volta do mech
	dust = CPUParticles3D.new()
	dust.amount = 160
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(60, 22, 60)
	dust.gravity = Vector3.ZERO
	dust.direction = Vector3(1, 0, 0)
	dust.spread = 20.0
	dust.initial_velocity_min = 0.4
	dust.initial_velocity_max = 1.0
	var dq = QuadMesh.new()
	dq.size = Vector2(0.22, 0.22)
	var dm = unlit(0xd9c49e)
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color.a = 0.55
	dq.material = dm
	dust.mesh = dq
	add_child(dust)


func puff(pos, size, colhex, life = 1.2, vy = 2.0):
	puff_i = (puff_i + 1) % puffs.size()
	var p = puffs[puff_i]
	p.s.position = pos
	p.s.scale = Vector3.ONE * size
	p.col = hexc(colhex)
	p.s.modulate = Color(p.col.r, p.col.g, p.col.b, 0.55)
	p.s.visible = true
	p.life = life
	p.maxl = life
	p.grow = size * 1.6
	p.vy = vy


func tracer(a, b):
	tracer_i = (tracer_i + 1) % tracers.size()
	var t = tracers[tracer_i]
	place_seg(t.n, a, b)
	t.n.visible = true
	t.life = 0.07


func build_ui():
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	var grad = Gradient.new()
	grad.set_color(0, Color(0.47, 0.04, 0.0, 0.0))
	grad.set_color(1, Color(0.3, 0.0, 0.0, 0.9))
	var gt = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.1, 0.5)
	vignette = TextureRect.new()
	vignette.texture = gt
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	ui_layer.add_child(vignette)
	var dim = ColorRect.new()
	dim.name = "Menu"
	dim.color = Color(0.055, 0.047, 0.035, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var plate = PanelContainer.new()
	center.add_child(plate)
	var margin = MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	plate.add_child(margin)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)
	ui_title = Label.new()
	ui_title.add_theme_font_size_override("font_size", 56)
	ui_title.add_theme_color_override("font_color", hexc(0xffb547))
	vb.add_child(ui_title)
	ui_body = Label.new()
	ui_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_body.custom_minimum_size = Vector2(660, 0)
	vb.add_child(ui_body)
	ui_quick = CheckBox.new()
	ui_quick.text = "Pular a partida a frio"
	vb.add_child(ui_quick)
	ui_button = Button.new()
	ui_button.add_theme_font_size_override("font_size", 26)
	ui_button.pressed.connect(_on_button)
	vb.add_child(ui_button)
	show_menu("start")


const MENU_TEXT = "Protótipo 0.4 (Godot) · cockpit de mech de 40 m\n\nVocê está sozinho dentro de 40 metros de aço. Nada responde na hora: as pernas demoram pra embalar, o torso gira como torre de tanque e todo soco precisa de pressão hidráulica. Sobreviva a 5 ondas.\n\nW / S: acelerador das pernas      A / D: girar a base\nMouse: mira com a cabeça, o torso vem atrás com inércia\nSegurar clique esquerdo: pressurizar o braço. Soltar dispara o soco\nClique direito: bloquear      Q: guarda      Espaço: canhão de ombro\nSegurar 1 / 2 / 3: puxar energia pra pernas, braços ou arma\nShift + mouse: olhar pela cabine sem girar o torso\nF: acionar a chave que está na mira\nM: som      Esc: pausa\n\nO mech começa desligado. O painel de partida fica à sua esquerda: segure Shift e olhe pra ele. A luz âmbar mostra a próxima chave: bateria, combustível, partida da turbina, hidráulica, reator (abra a tampa antes) e travas das pernas."

var menu_mode = "start"


func show_menu(mode, extra = ""):
	menu_mode = mode
	ui_layer.get_node("Menu").visible = true
	ui_quick.visible = mode != "pause"
	if mode == "start":
		ui_title.text = "BORNTOMECH"
		ui_body.text = MENU_TEXT
		ui_button.text = "Ligar o mech"
	elif mode == "pause":
		ui_title.text = "PAUSA"
		ui_body.text = "Turbina em marcha lenta."
		ui_button.text = "Continuar"
	else:
		ui_title.text = "VITÓRIA" if mode == "win" else "MECH PERDIDO"
		ui_body.text = extra
		ui_button.text = "Religar"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_button():
	if menu_mode == "pause":
		ui_layer.get_node("Menu").visible = false
		S.phase = "play"
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		start_game()


func start_game():
	for n in enemy_nodes:
		if is_instance_valid(n):
			n.queue_free()
	enemy_nodes.clear()
	S = State.new()
	S.phase = "play"
	for L in legs:
		L.x = L.side * 3.6
		L.z = -0.5
		L.yaw = 0.0
		L.y = 0.0
		L.stepping = false
	ui_layer.get_node("Menu").visible = false
	if ui_quick.button_pressed:
		quick_start(S)
		show_msg("PARTIDA", "Turbina girando. Pressão subindo.", 3.5)
	else:
		show_msg("MECH DESLIGADO", "Segure Shift e olhe pro painel à esquerda. Mire na chave âmbar e aperte F.", 7.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func quick_start(st):
	for k in ["bat", "fuel", "hyd", "reactor", "guard", "locks"]:
		st.sw[k] = true
	st.lit = true
	st.reactor_on = true
	st.rpm = 0.42
	st.P = 150.0
	st.cold = false
	st.wave_state = "intro"


func show_msg(big, sub = "", dur = 3.0):
	S.msg_big = big
	S.msg_sub = sub
	S.msg_t = dur + 1.5
	snd.play("beep")


# ============================== ENTRADA ==============================
func _input(event):
	if S == null or S.phase != "play":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k = 0.0021
		if key(KEY_SHIFT):   # olhar solto: só a cabeça do piloto, o torso fica
			S.look_h = clamp(S.look_h - event.relative.x * k, -1.7, 1.7)
			S.look_p = clamp(S.look_p - event.relative.y * k, -1.1, 1.1)
		else:
			S.aim = clamp(S.aim - event.relative.x * k, -2.4, 2.4)
			S.p_target = clamp(S.p_target - event.relative.y * k, -1.5, 0.32)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse_l = event.pressed
			if event.pressed:
				start_charge()
			else:
				release_charge()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_r = event.pressed
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q:
				S.guard_manual = not S.guard_manual
			KEY_F:
				use_switch()
			KEY_M:
				muted = not muted
				AudioServer.set_bus_mute(0, muted)
			KEY_ESCAPE, KEY_P:
				S.phase = "pause"
				mouse_l = false
				mouse_r = false
				show_menu("pause")


# ============================== CHAVES ==============================
func step_done(id, st):
	match id:
		"bat":
			return st.sw.bat
		"fuel":
			return st.sw.fuel
		"start":
			return st.lit
		"hyd":
			return st.sw.hyd
		"reactor":
			return st.reactor_on
		"locks":
			return st.sw.locks
	return true


func next_step(st):
	for id in STEP_ORDER:
		if not step_done(id, st):
			return id
	return ""


func next_hint():
	var n = next_step(S)
	return ("Próximo: " + STEP_TEXT[n]) if n != "" else ""


func use_switch():
	if hovered_sw == null:
		return
	var sw = hovered_sw
	var W = S.sw
	var heavy = false
	match sw.id:
		"bat":
			W.bat = not W.bat
			show_msg("BATERIA LIGADA" if W.bat else "BATERIA DESLIGADA", next_hint() if (W.bat and S.cold) else "", 2.5)
		"fuel":
			W.fuel = not W.fuel
			show_msg("COMBUSTÍVEL ABERTO" if W.fuel else "COMBUSTÍVEL CORTADO", next_hint() if (W.fuel and S.cold) else "", 2.5)
		"start":
			sw.anim = 1.0
			heavy = true
			if S.lit:
				pass
			elif not W.bat:
				show_msg("SEM BATERIA", "Ligue a chave 1 primeiro", 2.5)
			elif not W.fuel:
				show_msg("SEM COMBUSTÍVEL", "Abra a chave 2 primeiro", 2.5)
			elif S.starter <= 0.0:
				S.starter = 3.5
				show_msg("PARTIDA", "Motor de arranque girando a turbina…", 3.0)
				snd.play("starter", 0.9)
		"hyd":
			W.hyd = not W.hyd
			var sub = ""
			if W.hyd and S.cold:
				sub = next_hint() if S.lit else "Sem turbina acesa a pressão não sobe"
			show_msg("BOMBA HIDRÁULICA LIGADA" if W.hyd else "BOMBA HIDRÁULICA DESLIGADA", sub, 2.5)
		"reactor":
			if not W.guard:
				W.guard = true
				heavy = true
				show_msg("TAMPA ABERTA", "Aperte F de novo pra ligar o reator", 2.5)
			elif W.reactor:
				W.reactor = false
				S.reactor_on = false
				show_msg("REATOR DESLIGADO", "Esfriando. Braços e canhão sem força total.", 2.5)
			elif S.scram > 0.0:
				show_msg("REATOR TRAVADO", "Esfriando: %d s" % int(ceil(S.scram)), 1.5)
			elif not W.bat and not S.lit:
				show_msg("SEM ENERGIA", "O reator precisa da bateria pra partir", 2.5)
			else:
				W.reactor = true
				S.reactor_on = true
				heavy = true
				show_msg("REATOR ONLINE", next_hint() if S.cold else "", 2.5)
		"locks":
			W.locks = not W.locks
			heavy = true
			show_msg("TRAVAS SOLTAS" if W.locks else "PERNAS TRAVADAS", "", 2.0)
		"light":
			W.light = not W.light
	snd.play("click", 1.0, 0.7 if heavy else 1.2)


func update_cockpit_props(dt):
	# chave mais perto do centro da mira
	var o = cam.global_position
	var d = -cam.global_transform.basis.z
	hovered_sw = null
	var best = 0.075
	for sw in SWITCHES:
		var rel = sw.hit.global_position - o
		var along = rel.dot(d)
		if along < 0.2 or along > 3.4:
			continue
		var off = (rel - d * along).length()
		if off < best:
			best = off
			hovered_sw = sw
	if S.cold and next_step(S) == "":
		S.cold = false
		S.wave_state = "intro"
		S.wave_t = 5.0
		show_msg("MECH PRONTO", "Contatos se aproximando. Boa sorte, piloto.", 3.5)
	var nxt = next_step(S) if S.cold else ""
	var blink = sin(S.time * 6.0) > 0
	for sw in SWITCHES:
		var on = false
		if sw.id == "start":
			on = S.lit or S.starter > 0.0
		else:
			on = S.sw[sw.id]
		if sw.kind == "button":
			sw.anim = max(0.0, sw.anim - dt * 5.0)
			sw.lever.position.z = 0.02 - sw.anim * 0.03
		else:
			sw.lever.rotation.x = lerp(sw.lever.rotation.x, -0.55 if on else 0.55, 1.0 - exp(-30.0 * dt))
		if sw.cover != null:
			sw.cover.rotation.x = lerp(sw.cover.rotation.x, -1.9 if S.sw.guard else 0.0, 1.0 - exp(-10.0 * dt))
		sw.mat.emission = hexc(0x6a5a30) if sw == hovered_sw else Color(0, 0, 0)
		var col = 0x2a2620
		if sw.id == "reactor" and S.scram > 0.0:
			col = 0xff2a10 if blink else 0x3a0a04
		elif sw.id == "start" and S.starter > 0.0:
			col = 0xffb547 if blink else 0x4a3412
		elif sw.id == nxt:
			col = 0xffb547 if blink else 0x4a3412
		elif on:
			col = 0x6dff5a if (S.sw.bat or S.reactor_on or sw.id == "bat") else 0x1a3a14
		sw.lamp_mat.albedo_color = hexc(col)
	# alavancas de energia e manches acompanham os comandos
	var vals = [S.E.legs, S.E.arms, S.E.gun]
	for i in range(3):
		q_levers[i].rotation.x = lerp(q_levers[i].rotation.x, 0.7 - vals[i] * 1.4, 1.0 - exp(-12.0 * dt))
	var fw = (1.0 if key(KEY_W) else 0.0) - (1.0 if key(KEY_S) else 0.0)
	var tr = (1.0 if key(KEY_A) else 0.0) - (1.0 if key(KEY_D) else 0.0)
	var kk = 1.0 - exp(-10.0 * dt)
	sticks[0].rotation.x = lerp(sticks[0].rotation.x, -fw * 0.35, kk)
	sticks[0].rotation.z = lerp(sticks[0].rotation.z, tr * 0.25, kk)
	sticks[1].rotation.x = lerp(sticks[1].rotation.x, (-0.25 if mouse_l else 0.0) + (0.2 if mouse_r else 0.0), kk)


# ============================== MODELOS ==============================
func find_mesh(n):
	if n is MeshInstance3D and n.mesh != null:
		return n
	for c in n.get_children():
		var r = find_mesh(c)
		if r != null:
			return r
	return null


# tira a malha do GLB importado, já com a transformação do nó aplicada
func extract_model(nm, metal):
	var path = "res://assets/modelos/" + nm + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res == null or not (res is PackedScene):
		return null
	var root = res.instantiate()
	var mi = find_mesh(root)
	if mi == null:
		root.free()
		return null
	var xf = Transform3D.IDENTITY
	var n = mi
	while n != null and n is Node3D:
		xf = n.transform * xf
		n = n.get_parent()
	var arr = mi.mesh.surface_get_arrays(0)
	var src = arr[Mesh.ARRAY_VERTEX]
	var uv = arr[Mesh.ARRAY_TEX_UV]
	var idx = arr[Mesh.ARRAY_INDEX]
	if src == null or src.size() == 0:
		root.free()
		return null
	var v = PackedVector3Array()
	v.resize(src.size())
	var box = AABB(xf * src[0], Vector3.ZERO)
	for i in range(src.size()):
		var p = xf * src[i]
		v[i] = p
		box = box.expand(p)
	if idx == null or idx.size() == 0:
		idx = range(src.size())
	if uv == null:
		uv = PackedVector2Array()
	var mat = mi.mesh.surface_get_material(0)
	if mat == null:
		mat = make_mat(0x77705f, 0.85, metal)
	else:
		mat = mat.duplicate()
		if mat is BaseMaterial3D:
			mat.roughness = 0.85
			mat.metallic = metal
	root.free()
	return {"v": v, "uv": uv, "idx": idx, "mat": mat, "lo": box.position, "hi": box.end}


# monta uma malha nova só com os triângulos pedidos, transformada, com normais suaves
func build_mesh(verts, uvs, idx, xf, mat):
	if idx.size() < 3:
		return null
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var remap = {}
	var count = 0
	var has_uv = uvs.size() == verts.size()
	for i in idx:
		if not remap.has(i):
			remap[i] = count
			count += 1
			if has_uv:
				st.set_uv(uvs[i])
			st.add_vertex(xf * verts[i])
	for i in idx:
		st.add_index(remap[i])
	st.generate_normals()
	if mat != null:
		st.set_material(mat)
	return st.commit()


func prep_colossus(m):
	var lo = m.lo
	var hi = m.hi
	var cx = (lo.x + hi.x) / 2.0
	var cz = (lo.z + hi.z) / 2.0
	var s = 27.0 / (hi.y - lo.y)
	var buckets = [[], [], [], [], []]
	var v = m.v
	var idx = m.idx
	# braços pendem por fora do corpo; pernas abaixo do quadril
	for k in range(0, idx.size() - 2, 3):
		var p = (v[idx[k]] + v[idx[k + 1]] + v[idx[k + 2]]) / 3.0
		var b = 0
		if (p.x < -0.19 or p.x > 0.17) and p.y > -0.46 and p.y < 0.22:
			b = 1 if p.x < 0.0 else 2
		elif p.y < -0.12:
			b = 3 if p.x < 0.0 else 4
		buckets[b].append(idx[k])
		buckets[b].append(idx[k + 1])
		buckets[b].append(idx[k + 2])
	var xf = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(-cx, -lo.y, -cz) * s)
	var parts = []
	for b in buckets:
		parts.append(build_mesh(v, m.uv, b, xf, null))
	return {
		"mat": m.mat, "torso": parts[0], "armL": parts[1], "armR": parts[2], "legL": parts[3], "legR": parts[4],
		"hipY": (-0.12 - lo.y) * s, "hipX": (0.15 - cx) * s, "waistY": (0.0 - lo.y) * s,
		"shY": (0.2 - lo.y) * s, "shX": (0.25 - cx) * s, "chestY": (0.13 - lo.y) * s, "chestZ": 0.15 * s,
		"headY": (0.36 - lo.y) * s, "headZ": 0.2 * s,
	}


func prep_simple(m, size, axis):
	var lo = m.lo
	var hi = m.hi
	var s = size / (hi[axis] - lo[axis])
	var xf = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(-(lo.x + hi.x) / 2.0, -lo.y, -(lo.z + hi.z) / 2.0) * s)
	return build_mesh(m.v, m.uv, m.idx, xf, m.mat)


func prep_arm(m):
	# antebraço + punho: começa no cotovelo (z = 0) e o punho fica no +z
	var lo = m.lo
	var hi = m.hi
	var s = 10.1 / (hi.z - lo.z)
	var w = s * 0.8
	var xf = Transform3D(Basis.from_scale(Vector3(w, w, s)), Vector3(-(lo.x + hi.x) / 2.0 * w, -(lo.y + hi.y) / 2.0 * w, -lo.z * s))
	if m.mat is BaseMaterial3D:
		m.mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # o braço esquerdo é o direito espelhado
	return build_mesh(m.v, m.uv, m.idx, xf, m.mat)


func load_models():
	var c = extract_model("colosso", 0.0)
	if c != null:
		models["colosso"] = prep_colossus(c)
	var r = extract_model("rastejante", 0.0)
	if r != null:
		var rm = prep_simple(r, 5.5, 2)
		if rm != null:
			models["rastejante"] = rm
	var a = extract_model("braco", 0.3)
	if a != null:
		var am = prep_arm(a)
		if am != null:
			models["braco"] = am


# ============================== INIMIGOS ==============================
func pivot_part(parent, x, y, mesh, mat, off):
	var p = Node3D.new()
	p.position = Vector3(x, y, 0)
	parent.add_child(p)
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(-x - off.x, -y - off.y, 0)
	p.add_child(mi)
	return p


func make_colossus():
	var glow = glow_mat(0x1a0700, 0xff5a14, 0.15)
	var eye = glow_mat(0x220800, 0xffa040, 1.5)
	var g = Node3D.new()
	var body = Node3D.new()
	g.add_child(body)
	var skin
	var upper
	var leg_l
	var leg_r
	var a_l
	var a_r
	if models.has("colosso"):
		var C = models.colosso
		skin = C.mat.duplicate()
		if skin is BaseMaterial3D:
			skin.emission_enabled = true
			skin.emission = Color(0, 0, 0)
		leg_l = pivot_part(body, -C.hipX, C.hipY, C.legL, skin, Vector2.ZERO)
		leg_r = pivot_part(body, C.hipX, C.hipY, C.legR, skin, Vector2.ZERO)
		upper = pivot_part(body, 0.0, C.waistY, C.torso, skin, Vector2.ZERO)
		var off = Vector2(0.0, C.waistY)
		a_l = pivot_part(upper, -C.shX, C.shY - C.waistY, C.armL, skin, off)
		a_r = pivot_part(upper, C.shX, C.shY - C.waistY, C.armR, skin, off)
		# fenda no peito que acende antes da investida, e olhos
		var crack = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 12
		sm.rings = 8
		crack.mesh = sm
		crack.material_override = glow
		crack.scale = Vector3(1.3, 1.9, 0.5)
		crack.position = Vector3(0, C.chestY - C.waistY, C.chestZ)
		upper.add_child(crack)
		for x in [-1.0, 1.0]:
			box_at(upper, Vector3(0.8, 0.4, 0.3), eye, Vector3(x * 0.9, C.headY - C.waistY, C.headZ))
	else:
		skin = make_mat(0x2f2924, 0.95, 0.0)
		skin.emission_enabled = true
		skin.emission = Color(0, 0, 0)
		var bone = make_mat(0x6f6554, 0.85, 0.0)
		box_at(body, Vector3(8, 4, 5), skin, Vector3(0, 12, 0))
		leg_l = Node3D.new()
		leg_l.position = Vector3(-3, 12, 0)
		body.add_child(leg_l)
		leg_r = Node3D.new()
		leg_r.position = Vector3(3, 12, 0)
		body.add_child(leg_r)
		for L in [leg_l, leg_r]:
			box_at(L, Vector3(3.4, 12, 3.8), skin, Vector3(0, -6, 0))
			box_at(L, Vector3(4.2, 1.6, 6.5), bone, Vector3(0, -11.6, 1))
		upper = Node3D.new()
		upper.position = Vector3(0, 14, 0)
		body.add_child(upper)
		box_at(upper, Vector3(11, 10, 7), skin, Vector3(0, 5.5, 0.5))
		box_at(upper, Vector3(12.5, 1.6, 8), bone, Vector3(0, 10.6, 0.3))
		box_at(upper, Vector3(4, 2.2, 8.4), bone, Vector3(-5.5, 9.4, 0.3))
		box_at(upper, Vector3(4, 2.2, 8.4), bone, Vector3(5.5, 9.4, 0.3))
		box_at(upper, Vector3(5, 4, 0.7), glow, Vector3(0, 5, 4.1))
		box_at(upper, Vector3(4.2, 3.5, 5), skin, Vector3(0, 12.6, 2.6))
		box_at(upper, Vector3(0.9, 0.45, 0.2), eye, Vector3(-1.1, 13, 5.15))
		box_at(upper, Vector3(0.9, 0.45, 0.2), eye, Vector3(1.1, 13, 5.15))
		a_l = Node3D.new()
		a_l.position = Vector3(-7.2, 9.5, 0)
		upper.add_child(a_l)
		a_r = Node3D.new()
		a_r.position = Vector3(7.2, 9.5, 0)
		upper.add_child(a_r)
		for A in [a_l, a_r]:
			box_at(A, Vector3(3, 15, 3.2), skin, Vector3(0, -7.5, 0))
			box_at(A, Vector3(4.4, 4.4, 4.4), bone, Vector3(0, -16, 0))
	g.scale = Vector3(1.4, 1.4, 1.4)
	add_child(g)
	enemy_nodes.append(g)
	return {"g": g, "body": body, "upper": upper, "legL": leg_l, "legR": leg_r, "armL": a_l, "armR": a_r, "hide": skin, "glow": glow, "eye": eye}


var crawler_mat = null
var crawler_eye = null


func make_crawler():
	var g = Node3D.new()
	var body = null
	var legs_c = []
	if models.has("rastejante"):
		body = Node3D.new()
		g.add_child(body)
		var mi = MeshInstance3D.new()
		mi.mesh = models.rastejante
		body.add_child(mi)
	else:
		if crawler_mat == null:
			crawler_mat = make_mat(0x241f1b, 0.9, 0.0)
			crawler_eye = glow_mat(0x200500, 0xff6a20, 2.0)
		var b = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 7
		b.mesh = sm
		b.material_override = crawler_mat
		b.scale = Vector3(1.5, 0.85, 2.1)
		b.position.y = 1.0
		g.add_child(b)
		for x in [-0.5, 0.5]:
			box_at(g, Vector3(0.3, 0.2, 0.1), crawler_eye, Vector3(x, 1.3, 2.0))
		for i in range(6):
			var side = -1.0 if i < 3 else 1.0
			var l = box_at(g, Vector3(0.25, 0.25, 2.2), crawler_mat, Vector3(side * 1.7, 0.5, ((i % 3) - 1) * 1.2))
			l.rotation.y = side * (PI / 2.0 - 0.3)
			legs_c.append(l)
	add_child(g)
	enemy_nodes.append(g)
	return {"g": g, "body": body, "legsC": legs_c}


func spawn_colossus():
	var a = randf_range(0.0, TAU)
	var r = 270.0
	var col = {
		"m": make_colossus(), "x": S.pos.x + cos(a) * r, "z": S.pos.y + sin(a) * r, "yaw": 0.0, "hp": 280.0,
		"state": "approach", "t": 0.0, "cd": 3.0, "phase": 0.0, "flash": 0.0, "kx": 0.0, "kz": 0.0,
		"dirX": 0.0, "dirZ": 0.0, "travel": 0.0, "maxTravel": 0.0, "hit": false, "crouch": 0.0, "armRaise": 0.0,
		"glow": 0.15, "dead": 0.0, "lastStep": 0, "fell": false,
	}
	col.yaw = atan2(S.pos.x - col.x, S.pos.y - col.z)
	col.m.g.position = Vector3(col.x, 0, col.z)
	S.colossi.append(col)
	show_msg("COLOSSO", "Contato no radar", 2.5)
	snd.play("roar", 0.35)


func spawn_crawler_group(n):
	var a = randf_range(0.0, TAU)
	for i in range(n):
		var r = randf_range(210.0, 250.0)
		var aa = a + randf_range(-0.15, 0.15)
		var cr = {
			"m": make_crawler(), "x": S.pos.x + cos(aa) * r, "z": S.pos.y + sin(aa) * r, "y": 0.0, "hp": 10.0,
			"state": "run", "foot": null, "ox": 0.0, "oz": 0.0, "ph": randf_range(0.0, 6.0), "speed": randf_range(9.0, 12.0),
			"dead": false, "stun": 0.0,
		}
		cr.m.g.position = Vector3(cr.x, 0, cr.z)
		S.crawlers.append(cr)


# ============================== COMBATE ==============================
func hyp(a, b):
	return sqrt(a * a + b * b)


func pf():
	return clamp(S.P / 120.0, 0.12, 1.0)


# ângulo do alvo relativo à frente do torso
func angle_to(x, z):
	return ang_wrap(atan2(-(x - S.pos.x), -(z - S.pos.y)) - (S.yaw + S.t))


func start_charge():
	if S.punch_s != "idle" or S.sec.armR <= 0.0:
		return
	S.punch_s = "charge"
	S.punch_c = 0.0


func release_charge():
	if S.punch_s != "charge":
		return
	if S.punch_c < 0.08:
		S.punch_s = "idle"
		return
	S.punch_s = "windup"
	S.punch_t = 0.25 + 0.45 * S.punch_c
	S.punch_crel = S.punch_c * (0.45 + 0.55 * pf())
	snd.play("hiss", 0.6 + S.punch_c)
	# preparo: ombro direito vai pra trás, peso no pé de trás, cabeça acompanha
	S.t_vel -= 0.25 + 0.35 * S.punch_c
	S.sway_v += 0.3 * S.punch_c
	S.hc_v += 0.2 * S.punch_c


func punch_impact():
	var c = S.punch_crel
	var dmg = (25.0 + 110.0 * pow(c, 1.4)) * (0.4 + 0.6 * S.sec.armR / 100.0)
	var hit = false
	for col in S.colossi:
		if col.state == "dead":
			continue
		var d = max(hyp(col.x - S.pos.x, col.z - S.pos.y), 0.001)
		if d < 48.0 and abs(angle_to(col.x, col.z)) < 30.0 * DEG:
			var mult = 1.0
			var label = ""
			if col.state == "charge":
				mult = 2.2
				label = "CONTRA-GOLPE"
				col.state = "stagger"
				col.t = 3.2
			elif col.state == "recover":
				mult = 1.5
			elif c > 0.6:
				col.state = "stagger"
				col.t = 1.6
			col.hp -= dmg * mult
			col.flash = 1.0
			hit = true
			var kx = (col.x - S.pos.x) / d
			var kz = (col.z - S.pos.y) / d
			col.kx = kx * (8.0 + 18.0 * c)
			col.kz = kz * (8.0 + 18.0 * c)
			if label != "":
				show_msg(label, "", 1.6)
			puff(Vector3(col.x - kx * 8.0, 26, col.z - kz * 8.0), 12.0, 0x9a8c74, 1.2, 3.0)
	for cr in S.crawlers:
		if cr.dead or cr.state == "latched":
			continue
		var d = hyp(cr.x - S.pos.x, cr.z - S.pos.y)
		if d < 36.0 and abs(angle_to(cr.x, cr.z)) < 32.0 * DEG:
			kill_crawler(cr)
			hit = true
	snd.play("impact", 1.0 if hit else 0.45)
	return hit


func hit_mech(src_x, src_z, dmg):
	var a = angle_to(src_x, src_z)
	var blocked = S.block > 0.85 and abs(a) < 55.0 * DEG and S.P > 25.0 and S.sec.armL > 0.0
	var dx = S.pos.x - src_x
	var dz = S.pos.y - src_z
	var d = max(hyp(dx, dz), 0.001)
	if blocked:
		S.sec.armL = max(0.0, S.sec.armL - dmg * 0.3)
		S.P = max(0.0, S.P - 50.0)
		S.shake = max(S.shake, 0.8)
		S.neural = min(1.0, S.neural + 0.35)
		S.push = Vector2(dx / d * 4.0, dz / d * 4.0)
		snd.play("clank", 1.6)
		snd.play("hiss", 1.0)
		show_msg("BLOQUEADO", "Pressão caiu", 1.2)
	else:
		S.sec.cockpit = max(0.0, S.sec.cockpit - dmg * 0.55)
		var other = "armR" if randf() < 0.5 else "legs"
		S.sec[other] = max(0.0, S.sec[other] - dmg * 0.6)
		S.shake = max(S.shake, 1.6)
		S.neural = 1.0
		S.push = Vector2(dx / d * 10.0, dz / d * 10.0)
		S.t_vel += randf_range(-0.9, 0.9)
		snd.play("impact", 1.3)
		snd.play("creak", 1.2)


func kill_crawler(cr):
	if cr.dead:
		return
	cr.dead = true
	S.kills_crawlers += 1
	puff(Vector3(cr.x, 1.5, cr.z), 4.0, 0x3a2a20, 1.0, 1.5)
	cr.m.g.visible = false


# distância ao longo do raio até uma esfera, ou -1
func ray_sphere(o, d, c, r):
	var oc = c - o
	var tca = oc.dot(d)
	if tca < 0.0:
		return -1.0
	var d2 = oc.length_squared() - tca * tca
	if d2 > r * r:
		return -1.0
	return tca - sqrt(r * r - d2)


func fire_gun(dt):
	S.gun_cd -= dt
	var can_fire = key(KEY_SPACE) and S.reactor_on and S.E.gun > 0.08
	S.firing = can_fire
	if not can_fire or S.gun_cd > 0.0:
		return
	S.gun_cd = 1.0 / (3.0 + 15.0 * S.E.gun)
	S.heat += 0.021
	var origin = cam.global_position
	var dir = -cam.global_transform.basis.z
	dir = (dir + Vector3(randf_range(-0.006, 0.006), randf_range(-0.006, 0.006), randf_range(-0.006, 0.006))).normalized()
	var best = 650.0
	var hit_obj = null
	var hit_type = ""
	for cr in S.crawlers:
		if cr.dead:
			continue
		var t = ray_sphere(origin, dir, Vector3(cr.x, cr.y + 1.0, cr.z), 3.4)
		if t > 0.0 and t < best:
			best = t
			hit_obj = cr
			hit_type = "c"
	for col in S.colossi:
		if col.state == "dead":
			continue
		for hs in [[27.0, 10.0], [38.0, 5.0], [11.0, 7.0]]:
			var t = ray_sphere(origin, dir, Vector3(col.x, hs[0], col.z), hs[1])
			if t > 0.0 and t < best:
				best = t
				hit_obj = col
				hit_type = "k"
	if hit_obj == null and dir.y < 0.0:
		var t = -origin.y / dir.y
		if t < best:
			best = t
			hit_type = "g"
	var end = origin + dir * best
	tracer(cockpit.to_global(Vector3(5.5, 2.6, -6.2)), end)
	muzzle_light.light_energy = 6.0
	snd.play("gun", 1.0, randf_range(0.94, 1.06))
	if hit_type == "c":
		hit_obj.hp -= 6.0
		puff(end, 1.6, 0xffa050, 0.25, 0.0)
		if hit_obj.hp <= 0.0:
			kill_crawler(hit_obj)
	elif hit_type == "k":
		hit_obj.hp -= 1.2
		hit_obj.flash = max(hit_obj.flash, 0.3)
		puff(end, 2.2, 0xffa050, 0.25, 0.0)
	elif hit_type == "g":
		puff(Vector3(end.x, 0.5, end.z), 2.5, 0xb59a74, 0.8, 1.5)


# ============================== ONDAS ==============================
func update_waves(dt):
	if S.wave_state == "cold":   # espera a partida a frio
		return
	if S.wave_state == "intro" or S.wave_state == "break":
		S.wave_t -= dt
		if S.wave_t <= 0.0:
			var w = WAVES[S.wave]
			S.wave_state = "fight"
			S.to_spawn_crawlers = w.crawlers
			S.crawler_spawn_t = 1.5
			S.colossus_queue = w.colossi.duplicate()
			S.wave_clock = 0.0
			show_msg("ONDA %d" % (S.wave + 1), "Colosso a caminho. Fique de olho no peito dele." if w.colossi.size() > 0 else "Rastejantes. Pise ou atire olhando pra baixo.", 3.0)
		return
	S.wave_clock += dt
	S.crawler_spawn_t -= dt
	if S.to_spawn_crawlers > 0 and S.crawler_spawn_t <= 0.0:
		var n = min(S.to_spawn_crawlers, 3 + randi_range(0, 1))
		spawn_crawler_group(n)
		S.to_spawn_crawlers -= n
		S.crawler_spawn_t = randf_range(4.0, 7.0)
	var rest = []
	for tq in S.colossus_queue:
		if tq <= S.wave_clock:
			spawn_colossus()
		else:
			rest.append(tq)
	S.colossus_queue = rest
	var alive = false
	for cr in S.crawlers:
		if not cr.dead:
			alive = true
			break
	for col in S.colossi:
		if col.state != "dead":
			alive = true
			break
	if not alive and S.to_spawn_crawlers <= 0 and S.colossus_queue.size() == 0:
		S.wave += 1
		if S.wave >= WAVES.size():
			end_game(true)
			return
		S.wave_state = "break"
		S.wave_t = 8.0
		for k in ["cockpit", "legs", "armL", "armR"]:
			S.sec[k] = min(100.0, S.sec[k] + 15.0)
		show_msg("ONDA LIMPA", "Equipe de solo remendou um pouco a blindagem.", 4.0)


func end_game(win):
	S.phase = "end"
	mouse_l = false
	mouse_r = false
	var secs = int(S.time)
	var txt = ("As 5 ondas caíram. O mech continua de pé." if win else "A cabine não aguentou e a conexão neural caiu.")
	txt += "\n\nOndas: %d / 5\nColossos derrubados: %d\nRastejantes: %d\nTempo: %d:%02d" % [min(S.wave + (0 if win else 1), 5), S.kills_colossi, S.kills_crawlers, secs / 60, secs % 60]
	show_menu("win" if win else "lose", txt)


# ============================== SIMULAÇÃO ==============================
func update_systems(dt):
	# redistribuir energia elétrica segurando 1/2/3
	var E = S.E
	var pull = ""
	if key(KEY_1):
		pull = "legs"
	elif key(KEY_2):
		pull = "arms"
	elif key(KEY_3):
		pull = "gun"
	if pull != "":
		var take = min(0.45 * dt, 1.0 - E[pull])
		var avail = 0.0
		for k in ["legs", "arms", "gun"]:
			if k != pull:
				avail += E[k]
		if avail > 0.0001:
			for k in ["legs", "arms", "gun"]:
				if k != pull:
					E[k] -= take * (E[k] / avail)
			E[pull] += take
	# reator e calor
	if S.punch_s == "charge":
		S.heat += 0.03 * dt
	S.heat = max(0.0, S.heat - (0.1 if S.reactor_on else 0.22) * dt)
	if S.reactor_on and S.heat >= 1.0:
		S.reactor_on = false
		S.sw.reactor = false
		S.scram = 5.0
		show_msg("SCRAM", "Reator superaqueceu e desligou. Espere esfriar e religue.", 3.0)
		snd.play("clank", 1.5)
		snd.play("hiss", 1.4)
	if S.scram > 0.0:
		S.scram -= dt
		if S.scram <= 0.0:
			S.scram = 0.0
			show_msg("REATOR FRIO", "Pode religar a chave do reator (5)", 3.0)
	S.reactor_on = S.sw.reactor and S.scram <= 0.0
	# partida da turbina: o motor de arranque gira por alguns segundos, depois acende
	if S.starter > 0.0:
		S.starter -= dt
		if not S.sw.bat or not S.sw.fuel:
			S.starter = 0.0
			show_msg("PARTIDA ABORTADA", "Sem bateria" if not S.sw.bat else "Sem combustível", 2.0)
		elif S.starter <= 0.0:
			S.starter = 0.0
			S.lit = true
			show_msg("TURBINA ACESA", next_hint() if S.cold else "", 2.5)
			snd.play("hiss", 0.6)
			snd.play("clank", 0.4)
	if S.lit and not S.sw.fuel:
		S.lit = false
		show_msg("TURBINA APAGOU", "Combustível cortado", 2.5)
	# turbina: acelera quando a pressão cai
	var moving = abs(S.v) > 0.3 or abs(S.w) > 0.02
	var rpm_target = 0.42
	if not S.lit:
		rpm_target = 0.3 if S.starter > 0.0 else 0.0
	elif S.P < 170.0 or S.punch_s == "charge" or moving:
		rpm_target = 1.0
	S.rpm += (rpm_target - S.rpm) * min(1.0, dt / 1.6)
	# hidráulica
	var inflow = S.rpm * 62.0 if S.sw.hyd else 0.0
	var use = abs(S.v) * 1.7 + abs(S.w) * 14.0
	if S.punch_s == "charge":
		use += 32.0
	if S.block > 0.0 and mouse_r:
		use += 5.0
	var leak = ((100.0 - S.sec.legs) + (100.0 - S.sec.armR)) / 200.0 * 13.0
	S.P += (inflow - use - leak) * dt
	S.relief = 0.0
	if S.P > 205.0:
		S.relief = min(1.0, (S.P - 205.0) / 8.0 + 0.5)
		S.P = 205.0
	if S.punch_s == "charge" and S.punch_c >= 1.0:
		S.relief = max(S.relief, 0.8)
	S.P = max(0.0, S.P)


func update_motion(dt):
	var E = S.E
	var p = pf()
	var elec = 1.0 if S.reactor_on else 0.55
	var leg_f = (0.45 + 1.15 * E.legs) * (0.45 + 0.55 * S.sec.legs / 100.0) * elec
	var unlocked = 1.0 if S.sw.locks else 0.0   # com as travas das pernas presas o mech não anda
	var fwd_in = ((1.0 if key(KEY_W) else 0.0) - (1.0 if key(KEY_S) else 0.0)) * unlocked
	var turn_in = ((1.0 if key(KEY_A) else 0.0) - (1.0 if key(KEY_D) else 0.0)) * unlocked
	var v_t = 0.0
	if fwd_in > 0.0:
		v_t = 6.0 * leg_f * p   # perna de ~19 m: acima disso a passada vira corrida
	elif fwd_in < 0.0:
		v_t = -2.4 * leg_f * p
	S.v = approach(S.v, v_t, (1.05 if fwd_in != 0.0 else 0.75) * (0.4 + 0.6 * p) * dt)
	S.w = approach(S.w, turn_in * 0.3 * leg_f * p, (0.28 if turn_in != 0.0 else 0.36) * dt)
	S.yaw += S.w * clamp(S.gf * 1.1, 0.35, 1.3) * dt
	var fwd = Vector2(-sin(S.yaw), -cos(S.yaw))
	S.pos += fwd * (S.v * S.gf * dt) + S.push * dt
	S.push *= max(0.0, 1.0 - 2.2 * dt)
	if S.pos.length() > 900.0:
		S.pos = S.pos.normalized() * 900.0
	# torso: mola com motor limitado (passa do ponto e volta)
	var max_rate = (0.25 + 1.25 * E.arms) * (1.0 if S.reactor_on else 0.22) * (0.6 + 0.4 * p)
	if S.punch_s == "recover" or S.punch_s == "windup":
		max_rate *= 0.45
	var max_acc = max_rate * 1.7
	S.t_target = clamp(S.aim, -1.75, 1.75)   # o torso persegue pra onde o piloto olha
	var a = clamp(5.5 * (S.t_target - S.t) - 2.4 * S.t_vel, -max_acc, max_acc)
	var t_vel_prev = S.t_vel
	# no golpe o motor do torso libera mais giro: o corpo acompanha o braço
	max_rate *= 1.0 + 1.6 * S.commit
	S.t_vel = clamp(S.t_vel + a * dt, -max_rate, max_rate)
	S.t += S.t_vel * dt
	if S.t > 1.8:
		S.t = 1.8
		S.t_vel = min(0.0, S.t_vel)
	if S.t < -1.8:
		S.t = -1.8
		S.t_vel = max(0.0, S.t_vel)
	# cabeça: mais leve. Pescoço vai até 40 graus pra cada lado
	S.aim = clamp(S.aim, S.t - 0.7, S.t + 0.7)
	S.h = S.aim - S.t
	S.p = lerp(S.p, S.p_target, 1.0 - exp(-22.0 * dt))
	if not key(KEY_SHIFT):
		var kk = 1.0 - exp(-7.0 * dt)
		S.look_h = lerp(S.look_h, 0.0, kk)
		S.look_p = lerp(S.look_p, 0.0, kk)
	# inclinação pela inércia
	S.roll = lerp(S.roll, -S.w * 0.6 - S.t_vel * 0.025, min(1.0, dt * 3.0))
	# pescoço: quando o torso dá tranco a cabeça fica pra trás e depois acerta a mira
	var t_acc = (S.t_vel - t_vel_prev) / max(dt, 0.004)
	S.hc_v += (-70.0 * S.hc - 11.0 * S.hc_v - t_acc * 0.35) * dt
	S.hc = clamp(S.hc + S.hc_v * dt, -0.12, 0.12)
	S.hp_adjv += (-55.0 * S.hp_adj - 10.0 * S.hp_adjv) * dt
	S.hp_adj = clamp(S.hp_adj + S.hp_adjv * dt, -0.1, 0.1)
	# reação dos braços no corpo (rolagem)
	S.react_rollv += (-24.0 * S.react_roll - 8.0 * S.react_rollv) * dt
	S.react_roll = clamp(S.react_roll + S.react_rollv * dt, -0.08, 0.08)
	S.commit = max(0.0, S.commit - dt * 1.4)


func update_legs(dt):
	var p = pf()
	var fx = -sin(S.yaw)
	var fz = -cos(S.yaw)
	var rx = cos(S.yaw)
	var rz = -sin(S.yaw)
	var vf = clamp(abs(S.v) / 6.0, 0.0, 1.0)
	S.step_rest = max(0.0, S.step_rest - dt)
	S.stumble = max(0.0, S.stumble - dt)
	# ritmo de pêndulo: perna de ~19 m dá passo de 2,2 a 2,7 s
	var t_step = clamp(2.7 - abs(S.v) * 0.085, 2.2, 2.7) / (0.6 + 0.4 * p)
	var any_stepping = false
	var worst = null
	var worst_err = 0.0
	for L in legs:
		L.ix = S.pos.x + rx * L.side * 3.6 + fx * 0.5
		L.iz = S.pos.y + rz * L.side * 3.6 + fz * 0.5
		if L.stepping:
			any_stepping = true
			continue
		var err = hyp(L.ix - L.x, L.iz - L.z) + abs(ang_wrap(S.yaw - L.yaw)) * 6.0
		if S.last_leg != null and S.last_leg == L.side:
			err *= 0.35   # alterna as pernas
		if err > worst_err:
			worst_err = err
			worst = L
	var want_move = key(KEY_W) or key(KEY_S) or key(KEY_A) or key(KEY_D)
	# empurrão forte tira o peso de cima dos pés: passo de recuperação, sem esperar
	var pushed = S.push.length() > 2.5 and S.stumble <= 0.0
	var can_step = S.step_rest <= 0.0 or pushed
	if not any_stepping and can_step and worst != null and (worst_err > (0.3 if want_move else 1.1) or pushed):
		var L = worst
		L.stepping = true
		L.t = 0.0
		S.last_leg = L.side
		L.dur = t_step * 0.78   # 22% do ciclo com os dois pés no chão
		if pushed:
			L.dur = 1.1
			S.stumble = 1.6
		L.sx = L.x
		L.sz = L.z
		L.syaw = L.yaw
		var v_e = S.v
		if want_move and abs(S.v) > 0.05:
			v_e = sign(S.v) * max(abs(S.v), 1.5)
		# o pé pousa meio passo à frente de onde o quadril vai estar
		var reach = v_e * L.dur + v_e * t_step * 0.4
		L.tx = L.ix + fx * reach
		L.tz = L.iz + fz * reach
		if pushed:
			L.tx += S.push.x * 0.9
			L.tz += S.push.y * 0.9
		L.tyaw = S.yaw + S.w * L.dur
		S.P -= 3.0 + abs(S.v) * 0.8
		# antecipação: o quadril afunda um pouco antes de tirar o pé
		S.bob_v -= 0.5 + 0.5 * vf
		if dt > 0.0:
			snd.play("lift", 0.55 + 0.45 * vf, 1.2 / L.dur)
	var gf_t = 1.0
	var rise_t = 0.0
	# peso no pé de apoio: começa a passar logo que o outro pé pousa (antes de levantar)
	var sway_amp = 0.45 + 0.35 * vf
	var sway_t = (S.last_leg * sway_amp) if (S.last_leg != null and (want_move or any_stepping)) else 0.0
	var swing_side = 0.0
	for L in legs:
		if not L.stepping:
			L.y = 0.0
			continue
		L.t += dt / L.dur
		var t = min(1.0, L.t)
		# sobe devagar, vai pra frente, e no fim desce seco
		var s = smooth(min(1.0, t / 0.82))
		L.x = lerp(L.sx, L.tx, s)
		L.z = lerp(L.sz, L.tz, s)
		L.yaw = L.syaw + ang_wrap(L.tyaw - L.syaw) * s
		L.y = sin(PI * pow(t, 1.5)) * (1.8 + 1.4 * vf)
		gf_t = 1.0 - 0.07 * sin(PI * t)
		rise_t = (0.15 + 0.25 * vf) * sin(PI * t)   # pêndulo invertido: corpo sobe no meio do apoio
		sway_t = -L.side * sway_amp
		swing_side = L.side
		if t >= 1.0:
			L.stepping = false
			L.y = 0.0
			var vol = 0.6 + 0.4 * vf
			snd.play("step", vol)
			S.shake = max(S.shake, 0.3 + vol * 0.3)
			S.bob_v -= 1.6 + 2.4 * vf      # afunda devagar, sem quicar
			S.kick_v -= 2.0 + 2.5 * vf     # pancada seca na câmera
			S.pod_yv -= 1.0 + 1.4 * vf     # a cabine desce na suspensão
			S.nod_v -= 0.05 + 0.07 * vf
			S.fov_k += 0.6 + 0.8 * vf
			S.sway_v += L.side * (0.15 + 0.2 * vf)
			S.pend_fv += 0.8 + 1.6 * vf
			S.pend_lv += L.side * 0.6
			S.step_rest = t_step * 0.22 if want_move else 0.5
			puff(Vector3(L.x, 1, L.z), 8.0 + 4.0 * vf, 0xb59a74, 1.8 + vf, 1.2)
			puff(Vector3(L.x + rx * 3.0, 1, L.z + rz * 3.0), 5.0 + 3.0 * vf, 0xb59a74, 1.4, 1.0)
			puff(Vector3(L.x - rx * 3.0, 1, L.z - rz * 3.0), 5.0 + 3.0 * vf, 0xb59a74, 1.4, 1.0)
			for cr in S.crawlers:
				if cr.dead:
					continue
				if cr.state != "latched" and hyp(cr.x - L.x, cr.z - L.z) < 6.0:
					kill_crawler(cr)
				elif cr.state == "latched" and cr.foot != null and cr.foot.side == L.side and randf() < 0.3:
					cr.state = "run"
					cr.foot = null
					cr.stun = 1.2
					var a = randf_range(0.0, TAU)
					cr.x += cos(a) * 9.0
					cr.z += sin(a) * 9.0
	S.gf = lerp(S.gf, gf_t, min(1.0, dt * 4.0))
	S.rise = lerp(S.rise, rise_t, min(1.0, dt * 3.0))
	# molas quase criticamente amortecidas: massa grande não quica
	S.bob_v += (-14.0 * S.bob_y - 7.1 * S.bob_v) * dt
	S.bob_y += S.bob_v * dt
	S.nod_v += (-30.0 * S.nod - 9.9 * S.nod_v) * dt
	S.nod += S.nod_v * dt
	S.kick_v += (-140.0 * S.kick - 14.0 * S.kick_v) * dt
	S.kick += S.kick_v * dt
	var prev_sv = S.sway_v
	S.sway_v += (10.0 * (sway_t - S.sway) - 6.0 * S.sway_v) * dt
	S.sway += S.sway_v * dt
	S.arm_swing = lerp(S.arm_swing, -swing_side * (0.35 + 0.65 * vf), min(1.0, dt * 2.0))
	# aceleração real do corpo (passo + empurrão), no referencial do mech
	var vw = Vector2(fx, fz) * (S.v * S.gf) + S.push
	var idt = 1.0 / max(dt, 0.004)
	var acc = (vw - S.vw_prev) * idt
	S.vw_prev = vw
	var a_f = clamp(acc.dot(Vector2(fx, fz)), -9.0, 9.0)
	var a_side = clamp(acc.dot(Vector2(rx, rz)), -9.0, 9.0)
	S.v_inst = S.v * S.gf
	# torso atrasa na aceleração (inclina pra trás ao arrancar, pra frente ao frear)
	S.lean_fv += (-6.0 * S.lean_f - 3.4 * S.lean_fv + a_f * 0.12) * dt
	S.lean_f = clamp(S.lean_f + S.lean_fv * dt, -0.12, 0.12)
	# cabine pendurada na suspensão
	S.pod_zv += (-40.0 * S.pod_z - 8.0 * S.pod_zv + a_f * 0.35) * dt
	S.pod_z = clamp(S.pod_z + S.pod_zv * dt, -0.7, 0.7)
	S.pod_yv += (-40.0 * S.pod_y - 8.0 * S.pod_yv) * dt
	S.pod_y = clamp(S.pod_y + S.pod_yv * dt, -0.6, 0.6)
	# peças penduradas: reagem à aceleração da cabine
	var a_l = clamp((S.sway_v - prev_sv) * idt, -9.0, 9.0) + a_side + S.t_vel * 2.5 + S.w * 6.0
	S.pend_fv += (-13.0 * S.pend_f - 0.8 * S.pend_fv + a_f * 0.4) * dt
	S.pend_f = clamp(S.pend_f + S.pend_fv * dt, -1.1, 1.1)
	S.pend_lv += (-13.0 * S.pend_l - 0.8 * S.pend_lv + a_l * 0.4) * dt
	S.pend_l = clamp(S.pend_l + S.pend_lv * dt, -1.1, 1.1)
	# pernas humanoides: quadril em cima dos pés, joelho dobra pra frente.
	# o quadril inteiro (e o corpo junto) passa pro pé de apoio, sem deslizar o torso
	var max_h = 0.0
	for L in legs:
		L.hx = S.pos.x + rx * (L.side * 3.6 + S.sway)
		L.hz = S.pos.y + rz * (L.side * 3.6 + S.sway)
		if not L.stepping:
			max_h = max(max_h, hyp(L.x - L.hx, L.z - L.hz))
	# perna esticada limita a altura do quadril
	var cap = sqrt(max(1.0, (2.0 * LEG - 0.15) * (2.0 * LEG - 0.15) - max_h * max_h)) + ANK
	S.body_y = lerp(S.body_y, min(HIP + S.bob_y + S.rise, cap) - HIP, min(1.0, dt * 8.0))
	var hint = Vector3(fx, 0.1, fz)
	for L in legs:
		var hip = Vector3(L.hx, HIP + S.body_y, L.hz)
		var ank = Vector3(L.x, L.y + ANK, L.z)
		var knee = ik2(hip, ank, LEG, LEG, hint)
		place_seg(L.thigh, hip, knee)
		place_seg(L.shin, knee, ank)
		L.foot.position = Vector3(L.x, L.y, L.z)
		L.foot.rotation.y = L.yaw


func update_punch(dt):
	var p = pf()
	var elec = 1.0 if S.reactor_on else 0.4
	var a = arm_r
	var b = arm_l
	if S.punch_s == "charge":
		S.punch_c = min(1.0, S.punch_c + (0.32 + 1.0 * S.E.arms) * p * elec * dt)
		if not mouse_l:
			release_charge()
	elif S.punch_s == "windup":
		S.punch_t -= dt
		if S.punch_t <= 0.0:
			start_strike(a)
	elif S.punch_s == "strike":
		S.punch_t -= dt
		# o golpe resolve quando o punho chega no alvo (ou começa a voltar), não por relógio fixo
		var to_t = S.punch_tgt - a.pos
		var reached = to_t.length() < 1.6 or (S.arm_vel.dot(to_t) < 0.0 and S.punch_t < 0.5)
		if reached or S.punch_t <= 0.0:
			resolve_punch(a)
	elif S.punch_s == "recover":
		S.punch_t -= dt
		if S.punch_t <= 0.0:
			S.punch_s = "idle"
			S.punch_c = 0.0
	# postura: braços soltos andando, guarda alta quando tem ameaça perto ou o piloto pede
	var near = false
	for col in S.colossi:
		if col.state != "dead" and hyp(col.x - S.pos.x, col.z - S.pos.y) < 150.0:
			near = true
	if near or S.punch_s != "idle" or mouse_r:
		S.guard_hold = 2.5
	else:
		S.guard_hold = max(0.0, S.guard_hold - dt)
	var want_guard = S.guard_manual or S.guard_hold > 0.0
	S.guard = approach(S.guard, 1.0 if want_guard else 0.0, (1.0 if want_guard else 0.55) * (0.4 + 0.6 * p) * dt)
	var gs = smooth(S.guard)
	var swing = S.arm_swing * (1.0 - gs) * 3.4
	var pk = 0.5 + 0.5 * p
	# braço direito: massa na ponta de um pistão. Mola + amortecedor + força máxima da hidráulica
	var tgt = a.rest.lerp(a.guard, gs)
	tgt.z -= swing
	var c = S.punch_c
	var cocked = Vector3(9.5, -2.0 - 1.2 * c, 3.0 + 2.2 * c)   # quanto mais carga, mais pra trás
	var k = 45.0
	var zeta = 0.85
	var fmax = 160.0
	if S.punch_s == "charge":
		tgt = tgt.lerp(cocked, smooth(min(1.0, c * 1.5)))
		k = 30.0
		fmax = 70.0
	elif S.punch_s == "windup":
		tgt = cocked
		k = 50.0
		fmax = 120.0
	elif S.punch_s == "strike":
		tgt = S.punch_tgt
		k = 220.0 + 300.0 * S.punch_crel
		zeta = 0.32   # passa do ponto: follow-through
		fmax = 700.0 + 1300.0 * S.punch_crel
	elif S.punch_s == "recover":
		k = 14.0      # volta pesado, sem pressa
		zeta = 0.9
		fmax = 55.0
	var force = (k * (tgt - a.pos) - 2.0 * sqrt(k) * zeta * S.arm_vel).limit_length(fmax * pk)
	if S.punch_s == "charge":   # o braço vibra enquanto pressuriza
		force += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * c * 30.0
	S.arm_vel += force * dt
	a.pos += S.arm_vel * dt
	var off = a.pos - a.shoulder
	if off.length() > 15.4:
		var n = off.normalized()
		a.pos = a.shoulder + n * 15.4
		var out = S.arm_vel.dot(n)
		if out > 0.0:
			S.arm_vel -= n * out
	arm_reaction(a, S.arm_vel, dt)
	update_arm(a)
	# braço esquerdo: bloqueio. No soco do direito ele recolhe pro peito (contra-movimento)
	var can_block = mouse_r and S.sec.armL > 0.0 and S.P > 10.0 and S.guard > 0.6
	S.block = min(1.0, S.block + 2.4 * p * dt) if can_block else max(0.0, S.block - 2.8 * dt)
	var bt = b.rest.lerp(b.guard, gs)
	bt.z += swing
	if S.punch_s == "windup" or S.punch_s == "strike":
		bt = bt.lerp(Vector3(-4.6, -3.2, -2.5), 0.7 if S.punch_s == "strike" else 0.35)
	bt = bt.lerp(Vector3(-1.4, -1, -7.2), smooth(S.block))
	var bv = b.get("vel", Vector3.ZERO)
	var kb = 60.0
	var fb = (kb * (bt - b.pos) - 2.0 * sqrt(kb) * 0.8 * bv).limit_length(240.0 * pk)
	bv += fb * dt
	b.pos += bv * dt
	b.vel = bv
	arm_reaction(b, bv, dt)
	update_arm(b)


# o braço acelera, o corpo leva o tranco ao contrário (torso, rolagem, pescoço)
func arm_reaction(arm, vel, dt):
	var prev = arm.get("vprev", vel)
	arm.vprev = vel
	var acc = ((vel - prev) / max(dt, 0.004)).limit_length(2500.0)
	S.react_rollv += (acc.y * arm.side * 0.0006 - acc.x * 0.0002) * dt
	S.lean_fv += -acc.z * 0.0002 * dt
	S.t_vel += acc.z * arm.side * 0.0003 * dt
	S.hc_v += -acc.x * 0.0004 * dt


# mira procedural: o soco vai onde o inimigo está, não sempre no mesmo ponto
func compute_punch_target(a):
	var world_pt = null
	var best_d = 1e9
	for col in S.colossi:
		if col.state == "dead":
			continue
		var d = hyp(col.x - S.pos.x, col.z - S.pos.y)
		if d < 70.0 and abs(angle_to(col.x, col.z)) < 40.0 * DEG and d < best_d:
			best_d = d
			world_pt = Vector3(col.x, 26.0 + randf_range(-3.0, 3.0), col.z)
	if world_pt == null:
		for cr in S.crawlers:
			if cr.dead or cr.state == "latched":
				continue
			var d = hyp(cr.x - S.pos.x, cr.z - S.pos.y)
			if d < 36.0 and abs(angle_to(cr.x, cr.z)) < 35.0 * DEG and d < best_d:
				best_d = d
				world_pt = Vector3(cr.x, 2.0, cr.z)
	if world_pt == null:
		world_pt = cam.global_position - cam.global_transform.basis.z * 40.0
	var local = cockpit.to_local(world_pt)
	var dir = (local - a.shoulder).normalized()
	dir.z = min(dir.z, -0.35)
	dir = dir.normalized()
	return a.shoulder + dir * 14.6 + Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), 0.0)


func start_strike(a):
	var cr = S.punch_crel
	S.punch_s = "strike"
	S.punch_t = 0.75
	S.punch_tgt = compute_punch_target(a)
	# o corpo inteiro vai junto: ombro gira, peso passa pra frente, cabeça encolhe
	S.commit = 0.6 + 0.4 * cr
	S.t_vel += 0.45 + 0.6 * cr
	S.lean_fv -= 0.12 + 0.2 * cr
	S.sway_v -= 0.4 * cr
	S.hp_adjv -= 0.35 * (0.5 + cr)
	S.pod_zv -= 0.8 * cr


func resolve_punch(a):
	var cr = S.punch_crel
	var hit = punch_impact()
	S.punch_s = "recover"
	S.punch_t = 0.8 + 0.6 * cr
	if hit:
		S.hitstop = 0.05 + 0.08 * cr          # o mundo trava um instante no contato
		S.arm_vel = -S.arm_vel * 0.18          # o punho para no alvo e volta
		S.shake = max(S.shake, 0.9 + 0.6 * cr)
		S.pod_zv += 2.0 + 3.0 * cr             # cabine leva o coice
		S.fov_k += 2.0 + 3.0 * cr
		S.t_vel -= 0.35 + 0.5 * cr             # recuo no ombro
		S.lean_fv += 0.25 * cr
		S.hp_adjv += 0.5 + 0.6 * cr            # cabeça dá o tranco
		S.hc_v += randf_range(-0.6, 0.6)
		S.push -= Vector2(-sin(S.yaw), -cos(S.yaw)) * (1.0 + 2.5 * cr)
		S.neural = min(1.0, S.neural + 0.15 * cr)
		puff(cockpit.to_global(a.pos), 4.0 + 6.0 * cr, 0xffc070, 0.35, 1.0)
	else:
		# soco no vazio: o corpo passa do ponto e demora pra voltar
		S.punch_t += 0.5
		S.t_vel += 0.3 * cr
		S.lean_fv -= 0.15 * cr
		S.commit = 1.0
		S.shake = max(S.shake, 0.3)


func update_colossi(dt):
	S.threat = false
	for col in S.colossi:
		var m = col.m
		if col.state == "dead":
			col.dead += dt
			m.body.rotation.x = lerp(m.body.rotation.x, -1.45, min(1.0, dt * 1.6))
			m.g.position.y = lerp(m.g.position.y, -3.0, min(1.0, dt * 0.5))
			m.glow.emission_energy_multiplier = max(0.0, m.glow.emission_energy_multiplier - dt)
			m.eye.emission_energy_multiplier = max(0.0, m.eye.emission_energy_multiplier - dt)
			if col.dead > 1.1 and not col.fell:
				col.fell = true
				var dd = hyp(col.x - S.pos.x, col.z - S.pos.y)
				snd.play("far", clamp(1.4 - dd / 200.0, 0.1, 1.2))
				S.shake = max(S.shake, clamp(1.2 - dd / 150.0, 0.0, 1.0))
				puff(Vector3(col.x, 3, col.z), 22.0, 0xa48a68, 2.5, 2.0)
			continue
		var dx = S.pos.x - col.x
		var dz = S.pos.y - col.z
		var dist = max(hyp(dx, dz), 0.001)
		var facing = atan2(dx, dz)
		var turn = 0.0
		var speed = 0.0
		col.flash = max(0.0, col.flash - dt * 3.0)
		match col.state:
			"approach":
				turn = 0.9
				if dist > 34.0:
					speed = 6.5
				col.cd -= dt
				if col.cd <= 0.0 and dist < 80.0:
					if dist > 36.0:
						col.state = "tCharge"
						col.t = 2.5
						snd.play("roar", clamp(1.3 - dist / 300.0, 0.3, 1.0))
					else:
						col.state = "tSlam"
						col.t = 2.0
						snd.play("roar", clamp(1.3 - dist / 300.0, 0.3, 1.0) * 0.8, 1.2)
			"tCharge":
				S.threat = true
				turn = 1.4
				col.t -= dt
				col.crouch = approach(col.crouch, 1.0, dt * 1.2)
				col.glow = 0.15 + 4.0 * (1.0 - col.t / 2.5) + sin(S.time * 18.0) * 0.4
				if col.t <= 0.0:
					col.state = "charge"
					col.dirX = dx / dist
					col.dirZ = dz / dist
					col.yaw = facing
					turn = 0.0
					col.travel = 0.0
					col.maxTravel = dist + 24.0
					col.hit = false
			"charge":
				S.threat = true
				var sp = 34.0
				col.x += col.dirX * sp * dt
				col.z += col.dirZ * sp * dt
				col.travel += sp * dt
				col.crouch = approach(col.crouch, 0.4, dt * 3.0)
				col.glow = 3.0
				if randf() < dt * 14.0:
					puff(Vector3(col.x + randf_range(-4, 4), 1, col.z + randf_range(-4, 4)), 6.0, 0xb59a74, 1.0, 2.0)
				if not col.hit and hyp(S.pos.x - col.x, S.pos.y - col.z) < 18.0:
					col.hit = true
					hit_mech(col.x, col.z, 24.0)
					col.state = "recover"
					col.t = 2.4
				elif col.travel > col.maxTravel:
					col.state = "recover"
					col.t = 2.4
			"tSlam":
				S.threat = true
				turn = 1.1
				if dist > 30.0:
					speed = 3.0
				col.t -= dt
				col.armRaise = approach(col.armRaise, 1.0, dt * 0.8)
				col.glow = 0.15 + 2.0 * (1.0 - col.t / 2.0)
				if col.t <= 0.0:
					col.state = "slam"
					col.t = 0.28
			"slam":
				S.threat = true
				col.t -= dt
				col.armRaise = approach(col.armRaise, 0.3, dt * 6.0)
				if col.t <= 0.0:
					var px = col.x + sin(col.yaw) * 19.0
					var pz = col.z + cos(col.yaw) * 19.0
					snd.play("far", clamp(1.3 - dist / 200.0, 0.2, 1.3))
					S.shake = max(S.shake, clamp(1.4 - dist / 120.0, 0.2, 1.2))
					for i in range(6):
						var pa = i / 6.0 * TAU
						puff(Vector3(px + cos(pa) * 7.0, 1, pz + sin(pa) * 7.0), 9.0, 0xb59a74, 1.8, 2.5)
					if hyp(S.pos.x - px, S.pos.y - pz) < 24.0:
						hit_mech(col.x, col.z, 32.0)
					col.state = "recover"
					col.t = 2.2
			"recover":
				col.t -= dt
				col.crouch = approach(col.crouch, 0.0, dt)
				col.armRaise = approach(col.armRaise, 0.0, dt * 0.8)
				col.glow = approach(col.glow, 0.15, dt * 3.0)
				if col.t <= 0.0:
					col.state = "approach"
					col.cd = randf_range(2.2, 4.2)
			"stagger":
				col.t -= dt
				col.crouch = approach(col.crouch, 0.0, dt * 2.0)
				col.armRaise = approach(col.armRaise, 0.0, dt * 2.0)
				col.glow = approach(col.glow, 0.05, dt * 4.0)
				if col.t <= 0.0:
					col.state = "approach"
					col.cd = 2.0
		if turn > 0.0:
			col.yaw += clamp(ang_wrap(facing - col.yaw), -turn * dt, turn * dt)
		# empurrão do soco e separação
		col.x += col.kx * dt
		col.z += col.kz * dt
		col.kx *= max(0.0, 1.0 - 2.5 * dt)
		col.kz *= max(0.0, 1.0 - 2.5 * dt)
		if speed > 0.0:
			col.x += sin(col.yaw) * speed * dt
			col.z += cos(col.yaw) * speed * dt
		var nd = max(hyp(S.pos.x - col.x, S.pos.y - col.z), 0.001)
		if nd < 18.0:
			col.x -= (S.pos.x - col.x) / nd * (18.0 - nd)
			col.z -= (S.pos.y - col.z) / nd * (18.0 - nd)
		# passos à distância
		var walking = speed > 0.0 or col.state == "charge"
		if walking:
			col.phase += dt * (5.0 if col.state == "charge" else 1.6)
			var stp = int(floor(col.phase / PI))
			if stp != col.lastStep:
				col.lastStep = stp
				var dd = hyp(col.x - S.pos.x, col.z - S.pos.y)
				snd.play("far", clamp(0.9 - dd / 260.0, 0.0, 0.9) * (1.2 if col.state == "charge" else 0.7))
				if dd < 90.0:
					S.shake = max(S.shake, 0.25 * (1.0 - dd / 90.0))
		# pose
		m.g.position = Vector3(col.x, 0, col.z)
		m.g.rotation.y = col.yaw
		var sw = sin(col.phase) if walking else 0.0
		m.legL.rotation.x = sw * 0.45
		m.legR.rotation.x = -sw * 0.45
		m.body.position.y = -col.crouch * 2.5
		m.upper.rotation.x = col.crouch * 0.45 + (-0.35 if col.state == "stagger" else 0.0)
		m.armL.rotation.x = -sw * 0.3 + col.crouch * -0.6
		m.armR.rotation.x = sw * 0.3 + col.crouch * -0.6 - col.armRaise * 2.7
		m.glow.emission_energy_multiplier = max(0.05, col.glow)
		if m.hide is BaseMaterial3D:
			m.hide.emission = Color(col.flash * 0.5, col.flash * 0.2, 0.0)
		if col.hp <= 0.0:
			col.state = "dead"
			S.kills_colossi += 1
			show_msg("COLOSSO ABATIDO", "", 2.0)
			snd.play("roar", 0.5, 0.7)


func update_crawlers(dt):
	var latched = 0
	for cr in S.crawlers:
		if cr.dead:
			continue
		cr.ph += dt * 14.0
		var g = cr.m.g
		if cr.state == "run":
			if cr.stun > 0.0:
				cr.stun = max(0.0, cr.stun - dt)
			var best = null
			var bd = 1e9
			for L in legs:
				var d = hyp(L.x - cr.x, L.z - cr.z)
				if d < bd:
					bd = d
					best = L
			if cr.stun <= 0.0 and bd > 0.001:
				var dx = best.x - cr.x
				var dz = best.z - cr.z
				cr.x += dx / bd * cr.speed * dt
				cr.z += dz / bd * cr.speed * dt
				g.rotation.y = atan2(dx, dz)
			cr.y = 0.0
			if bd < 4.0 and not best.stepping:
				cr.state = "latched"
				cr.foot = best
				var a = randf_range(0.0, TAU)
				cr.ox = cos(a) * 3.0
				cr.oz = sin(a) * 3.0
				snd.play("latch", 0.8)
		else:
			latched += 1
			cr.x = cr.foot.x + cr.ox
			cr.z = cr.foot.z + cr.oz
			cr.y = cr.foot.y + 2.0 + sin(cr.ph * 0.5) * 0.3
			if S.sec.legs > 0.0:
				S.sec.legs = max(0.0, S.sec.legs - 2.2 * dt)
			else:
				S.sec.cockpit = max(0.0, S.sec.cockpit - 0.7 * dt)
		g.position = Vector3(cr.x, cr.y, cr.z)
		var lc = cr.m.legsC
		for i in range(lc.size()):
			lc[i].rotation.x = sin(cr.ph + i) * 0.5
		if cr.m.body != null:
			cr.m.body.rotation = Vector3(sin(cr.ph * 2.0) * 0.03, 0.0, sin(cr.ph) * 0.07)
			cr.m.body.position.y = abs(sin(cr.ph)) * 0.18
	S.latched = latched
	if latched > 0 and randf() < dt * latched * 0.8:
		snd.play("latch", 0.25, randf_range(1.3, 1.9))
	# limpa mortos
	if S.crawlers.size() > 60:
		var keep = []
		for cr in S.crawlers:
			if cr.dead:
				cr.m.g.queue_free()
			else:
				keep.append(cr)
		S.crawlers = keep


func update_fx(dt):
	for p in puffs:
		if not p.s.visible:
			continue
		p.life -= dt
		if p.life <= 0.0:
			p.s.visible = false
			continue
		p.s.modulate = Color(p.col.r, p.col.g, p.col.b, p.life / p.maxl * 0.55)
		p.s.scale += Vector3.ONE * (p.grow * dt)
		p.s.position.y += p.vy * dt
	for t in tracers:
		if not t.n.visible:
			continue
		t.life -= dt
		if t.life <= 0.0:
			t.n.visible = false
	muzzle_light.light_energy = max(0.0, muzzle_light.light_energy - dt * 80.0)
	dust.position = Vector3(S.pos.x, 22.0, S.pos.y)
	# conexão neural e tremor
	S.shake = max(0.0, S.shake - dt * 1.6)
	S.fov_k = clamp(S.fov_k - dt * (2.5 + S.fov_k * 2.0), 0.0, 6.0)
	S.neural = max(0.0, S.neural - dt * 0.55)
	var low = (0.25 + 0.1 * sin(S.time * 4.0)) if S.sec.cockpit < 30.0 else 0.0
	vignette.modulate.a = clamp(S.neural * 0.9 + low, 0.0, 1.0)
	# luzes da cabine
	var alarm = S.scram > 0.0 or S.sec.cockpit < 30.0 or S.threat
	S.alarm_t += dt
	alarm_light.light_energy = (3.0 if sin(S.alarm_t * 7.0) > 0.0 else 0.3) if alarm else 0.0
	if not S.sw.light:
		cabin_light.light_energy = 0.0
	elif S.reactor_on:
		cabin_light.light_energy = 2.2
	else:
		cabin_light.light_energy = (0.5 + randf() * 0.3) if S.sw.bat else 0.0
	if S.msg_t > 0.0:
		S.msg_t -= dt
	S.in_range = false
	for col in S.colossi:
		if col.state == "dead":
			continue
		if hyp(col.x - S.pos.x, col.z - S.pos.y) < 48.0 and abs(angle_to(col.x, col.z)) < 30.0 * DEG:
			S.in_range = true


func update_audio():
	var playing = S.phase == "play"
	var r = S.rpm
	# bomba hidráulica: barulho alto e constante, a carga muda com a pressão
	var load_k = clamp((0.7 if S.punch_s == "charge" else 0.0) + abs(S.v) / 10.0 + (0.3 if S.P < 120.0 else 0.0), 0.0, 1.0)
	var pump = (0.28 + 0.25 * r + 0.18 * load_k) * min(1.0, r * 3.0) if (playing and S.sw.hyd and r > 0.05) else 0.0
	snd.set_loop("pump", pump, 0.8 + 0.42 * r + 0.16 * load_k)
	snd.set_loop("turb", (0.08 + 0.2 * r) * min(1.0, r * 4.0) if playing else 0.0, 0.45 + 1.0 * r, 0.05)
	snd.set_loop("reactor", (0.32 + S.heat * 0.12 if S.reactor_on else 0.03) if playing else 0.0, 1.0, 0.08)
	# motores do torso
	var tv = abs(S.t_vel) + abs(S.w) * 2.0
	snd.set_loop("motor", clamp(tv * 0.55, 0.0, 0.35) if playing else 0.0, 0.8 + tv * 1.5, 0.3)
	# alívio e alarme
	snd.set_loop("relief", S.relief * 0.22 if playing else 0.0, 1.0, 0.3)
	snd.set_loop("alarm", 0.35 if (playing and (S.scram > 0.0 or S.sec.cockpit < 25.0)) else 0.0, 1.0, 0.5)
	# conexão neural: abafa o som quando o mech apanha
	if lowpass != null:
		lowpass.cutoff_hz = 18000.0 - S.neural * 17000.0


var lowpass = null


# ============================== CÂMERA E LAÇO ==============================
var shake_noise = null
var shake_clock = 0.0


func apply_camera():
	# o corpo inteiro (quadril + torso) passa pro pé de apoio; o torso não desliza sobre o quadril
	mech.position = Vector3(S.pos.x + cos(S.yaw) * S.sway, S.body_y, S.pos.y - sin(S.yaw) * S.sway)
	mech.rotation.y = S.yaw
	var lean = S.roll * 0.5 - S.sway * 0.02 + S.react_roll
	var pitch = S.nod + S.lean_f
	torso.position.x = 0.0
	torso.rotation = Vector3(pitch, S.t + S.sway * 0.01, lean)
	# tremor grave e contínuo (ruído suave), não chiado aleatório por quadro
	if shake_noise == null:
		shake_noise = FastNoiseLite.new()
		shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		shake_noise.frequency = 1.0
	var sh = S.shake * S.shake
	var q = shake_clock * 8.0
	var n1 = shake_noise.get_noise_2d(q, 0.0)
	var n2 = shake_noise.get_noise_2d(q, 37.0)
	var n3 = shake_noise.get_noise_2d(q, 91.0)
	cockpit.position = Vector3(n1 * sh * 0.45, 8.0 + S.pod_y + S.kick + n2 * sh * 0.45, -4.2 + S.pod_z)
	# o capacete compensa só parte do balanço: o piloto sente o passo, mas a mira fica utilizável
	head.rotation = Vector3(S.p + S.look_p - pitch * 0.3 + S.hp_adj + n3 * sh * 0.01, S.h + S.look_h + S.hc, -lean * 0.4 + n1 * sh * 0.012)
	cam.fov = 72.0 + S.fov_k
	pendulum.rotation = Vector3(S.pend_f, 0.0, S.pend_l)
	pendulum2.rotation = Vector3(S.pend_f * 0.7, 0.0, S.pend_l * 0.7)


func _process(delta):
	if S == null:
		return
	var dt = min(0.05, delta)
	shake_clock += delta
	if S.hitstop > 0.0:   # trava curta no contato do soco
		S.hitstop -= delta
		dt *= 0.06
	if S.phase == "play":
		S.time += dt
		update_systems(dt)
		update_motion(dt)
		update_legs(dt)
		update_punch(dt)
		fire_gun(dt)
		update_colossi(dt)
		update_crawlers(dt)
		update_waves(dt)
		update_cockpit_props(dt)
		update_fx(dt)
		if S.phase == "play" and S.sec.cockpit <= 0.0:
			end_game(false)
	apply_camera()
	update_audio()
	var lit = 0.07
	if S.reactor_on:
		lit = 1.0
	elif S.sw.bat:
		lit = 0.4 + randf() * 0.25
	for pn in panels:
		pn.mat.albedo_color = Color(lit, lit, lit)
	sight_lamp_mat.albedo_color = hexc(0x9dff7a if S.in_range else 0x3a2a14)
