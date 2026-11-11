extends Control
# Desenha um painel de instrumentos dentro de um SubViewport.
# O resultado vira a textura de uma placa física na cabine (nada de HUD).

var game
var mode = "left"
var font

const C_TEXT = Color("#d8ccaa")
const C_DIM = Color("#a39a83")
const C_AMBER = Color("#ffb547")
const C_INK = Color("#1b1914")


func _ready():
	font = ThemeDB.fallback_font


func _process(_delta):
	queue_redraw()


# texto com (x, y) no meio da altura. align: 0 esquerda, 1 centro, 2 direita
func txt(s, x, y, fsize, col, align = 0):
	var w = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var px = x
	if align == 1:
		px = x - w / 2.0
	elif align == 2:
		px = x - w
	draw_string(font, Vector2(px, y + fsize * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func panel_bg(w, h):
	draw_rect(Rect2(0, 0, w, h), Color("#36342c"))
	draw_rect(Rect2(0, 0, w, h * 0.3), Color("#403e35"))
	for i in range(60):
		var yy = (i * 53) % int(h)
		var xx = (i * 131) % int(w)
		draw_line(Vector2(xx, yy), Vector2(xx + 40 + (i % 7) * 14, yy + (i % 3) - 1), Color(0.85, 0.8, 0.67, 0.07), 1.5)
	draw_rect(Rect2(4, 4, w - 8, h - 8), Color("#0d0c0a"), false, 8.0)
	draw_rect(Rect2(10, 10, w - 20, h - 20), Color("#6b6555"), false, 2.0)
	for pt in [Vector2(24, 24), Vector2(w - 24, 24), Vector2(24, h - 24), Vector2(w - 24, h - 24), Vector2(w / 2.0, 22), Vector2(w / 2.0, h - 22)]:
		draw_circle(pt, 6, Color("#25231e"))
		draw_circle(pt - Vector2(1.5, 1.5), 3.5, Color("#9c947e"))


func dial(cx, cy, r, val, vmin, vmax, label, unit, red_from, majors):
	var c = Vector2(cx, cy)
	draw_circle(c, r * 1.12, Color("#121110"))
	draw_arc(c, r * 1.06, 0, TAU, 48, Color("#7b7462"), r * 0.07, true)
	draw_circle(c, r, Color("#c9bb92"))
	draw_circle(c - Vector2(r * 0.2, r * 0.2), r * 0.55, Color(0.92, 0.87, 0.74, 0.35))
	var a0 = deg_to_rad(135.0)
	var sweep = deg_to_rad(270.0)
	if red_from != null:
		var ra = a0 + clamp((red_from - vmin) / (vmax - vmin), 0.0, 1.0) * sweep
		draw_arc(c, r * 0.82, ra, a0 + sweep, 24, Color("#b8321e"), r * 0.12, true)
	var n = majors * 5
	for i in range(n + 1):
		var a = a0 + sweep * i / float(n)
		var major = i % 5 == 0
		var r1 = r * (0.7 if major else 0.78)
		var dir = Vector2(cos(a), sin(a))
		draw_line(c + dir * r1, c + dir * r * 0.9, C_INK, r * (0.05 if major else 0.022), true)
		if major:
			var v = vmin + (vmax - vmin) * i / float(n)
			txt(str(int(round(v))), cx + dir.x * r * 0.52, cy + dir.y * r * 0.52, int(r * 0.2), C_INK, 1)
	txt(unit, cx, cy + r * 0.45, int(r * 0.16), Color("#4a4232"), 1)
	var na = a0 + clamp((val - vmin) / (vmax - vmin), 0.0, 1.0) * sweep
	var nd = Vector2(cos(na), sin(na))
	draw_line(c - nd * r * 0.15, c + nd * r * 0.86, Color("#a3220f"), r * 0.06, true)
	draw_circle(c, r * 0.1, Color("#2a2722"))
	txt(label, cx, cy + r * 1.36, int(r * 0.3), C_TEXT, 1)


func lever(x, y_top, h, w, val, label, key_name, active):
	draw_rect(Rect2(x - w * 0.18, y_top, w * 0.36, h), Color("#0e0d0b"))
	draw_rect(Rect2(x - w * 0.18, y_top, w * 0.36, h), Color("#5c5545"), false, 2.0)
	for i in range(5):
		var yy = y_top + h * i / 4.0
		draw_line(Vector2(x - w * 0.5, yy), Vector2(x - w * 0.26, yy), Color("#8c846f"), 2.0)
	var y = y_top + (1.0 - val) * h
	draw_line(Vector2(x, y_top + h), Vector2(x, y), Color("#2a2722"), w * 0.14)
	draw_circle(Vector2(x, y), w * 0.34, Color("#4a1a0c"))
	draw_circle(Vector2(x - w * 0.06, y - w * 0.06), w * 0.24, Color("#f07a44") if active else Color("#b44a28"))
	txt(label, x, y_top + h + w * 0.42, int(w * 0.38), C_TEXT, 1)
	txt("%s · %d%%" % [key_name, int(round(val * 100.0))], x, y_top + h + w * 0.86, int(w * 0.28), C_DIM, 1)


func lamp(x, y, r, color, on, label, value = "", vx = 0.0):
	draw_circle(Vector2(x, y), r * 1.3, Color("#0d0c0a"))
	if on:
		draw_circle(Vector2(x, y), r * 1.7, Color(color.r, color.g, color.b, 0.25))
	draw_circle(Vector2(x, y), r, color if on else Color("#2a2620"))
	txt(label, x + r * 2.0, y, int(r * 1.5), C_TEXT, 0)
	if value != "":
		txt(value, vx, y, int(r * 1.3), C_DIM, 2)


func radar(S, cx, cy, r):
	var c = Vector2(cx, cy)
	draw_circle(c, r * 1.1, Color("#121110"))
	draw_circle(c, r, Color("#1d1407"))
	var grid = Color(1.0, 0.67, 0.24, 0.25)
	draw_arc(c, r * 0.33, 0, TAU, 32, grid, 2.0)
	draw_arc(c, r * 0.66, 0, TAU, 40, grid, 2.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), grid, 2.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), grid, 2.0)
	var sa = S.time * 2.2
	for k in range(8):
		var a = sa - k * 0.1
		draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(1.0, 0.67, 0.24, 0.3 * (1.0 - k / 8.0)), 5.0)
	var rng_m = 300.0
	var sc = r / rng_m
	var phi = S.yaw + S.t
	var f = Vector2(-sin(phi), -cos(phi))
	var rt = Vector2(cos(phi), -sin(phi))
	for cr in S.crawlers:
		if cr.dead:
			continue
		_blip(S, c, f, rt, sc, rng_m, cr.x, cr.z, r * 0.035, Color("#ff5533") if cr.state == "latched" else C_AMBER)
	for col in S.colossi:
		if col.state == "dead":
			continue
		var tele = col.state in ["tCharge", "tSlam", "charge", "slam"]
		var cc = Color("#ffcf7a")
		if tele:
			cc = Color("#ff3a20") if sin(S.time * 16.0) > 0 else Color("#ffe0a0")
		_blip(S, c, f, rt, sc, rng_m, col.x, col.z, r * 0.085, cc)
	var bt = -S.t
	draw_line(c, c + Vector2(sin(bt), -cos(bt)) * r * 0.24, C_TEXT, 4.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(-7, 7), c + Vector2(7, 7)]), C_TEXT)
	draw_arc(c, r * 1.04, 0, TAU, 48, Color("#7b7462"), r * 0.05, true)
	txt("RADAR 300 m", cx, cy + r * 1.3, int(r * 0.2), C_TEXT, 1)


func _blip(S, c, f, rt, sc, rng_m, x, z, size, color):
	var d = Vector2(x - S.pos.x, z - S.pos.y)
	var fwd = d.dot(f)
	var side = d.dot(rt)
	var dist = sqrt(fwd * fwd + side * side)
	if dist > rng_m * 0.97:
		fwd *= rng_m * 0.97 / dist
		side *= rng_m * 0.97 / dist
	draw_circle(c + Vector2(side * sc, -fwd * sc), size, color)


func placard(x, y, w, h):
	draw_rect(Rect2(x, y, w, h), Color("#17110a"))
	draw_rect(Rect2(x - 3, y - 3, w + 6, h + 6), Color("#6b6555"), false, 1.5)


func _draw():
	if game == null or game.S == null:
		return
	var S = game.S
	match mode:
		"left":
			_draw_left(S)
		"right":
			_draw_right(S)
		"top":
			_draw_top(S)
		"start":
			_draw_start()


func _draw_left(S):
	panel_bg(1024, 512)
	dial(165, 215, 104, S.rpm * 12.0, 0.0, 12.0, "TURBINA", "rpm×1000", 10.5, 4)
	dial(425, 215, 104, S.P, 0.0, 210.0, "PRESSÃO", "bar", 185.0, 7)
	dial(685, 215, 104, 250.0 + S.heat * 400.0, 250.0, 650.0, "REATOR", "°C", 570.0, 4)
	dial(908, 140, 66, abs(S.v * S.gf) * 3.6, 0.0, 30.0, "VELOC.", "km/h", null, 3)
	var c = 0.0
	if S.punch_s == "charge":
		c = S.punch_c
	elif S.punch_s == "windup" or S.punch_s == "strike":
		c = 1.0
	dial(908, 345, 66, c * 100.0, 0.0, 100.0, "SOCO", "%", 85.0, 4)
	placard(40, 420, 720, 56)
	var status = "SISTEMAS NOMINAIS"
	if not S.sw.bat and not S.lit:
		status = "MECH DESLIGADO"
	elif not S.reactor_on:
		status = "REATOR DESLIGADO"
	elif S.relief > 0.3:
		status = "VÁLVULA DE ALÍVIO ABERTA"
	elif S.P < 60.0:
		status = "PRESSÃO BAIXA: ESPERE A TURBINA"
	elif S.punch_s == "charge":
		status = "PRESSURIZANDO BRAÇO"
	elif S.block > 0.85:
		status = "BLOQUEIO ARMADO"
	txt(status, 60, 449, 27, C_AMBER, 0)


func _sec_color(S, v):
	if v <= 0.0:
		return Color("#ff3a20") if sin(S.time * 10.0) > 0 else Color("#2a2620")
	if v > 60.0:
		return Color("#7fd06a")
	if v > 25.0:
		return C_AMBER
	return Color("#ff4a2a")


func _draw_right(S):
	panel_bg(1024, 512)
	lever(105, 70, 260, 72, S.E.legs, "PERNAS", "1", Input.is_physical_key_pressed(KEY_1))
	lever(245, 70, 260, 72, S.E.arms, "BRAÇOS", "2", Input.is_physical_key_pressed(KEY_2))
	lever(385, 70, 260, 72, S.E.gun, "ARMA", "3", Input.is_physical_key_pressed(KEY_3))
	var rows = [["CABINE", S.sec.cockpit], ["PERNAS", S.sec.legs], ["BR. ESQ", S.sec.armL], ["BR. DIR", S.sec.armR]]
	for i in range(rows.size()):
		lamp(490, 95 + i * 72, 17, _sec_color(S, rows[i][1]), true, rows[i][0], "%d%%" % int(round(rows[i][1])), 700.0)
	radar(S, 860, 215, 128)
	txt("SEGURE 1 2 3 PARA PUXAR ENERGIA", 40, 472, 20, Color("#8f8772"), 0)


func _counter(y, label, val):
	txt(label, 40, y, 24, C_TEXT, 0)
	draw_rect(Rect2(126, y - 19, 70, 38), Color("#0c0b09"))
	draw_rect(Rect2(126, y - 19, 70, 38), Color("#6b6555"), false, 2.0)
	txt(val, 161, y, 26, C_AMBER, 1)


func _draw_top(S):
	panel_bg(1024, 128)
	var alive = 0
	for cr in S.crawlers:
		if not cr.dead:
			alive += 1
	for col in S.colossi:
		if col.state != "dead":
			alive += 1
	_counter(42, "ONDA", "%d/5" % min(S.wave + 1, 5))
	_counter(88, "HOSTIS", "%02d" % alive)
	placard(214, 22, 552, 84)
	if S.msg_t > 0.0:
		if S.msg_sub != "":
			txt(S.msg_big, 490, 46, 38, C_AMBER, 1)
			txt(S.msg_sub, 490, 86, 17, Color("#dacfae"), 1)
		else:
			txt(S.msg_big, 490, 64, 48, C_AMBER, 1)
	else:
		txt("RÁDIO EM SILÊNCIO", 490, 65, 26, Color("#4f4024"), 1)
	var blink = sin(S.time * 9.0) > 0
	lamp(798, 42, 11, Color("#ff4a2a"), S.threat and blink, "AMEAÇA")
	lamp(798, 88, 11, Color("#ff4a2a"), S.scram > 0.0 and blink, "SCRAM")
	lamp(908, 42, 11, Color("#7fd06a"), S.in_range, "ALCANCE")
	lamp(908, 88, 11, C_AMBER, S.latched > 0 and blink, "AGARROU")


func _draw_start():
	draw_rect(Rect2(0, 0, 1024, 548), Color("#33342a"))
	draw_rect(Rect2(0, 0, 1024, 180), Color("#3e3f31"))
	draw_rect(Rect2(4, 4, 1016, 540), Color("#0d0c0a"), false, 6.0)
	txt("PARTIDA · SISTEMAS", 34, 44, 44, C_TEXT, 0)
	txt("ORDEM 1 A 6 · LUZ ÂMBAR = PRÓXIMA", 520, 46, 21, C_DIM, 0)
	var sws = game.SWITCHES
	for i in range(sws.size()):
		var cx = 512 + (i - 3) * 128
		draw_rect(Rect2(cx - 56, 92, 112, 56), Color("#16150f"))
		txt(sws[i].n if sws[i].n != "" else "·", cx, 120, 38, C_TEXT, 1)
		txt(sws[i].label, cx, 496, 24, C_TEXT, 1)
		if sws[i].kind == "button":
			txt("APERTAR", cx, 176, 16, Color("#8f8670"), 1)
		else:
			txt("LIG", cx, 176, 16, Color("#8f8670"), 1)
			txt("DESL", cx, 380, 16, Color("#8f8670"), 1)
