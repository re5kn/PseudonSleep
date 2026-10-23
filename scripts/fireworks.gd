extends Node2D

const ItemArt = preload("res://scripts/item_art.gd")
## おみくじのあたりの演出。風船が割れた場所から花火を打ち上げる。
## 段階（Omikuji.Tier）が上がるほど花火の数・粒の数・広がりが増える。
## 上限であたったとき（GRAND）は画面が見えなくなるくらいに、回る後光・光の波・きのみの雨・画面の揺れを重ねる。

const GRAVITY := 160.0
const DRAG := 1.6
const PALETTE := [Color("ff5d73"), Color("ffd43b"), Color("5ad1ff"), Color("8cf27a"), Color("c78bff"), Color("ffa24c")]
const GOLD := Color("ffd76a")

## 段階ごとの設定: 花火の数、1つの粒の数、粒の速さ、打ち上げ終わるまでの時間
const TIERS := {
	1: {"bursts": 1, "count": 22, "speed": 230.0, "spread": 0.0, "span": 0.0},
	2: {"bursts": 3, "count": 28, "speed": 280.0, "spread": 170.0, "span": 0.5},
	3: {"bursts": 6, "count": 36, "speed": 330.0, "spread": 260.0, "span": 1.0},
	4: {"bursts": 30, "count": 60, "speed": 460.0, "spread": 0.0, "span": 2.6},
}
## 大あたりの長さ（後光やきのみの雨が続く秒数）
const GRAND_SEC := 3.6
const GRAND_RAYS := 28
## 上から降らすきのみの数
const BERRIES := 320

## 粒: {p, v, color, life, max, size, kind}。kind 0=花火の粒 1=金の紙吹雪 2=風船のかけら 3=きのみ
var _sparks: Array[Dictionary] = []
## これから打ち上げる花火: {at（残り秒）, pos, count, speed, colors, ring}
var _queue: Array[Dictionary] = []
var _flash := 0.0
var _grand := false
## 大あたりの経過秒（-1 で止まっている）と、中心
var _grand_t := -1.0
var _center := Vector2.ZERO
## 光の波: {p, r, life, max, color}
var _rings: Array[Dictionary] = []
## 揺らすノード（パチモンや風船の層）。大あたりのあいだだけ揺らす
var shake_target: Node2D
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
	_flash = [0.0, 0.25, 0.4, 0.55, 1.0][tier]
	if _grand:
		_center = area.get_center()
		_grand_t = 0.0
		# 最後にひときわ大きい金の花火を2発
		for k in 2:
			_queue.append({"at": cfg["span"] + 0.2 + k * 0.35, "pos": _center, "count": 140, "speed": 760.0, "colors": [GOLD, Color.WHITE, PALETTE[k * 2]], "ring": true})
		# 上から降るきのみ（size は絵の倍率）
		for i in BERRIES:
			var p := Vector2(_rng.randf_range(area.position.x - 80, area.end.x + 80), _rng.randf_range(-900, -20))
			_add(p, Vector2(_rng.randf_range(-40, 40), _rng.randf_range(120, 360)), GOLD, GRAND_SEC + 1.0, _rng.randf_range(0.7, 1.15), 3)
	return [0.0, 1.0, 1.4, 1.9, GRAND_SEC][tier]


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
		for i in 16:
			_add(b["pos"], Vector2(_rng.randf_range(-160, 160), _rng.randf_range(-280, -40)), GOLD, _rng.randf_range(1.6, 2.4), 5.0, 1)
		_rings.append({"p": b["pos"], "r": 10.0, "life": 0.6, "max": 0.6, "color": b["colors"][0]})
	_flash = maxf(_flash, 0.12 if not _grand else 0.5)


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
		if s["kind"] == 3:
			# きのみは空気抵抗なしでまっすぐ落ちる
			s["v"] += Vector2(0, GRAVITY * 0.6 * delta)
			s["p"] += s["v"] * delta
			alive.append(s)
			continue
		var drag := DRAG * (2.5 if s["kind"] == 1 else 1.0)
		s["v"] = s["v"] * exp(-drag * delta) + Vector2(0, GRAVITY * (0.4 if s["kind"] == 1 else 1.0) * delta)
		s["p"] += s["v"] * delta
		alive.append(s)
	_sparks = alive
	_flash = maxf(0.0, _flash - delta * 1.5)
	for r in _rings:
		r["life"] -= delta
		r["r"] += delta * 900.0
	_rings = _rings.filter(func(r: Dictionary) -> bool: return r["life"] > 0.0)
	if _grand_t >= 0.0:
		_grand_t += delta
		if _grand_t > GRAND_SEC + 0.8:
			_grand_t = -1.0
	_shake()
	queue_redraw()


## 大あたりのあいだ、パチモンや風船の層をがたがた揺らす（終わりぎわは弱める）
func _shake() -> void:
	if shake_target == null:
		return
	if _grand_t < 0.0 or _grand_t > GRAND_SEC:
		shake_target.position = Vector2.ZERO
		return
	var amount := 14.0 * clampf((GRAND_SEC - _grand_t) / 1.0, 0.0, 1.0)
	shake_target.position = Vector2(_rng.randf_range(-amount, amount), _rng.randf_range(-amount, amount))


func _draw() -> void:
	if _grand_t >= 0.0:
		_draw_glory()
	if _flash > 0.0:
		var c := Color(1, 0.97, 0.85, _flash * (0.85 if _grand else 0.5))
		draw_rect(Rect2(-2000, -2000, 4000, 4000), c)
	for r in _rings:
		var k: float = r["life"] / r["max"]
		draw_arc(r["p"], r["r"], 0, TAU, 64, Color(Color.WHITE.lerp(r["color"], 0.4), k * 0.9), 6.0 + 18.0 * k, true)
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
			3:
				_draw_berry(s["p"], s["size"])


## 大あたりの後光: 中心から画面の外まで届く光の筋が回り、色が虹色に移る。真ん中は白く光る
func _draw_glory() -> void:
	var t := _grand_t
	var grow := minf(1.0, t / 0.35)
	var fade := clampf((GRAND_SEC + 0.8 - t) / 0.8, 0.0, 1.0)
	var reach := 1600.0 * grow
	for i in GRAND_RAYS:
		var a := TAU * i / GRAND_RAYS + t * 0.9
		var half := TAU / GRAND_RAYS * 0.32
		var hue := fmod(t * 0.35 + float(i) / GRAND_RAYS, 1.0)
		var color := GOLD if i % 2 == 0 else Color.from_hsv(hue, 0.5, 1.0)
		var ray := PackedVector2Array([_center, _center + Vector2.from_angle(a - half) * reach, _center + Vector2.from_angle(a + half) * reach])
		draw_colored_polygon(ray, Color(color, 0.55 * fade))
	# 脈打つ中心の光
	var pulse := 1.0 + 0.15 * sin(t * 12.0)
	for k in 4:
		draw_circle(_center, (220.0 - k * 50.0) * grow * pulse, Color(1, 0.98, 0.85, (0.18 + k * 0.18) * fade))


## 落ちてくるきのみ（くるくる回る）
func _draw_berry(p: Vector2, scale: float) -> void:
	draw_set_transform(p, _t * 4.0 + p.x * 0.05)
	ItemArt.draw_item(self, "berry", Vector2.ZERO, scale)
	draw_set_transform(Vector2.ZERO)
