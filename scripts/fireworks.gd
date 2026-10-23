extends Node2D
## おみくじのあたりの演出。風船が割れた場所から花火を打ち上げる。
## 段階（Omikuji.Tier）が上がるほど花火の数・粒の数・広がりが増える。
## 上限であたったとき（GRAND）は画面いっぱいに打ち上げ、光と金の紙吹雪も出す。

const FONT = preload("res://fonts/MPLUSRounded1c-Bold.ttf")

const GRAVITY := 160.0
const DRAG := 1.6
const PALETTE := [Color("ff5d73"), Color("ffd43b"), Color("5ad1ff"), Color("8cf27a"), Color("c78bff"), Color("ffa24c")]
const GOLD := Color("ffd76a")

## 段階ごとの設定: 花火の数、1つの粒の数、粒の速さ、打ち上げ終わるまでの時間、文字の大きさ
const TIERS := {
	1: {"bursts": 1, "count": 22, "speed": 230.0, "spread": 0.0, "span": 0.0, "text": "あたり！", "size": 30},
	2: {"bursts": 3, "count": 28, "speed": 280.0, "spread": 170.0, "span": 0.5, "text": "あたり！", "size": 38},
	3: {"bursts": 6, "count": 36, "speed": 330.0, "spread": 260.0, "span": 1.0, "text": "あたり！！", "size": 46},
	4: {"bursts": 14, "count": 48, "speed": 380.0, "spread": 0.0, "span": 2.0, "text": "大あたり！！", "size": 60},
}

## 粒: {p, v, color, life, max, size, kind}。kind 0=花火の粒 1=金の紙吹雪 2=風船のかけら
var _sparks: Array[Dictionary] = []
## これから打ち上げる花火: {at（残り秒）, pos, count, speed, colors, ring}
var _queue: Array[Dictionary] = []
var _flash := 0.0
var _text := ""
var _text_size := 30
var _text_pos := Vector2.ZERO
var _text_t := -1.0
var _grand := false
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## origin で風船を割り、段階 tier の花火を始める。吹き出しを出すまで待つ秒数を返す
func start(tier: int, origin: Vector2, balloon_color: Color, area: Rect2) -> float:
	var cfg: Dictionary = TIERS[clampi(tier, 1, 4)]
	_grand = tier >= 4
	# 風船のかけら
	for i in 14:
		var a := _rng.randf() * TAU
		_add(origin, Vector2.from_angle(a) * _rng.randf_range(120, 260), balloon_color, _rng.randf_range(0.4, 0.7), 5.0, 2)
	var n: int = cfg["bursts"]
	for i in n:
		var pos := origin
		if i > 0:
			if _grand:
				pos = Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
			else:
				var spread: float = cfg["spread"]
				pos = origin + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread * 1.2, spread * 0.2))
				pos = pos.clamp(area.position, area.end)
		var colors: Array[Color] = []
		for k in mini(1 + tier, 3):
			colors.append(PALETTE[_rng.randi_range(0, PALETTE.size() - 1)])
		if _grand and i % 3 == 0:
			colors = [GOLD]
		_queue.append({"at": cfg["span"] * i / maxf(1.0, n - 1.0), "pos": pos, "count": cfg["count"],
			"speed": cfg["speed"] * _rng.randf_range(0.85, 1.1), "colors": colors, "ring": tier >= 3 and i % 2 == 0})
	if _grand:
		# 最後にひときわ大きい金の花火
		_queue.append({"at": cfg["span"] + 0.3, "pos": area.get_center(), "count": 90, "speed": 520.0, "colors": [GOLD, Color.WHITE], "ring": true})
	_flash = [0.0, 0.25, 0.4, 0.55, 0.9][tier]
	_text = cfg["text"]
	_text_size = cfg["size"]
	_text_pos = Vector2(area.get_center().x, clampf(origin.y - 120, area.position.y + 60, area.end.y))
	if _grand:
		_text_pos = area.get_center() + Vector2(0, -40)
	_text_t = 0.0
	return [0.0, 1.0, 1.4, 1.9, 3.2][tier]


func is_running() -> bool:
	return not _sparks.is_empty() or not _queue.is_empty()


func _add(p: Vector2, v: Vector2, color: Color, life: float, size: float, kind: int) -> void:
	_sparks.append({"p": p, "v": v, "color": color, "life": life, "max": life, "size": size, "kind": kind})


func _burst(b: Dictionary) -> void:
	var count: int = b["count"]
	var speed: float = b["speed"]
	var colors: Array = b["colors"]
	for i in count:
		var a := TAU * i / count + _rng.randf_range(-0.08, 0.08)
		var v := Vector2.from_angle(a) * speed * _rng.randf_range(0.75, 1.0)
		_add(b["pos"], v, colors[i % colors.size()], _rng.randf_range(0.9, 1.3), 4.8, 0)
	if b["ring"]:
		# 内側にもう一回り小さい輪
		for i in count / 2:
			var a := TAU * i / (count / 2)
			_add(b["pos"], Vector2.from_angle(a) * speed * 0.5, Color.WHITE, 0.8, 3.4, 0)
	if _grand:
		for i in 10:
			_add(b["pos"], Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-220, -40)), GOLD, _rng.randf_range(1.6, 2.4), 4.0, 1)
	_flash = maxf(_flash, 0.12 if not _grand else 0.25)


func _process(delta: float) -> void:
	_t += delta
	for b in _queue.duplicate():
		b["at"] -= delta
		if b["at"] <= 0.0:
			_queue.erase(b)
			_burst(b)
	var alive: Array[Dictionary] = []
	for s in _sparks:
		s["life"] -= delta
		if s["life"] <= 0.0:
			continue
		var drag := DRAG * (2.5 if s["kind"] == 1 else 1.0)
		s["v"] = s["v"] * exp(-drag * delta) + Vector2(0, GRAVITY * (0.4 if s["kind"] == 1 else 1.0) * delta)
		s["p"] += s["v"] * delta
		alive.append(s)
	_sparks = alive
	_flash = maxf(0.0, _flash - delta * 1.5)
	if _text_t >= 0.0:
		_text_t += delta
		if _text_t > (3.6 if _grand else 2.2):
			_text_t = -1.0
	queue_redraw()


func _draw() -> void:
	if _flash > 0.0:
		var c := Color(1, 0.97, 0.85, _flash * 0.5)
		draw_rect(Rect2(-2000, -2000, 4000, 4000), c)
	for s in _sparks:
		var k: float = s["life"] / s["max"]
		var color: Color = s["color"]
		match s["kind"]:
			0:
				# 尾を引く粒。消えぎわはちかちか
				var tail: Vector2 = s["p"] - s["v"] * 0.06
				var a := k if k > 0.3 else k * (0.5 + 0.5 * sin(_t * 40.0 + s["p"].x))
				draw_line(tail, s["p"], Color(color, a * 0.6), s["size"] * 0.8, true)
				draw_circle(s["p"], s["size"] * (0.6 + 0.4 * k), Color(color.lightened(0.3), a))
			1:
				# 金の紙吹雪（ひらひら回る）
				var w: float = s["size"] * absf(sin(_t * 9.0 + s["p"].y * 0.05))
				draw_rect(Rect2(s["p"] - Vector2(w, s["size"]) / 2, Vector2(w + 1, s["size"])), Color(color, minf(1.0, k * 2.0)))
			2:
				draw_circle(s["p"], s["size"] * k, Color(color, k))
	if _text_t >= 0.0:
		_draw_text()


func _draw_text() -> void:
	var pop := minf(1.0, _text_t / 0.25)
	var scale := 0.4 + 0.6 * pop + sin(minf(_text_t, 0.5) * TAU) * 0.08
	var end := 3.6 if _grand else 2.2
	var alpha := clampf((end - _text_t) / 0.4, 0.0, 1.0)
	var size := int(_text_size * scale)
	var w := FONT.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := _text_pos + Vector2(-w / 2, size * 0.36)
	draw_string_outline(FONT, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(6, size / 5), Color(0.35, 0.12, 0.1, alpha))
	if not _grand:
		draw_string(FONT, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(Color("fff3b0"), alpha))
		return
	# 大あたりは1文字ずつ虹色に
	var x := 0.0
	for i in _text.length():
		var ch := _text[i]
		var hue := fmod(_t * 0.5 + i * 0.12, 1.0)
		draw_string(FONT, at + Vector2(x, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.from_hsv(hue, 0.45, 1.0, alpha))
		x += FONT.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
