extends Node
# Som gerado em código: laços contínuos (bomba, turbina, reator, motores,
# válvula, alarme) e efeitos curtos. Depois dá pra trocar por gravações.

const RATE = 22050
var loops = {}
var loop_lin = {}
var shots = {}
var pool = []
var pool_i = 0
var rng = RandomNumberGenerator.new()


func _ready():
	_make_loops()
	_make_shots()
	for i in range(10):
		var pl = AudioStreamPlayer.new()
		add_child(pl)
		pool.append(pl)


func _wav(samples, looped):
	var n = samples.size()
	var data = PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	var wv = AudioStreamWAV.new()
	wv.format = AudioStreamWAV.FORMAT_16_BITS
	wv.mix_rate = RATE
	wv.stereo = false
	wv.data = data
	if looped:
		wv.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wv.loop_begin = 0
		wv.loop_end = n
	return wv


func _buf(sec):
	var b = PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b


func _saw(ph):
	return 2.0 * (ph - floor(ph)) - 1.0


func _sq(ph):
	return 1.0 if (ph - floor(ph)) < 0.5 else -1.0


func _add_loop(key, samples):
	var pl = AudioStreamPlayer.new()
	pl.stream = _wav(samples, true)
	pl.volume_db = -80.0
	add_child(pl)
	pl.play()
	loops[key] = pl
	loop_lin[key] = 0.0


func _make_loops():
	var n = RATE
	var b
	var y = 0.0
	# bomba hidráulica: ronco grave pulsado
	b = _buf(1.0)
	for i in range(n):
		var t = float(i) / RATE
		var s = _saw(41.0 * t) * 0.5 + _sq(82.0 * t) * 0.18 + _saw(123.0 * t) * 0.09
		y += (s - y) * 0.12
		b[i] = y * (0.6 + 0.4 * sin(TAU * 9.0 * t)) * 1.6
	_add_loop("pump", b)
	# turbina: sopro + assobio
	b = _buf(1.0)
	var a1 = 0.0
	var a2 = 0.0
	var lo = 0.0
	for i in range(n):
		var t = float(i) / RATE
		var wn = rng.randf_range(-1.0, 1.0)
		a1 += (wn - a1) * 0.5
		a2 += (wn - a2) * 0.15
		lo += (_saw(48.0 * t) - lo) * 0.05
		b[i] = (a1 - a2) * 0.9 + sin(TAU * 1200.0 * t) * 0.05 + lo * 0.25
	_add_loop("turb", b)
	# reator: zumbido fixo
	b = _buf(1.0)
	for i in range(n):
		var t = float(i) / RATE
		b[i] = sin(TAU * 50.0 * t) * 0.5 + sin(TAU * 100.0 * t) * 0.22 + sin(TAU * 150.0 * t) * 0.06
	_add_loop("reactor", b)
	# motores elétricos do torso
	b = _buf(1.0)
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		var s = _saw(200.0 * t) + _sq(301.0 * t) * 0.25
		y += (s - y) * 0.25
		b[i] = y * 0.35
	_add_loop("motor", b)
	# válvula de alívio
	b = _buf(1.0)
	y = 0.0
	for i in range(n):
		var wn = rng.randf_range(-1.0, 1.0)
		y += (wn - y) * 0.3
		b[i] = (wn - y) * 0.5
	_add_loop("relief", b)
	# alarme
	b = _buf(1.0)
	var ph = 0.0
	for i in range(n):
		var f = 650.0 if i < n / 2 else 870.0
		ph += f / RATE
		b[i] = _sq(ph) * 0.2
	_add_loop("alarm", b)


func _make_shots():
	var b
	var n
	var ph = 0.0
	var y = 0.0
	var y2 = 0.0
	# passo
	b = _buf(0.9)
	n = b.size()
	ph = 0.0
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		ph += lerp(70.0, 24.0, t / 0.9) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.08
		b[i] = sin(TAU * ph) * 0.9 * exp(-5.0 * t) + y * 2.0 * exp(-8.0 * t)
	shots["step"] = _wav(b, false)
	# baque distante
	b = _buf(1.1)
	n = b.size()
	ph = 0.0
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		ph += lerp(55.0, 22.0, t / 1.1) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.04
		b[i] = sin(TAU * ph) * 0.8 * exp(-4.0 * t) + y * 2.5 * exp(-5.0 * t)
	shots["far"] = _wav(b, false)
	# metal
	b = _buf(0.45)
	n = b.size()
	y = 0.0
	y2 = 0.0
	for i in range(n):
		var t = float(i) / RATE
		var s = 0.0
		for f in [287.0, 431.0, 689.0, 1043.0]:
			s += _sq(f * t) * 0.09
		var wn = rng.randf_range(-1.0, 1.0)
		y += (wn - y) * 0.5
		y2 += (wn - y2) * 0.2
		b[i] = s * exp(-9.0 * t) + (y - y2) * 0.6 * exp(-16.0 * t)
	shots["clank"] = _wav(b, false)
	# impacto
	b = _buf(1.0)
	n = b.size()
	ph = 0.0
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		ph += lerp(90.0, 28.0, t) / RATE
		y += (rng.randf_range(-1.0, 1.0) - y) * 0.15
		var s = 0.0
		for f in [287.0, 431.0, 689.0]:
			s += _sq(f * t) * 0.07
		b[i] = sin(TAU * ph) * exp(-4.5 * t) + y * 1.6 * exp(-5.0 * t) + s * exp(-8.0 * t)
	shots["impact"] = _wav(b, false)
	# canhão
	b = _buf(0.18)
	n = b.size()
	ph = 0.0
	y = 0.0
	y2 = 0.0
	for i in range(n):
		var t = float(i) / RATE
		ph += lerp(140.0, 60.0, t / 0.18) / RATE
		var wn = rng.randf_range(-1.0, 1.0)
		y += (wn - y) * 0.3
		y2 += (wn - y2) * 0.08
		b[i] = (y - y2) * 1.4 * exp(-25.0 * t) + _sq(ph) * 0.15 * exp(-20.0 * t)
	shots["gun"] = _wav(b, false)
	# chiado
	b = _buf(0.9)
	n = b.size()
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		var wn = rng.randf_range(-1.0, 1.0)
		y += (wn - y) * 0.3
		b[i] = (wn - y) * 0.45 * exp(-3.5 * t)
	shots["hiss"] = _wav(b, false)
	# rangido
	b = _buf(1.3)
	n = b.size()
	ph = 0.0
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		ph += lerp(92.0, 72.0, t / 1.3) / RATE
		var s = _saw(ph) + _saw(ph * 1.505)
		y += (s - y) * 0.2
		b[i] = y * 0.2 * min(1.0, t * 10.0) * exp(-2.5 * t)
	shots["creak"] = _wav(b, false)
	# rugido
	b = _buf(2.2)
	n = b.size()
	ph = 0.0
	y = 0.0
	y2 = 0.0
	for i in range(n):
		var t = float(i) / RATE
		ph += (lerp(70.0, 52.0, t / 2.2) + 6.0 * sin(TAU * 7.0 * t)) / RATE
		y += (_saw(ph) - y) * 0.12
		y2 += (rng.randf_range(-1.0, 1.0) - y2) * 0.06
		var env = min(1.0, t / 0.3) * min(1.0, (2.2 - t) / 0.4)
		b[i] = (y * 0.9 + y2 * 1.2) * env
	shots["roar"] = _wav(b, false)
	# servo levantando a perna
	b = _buf(1.2)
	n = b.size()
	ph = 0.0
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		var k = t / 1.2
		var f = lerp(85.0, 210.0, k / 0.6) if k < 0.6 else lerp(210.0, 120.0, (k - 0.6) / 0.4)
		ph += f / RATE
		y += (_saw(ph) - y) * 0.3
		b[i] = y * 0.3 * min(1.0, t / 0.12) * min(1.0, (1.2 - t) / 0.3)
	shots["lift"] = _wav(b, false)
	# bipe
	b = _buf(0.12)
	n = b.size()
	for i in range(n):
		var t = float(i) / RATE
		b[i] = _sq(1200.0 * t) * 0.15 * exp(-12.0 * t)
	shots["beep"] = _wav(b, false)
	# garra agarrando
	b = _buf(0.15)
	n = b.size()
	for i in range(n):
		var t = float(i) / RATE
		b[i] = (_sq(800.0 * t) + _sq(1270.0 * t)) * 0.08 * exp(-18.0 * t) + rng.randf_range(-1.0, 1.0) * 0.1 * exp(-30.0 * t)
	shots["latch"] = _wav(b, false)
	# clique de chave
	b = _buf(0.07)
	n = b.size()
	for i in range(n):
		var t = float(i) / RATE
		b[i] = rng.randf_range(-1.0, 1.0) * 0.5 * exp(-90.0 * t) + _sq(180.0 * t) * 0.2 * exp(-50.0 * t)
	shots["click"] = _wav(b, false)
	# motor de arranque
	b = _buf(3.4)
	n = b.size()
	ph = 0.0
	y = 0.0
	for i in range(n):
		var t = float(i) / RATE
		ph += lerp(90.0, 520.0, t / 3.4) / RATE
		y += (_saw(ph) - y) * 0.2
		b[i] = y * 0.18 * min(1.0, t * 8.0) * min(1.0, (3.4 - t) * 4.0)
	shots["starter"] = _wav(b, false)


# volume e tom de um laço contínuo (suavizado)
func set_loop(key, vol, pitch = 1.0, smooth_k = 0.15):
	var pl = loops[key]
	loop_lin[key] = lerp(loop_lin[key], float(vol), smooth_k)
	pl.volume_db = linear_to_db(max(loop_lin[key], 0.0001))
	pl.pitch_scale = lerp(pl.pitch_scale, clamp(float(pitch), 0.2, 4.0), smooth_k)


func play(key, vol = 1.0, pitch = 1.0):
	if vol < 0.02 or not shots.has(key):
		return
	var pl = pool[pool_i]
	pool_i = (pool_i + 1) % pool.size()
	pl.stream = shots[key]
	pl.volume_db = linear_to_db(clamp(vol * 0.8, 0.0001, 2.0))
	pl.pitch_scale = clamp(pitch, 0.3, 3.0)
	pl.play()
