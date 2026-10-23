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
## きのみの絵を描く正方形の一辺（倍率1のきのみが葉まで収まる大きさ）
const BERRY_TEX := 48

## 粒の種類
enum Kind { SPARK, CONFETTI, SHARD, BERRY }
## 粒。数千個になるので、1つずつの辞書ではなく種類ごとにまとめた配列に持つ（位置・速さ・色・残り秒・寿命・大きさ・種類）
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _color := PackedColorArray()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _size := PackedFloat32Array()
var _kind := PackedByteArray()
## 落ちてくるきのみの絵（_ready で一度だけ描いておき、毎フレームは貼るだけにする）
var _berry_tex: Texture2D
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
	_berry_tex = _render_berry()
	set_process(false)


## きのみの絵を一度だけ小さな画面に描いて、貼り付け用の絵にする
func _render_berry() -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(BERRY_TEX, BERRY_TEX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var art := Node2D.new()
	art.draw.connect(func() -> void: ItemArt.draw_item(art, "berry", Vector2(BERRY_TEX / 2.0, BERRY_TEX / 2.0 + 3.0)))
	vp.add_child(art)
	add_child(vp)
	return vp.get_texture()


## origin で風船を割り、段階 tier の花火を始める。吹き出しを出すまで待つ秒数を返す
func start(tier: int, origin: Vector2, balloon_color: Color, area: Rect2) -> float:
	var cfg: Dictionary = TIERS[clampi(tier, 1, 4)]
	_grand = tier >= 4
	set_process(true)
	# 風船のかけら
	for i in 14:
		var a := _rng.randf() * TAU
		_add(origin, Vector2.from_angle(a) * _rng.randf_range(120, 260), balloon_color, _rng.randf_range(0.4, 0.7), 5.0, Kind.SHARD)
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
			_add(p, Vector2(_rng.randf_range(-40, 40), _rng.randf_range(120, 360)), GOLD, GRAND_SEC + 1.0, _rng.randf_range(0.7, 1.15), Kind.BERRY)
	return [0.0, 1.0, 1.4, 1.9, GRAND_SEC][tier]


func is_running() -> bool:
	return not _pos.is_empty() or not _queue.is_empty() or not _rings.is_empty() or _grand_t >= 0.0 or _flash > 0.0


func spark_count() -> int:
	return _pos.size()


func _add(p: Vector2, v: Vector2, color: Color, life: float, size: float, kind: int) -> void:
	_pos.append(p)
	_vel.append(v)
	_color.append(color)
	_life.append(life)
	_max.append(life)
	_size.append(size)
	_kind.append(kind)


func _burst(b: Dictionary) -> void:
	var count: int = b["count"]
	var speed: float = b["speed"]
	var colors: Array = b["colors"]
	for i in count:
		var a := TAU * i / count + _rng.randf_range(-0.08, 0.08)
		var v := Vector2.from_angle(a) * speed * _rng.randf_range(0.75, 1.0)
		_add(b["pos"], v, colors[i % colors.size()], _rng.randf_range(0.9, 1.3), 4.8, Kind.SPARK)
	if b["ring"]:
		# 内側にもう一回り小さい輪
		for i in count / 2:
			var a := TAU * i / (count / 2)
			_add(b["pos"], Vector2.from_angle(a) * speed * 0.5, Color.WHITE, 0.8, 3.4, Kind.SPARK)
	if _grand:
		for i in 16:
			_add(b["pos"], Vector2(_rng.randf_range(-160, 160), _rng.randf_range(-280, -40)), GOLD, _rng.randf_range(1.6, 2.4), 5.0, Kind.CONFETTI)
		_rings.append({"p": b["pos"], "r": 10.0, "life": 0.6, "max": 0.6, "color": b["colors"][0]})
	_flash = maxf(_flash, 0.12 if not _grand else 0.5)


func _process(delta: float) -> void:
	_t += delta
	for b in _queue.duplicate():
		b["at"] -= delta
		if b["at"] <= 0.0:
			_queue.erase(b)
			_burst(b)
	_step_sparks(delta)
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
	if not is_running():
		set_process(false)


## 粒を動かす。消えた粒は配列の後ろの粒で埋めて詰める（順番は気にしない）
func _step_sparks(delta: float) -> void:
	var drag := exp(-DRAG * delta)
	var drag_confetti := exp(-DRAG * 2.5 * delta)
	var fall := Vector2(0, GRAVITY * delta)
	var n := _pos.size()
	var i := 0
	while i < n:
		_life[i] -= delta
		if _life[i] <= 0.0:
			n -= 1
			_pos[i] = _pos[n]
			_vel[i] = _vel[n]
			_color[i] = _color[n]
			_life[i] = _life[n]
			_max[i] = _max[n]
			_size[i] = _size[n]
			_kind[i] = _kind[n]
			continue
		match _kind[i]:
			Kind.BERRY:
				# きのみは空気抵抗なしでまっすぐ落ちる
				_vel[i] += fall * 0.6
			Kind.CONFETTI:
				_vel[i] = _vel[i] * drag_confetti + fall * 0.4
			_:
				_vel[i] = _vel[i] * drag + fall
		_pos[i] += _vel[i] * delta
		i += 1
	if n < _pos.size():
		for arr in [_pos, _vel, _color, _life, _max, _size, _kind]:
			arr.resize(n)


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
	_draw_sparks()


## 粒をまとめて描く。花火の尾・頭と紙吹雪は種類ごとに線の束1回で描き、描く回数を減らす
func _draw_sparks() -> void:
	var tails := PackedVector2Array()
	var tail_colors := PackedColorArray()
	var heads := PackedVector2Array()
	var head_colors := PackedColorArray()
	var confetti := PackedVector2Array()
	var confetti_colors := PackedColorArray()
	var berries: Array[int] = []
	for i in _pos.size():
		var k := _life[i] / _max[i]
		var p := _pos[i]
		var color := _color[i]
		match _kind[i]:
			Kind.SPARK:
				# 尾を引く粒。消えぎわはちかちか
				var a := k if k > 0.3 else k * (0.5 + 0.5 * sin(_t * 40.0 + p.x))
				tails.append(p - _vel[i] * 0.06)
				tails.append(p)
				tail_colors.append(Color(color, a * 0.6))
				var d := _vel[i].normalized() * _size[i] * (0.3 + 0.2 * k)
				heads.append(p - d)
				heads.append(p + d)
				head_colors.append(Color(color.lightened(0.3), a))
			Kind.CONFETTI:
				# 金の紙吹雪（ひらひら回るよう横幅を変える）
				var w := _size[i] * absf(sin(_t * 9.0 + p.y * 0.05)) / 2 + 0.5
				confetti.append(p - Vector2(w, 0))
				confetti.append(p + Vector2(w, 0))
				confetti_colors.append(Color(color, minf(1.0, k * 2.0)))
			Kind.SHARD:
				draw_circle(p, _size[i] * k, Color(color, k))
			Kind.BERRY:
				berries.append(i)
	if not tails.is_empty():
		draw_multiline_colors(tails, tail_colors, 3.4)
		draw_multiline_colors(heads, head_colors, 6.0)
	if not confetti.is_empty():
		draw_multiline_colors(confetti, confetti_colors, 5.0)
	for i in berries:
		_draw_berry(_pos[i], _size[i])
	draw_set_transform(Vector2.ZERO)


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


## 落ちてくるきのみ（くるくる回る）。絵は _ready で描いておいたものを貼る
func _draw_berry(p: Vector2, scale: float) -> void:
	draw_set_transform(p, _t * 4.0 + p.x * 0.05, Vector2(scale, scale))
	draw_texture(_berry_tex, -Vector2(BERRY_TEX, BERRY_TEX) / 2)
