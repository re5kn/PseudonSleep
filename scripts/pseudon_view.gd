extends Node2D
## パチモンの見た目（images/pseudon.png のおばけ）。所持数があれば頭上にアイコン、スキル発動時は「!」を出す。
## アイコンが出ていないとき（タップで設定パネルを開けるとき）は「…」の吹き出しを出す。
## おてつだいボーナスの数だけ、体のまわりを光の玉が回る。

const ItemArt = preload("res://scripts/item_art.gd")
const HeadMark = preload("res://scripts/head_mark.gd")
const TEXTURE = preload("res://images/pseudon.png")

const BODY_RX := 62.0
const BODY_RY := 56.0
## 画像は高さ SPRITE_HEIGHT で、体の中心より少し上に置く
const SPRITE_HEIGHT := 190.0
const SPRITE_CENTER := Vector2(0, -8)
## 頭上の印（アイコン・「…」・「!」）は画像の上端（-103）よりしっぽ込みで上に出す
const ICON_POS := Vector2(0, -152)
const ICON_RADIUS := HeadMark.ICON_RADIUS
## 手のひらのあたり（画面から見て左がパチモンの右手）。きのみは右手、食材は左手から出す
const RIGHT_HAND := Vector2(-60, 2)
## 食材は手のひらから食材Aの幅（19px）ぶん右に出す
const LEFT_HAND := Vector2(77, 6)
## 蝶ネクタイ（おやすみリボン）をつける首もと（口の下）と、羽の半分の幅・高さ。BOWTIE_SCALE 倍に縮めて描く
const BOWTIE_POS := Vector2(-3, -38)
const BOWTIE_SCALE := 0.5
const BOWTIE_HALF := Vector2(25, 13)
## おやすみリボンの段階ごとの蝶ネクタイの色（[地の色, 縁の色]）。青と金は虹色に合わせて彩度を 0.45 くらいに抑える。段階 4 は虹色なので使わない
const BOWTIE_COLORS := {
	1: [Color(0.97, 0.97, 0.95), Color(0.55, 0.55, 0.6)],
	2: [Color(0.52, 0.69, 0.95), Color(0.25, 0.35, 0.5)],
	3: [Color(0.98, 0.87, 0.54), Color(0.55, 0.46, 0.28)],
}
## 虹色の蝶ネクタイの色が1秒に一周の何割ぶん変わるかと、彩度
const RAINBOW_SPEED := 0.4
const RAINBOW_SAT := 0.45
## 結び目のブローチ（赤い宝石）の色
const BROOCH_COLOR := Color(0.86, 0.2, 0.26)
## おてつだいボーナスの光の玉が回る軌道。原子核のまわりの電子のように、玉ごとに傾きの違う楕円を回る。
## 楕円の中心（体の中心）と半径、1秒に回る角度（ラジアン）。軌道ごとに速さを少しずつ変える
const ORBIT_CENTER := Vector2(0, -8)
const ORBIT_RADIUS := Vector2(104, 30)
const ORBIT_SPEED := 1.3
const ORBIT_SPEED_STEP := 0.12
## 光の玉が通ったあとに残す軌跡の長さ（円周の1/4）と、軌跡を描く点の数
const TRAIL_ARC := PI / 2
const TRAIL_STEPS := 48
## 光の玉の芯の半径と、まわりの光の色
const ORB_RADIUS := 6.0
const ORB_GLOW := Color(1.0, 0.95, 0.6)
## 光の玉と軌跡の円を描くための白い円の画像の大きさ（ピクセル）。円を1つずつ多角形で描くと
## 描画命令が玉1個あたり50ほどに増えて重いので、この画像を色をつけて並べ、まとめて描けるようにする
const DISC_SIZE := 64

static var _disc: ImageTexture
## 色を反転した体の画像（2体目のパチモン用。最初に使うときに一度だけ作る）
static var _inverted: ImageTexture

var show_icon := false
## 設定パネルを開ける印（「…」の吹き出し）を出すか
var show_menu := false
var icon_full := false
var exclaim_count := 0
var exclaim_anim := 0.0
## おやすみリボンの段階（Params.ribbon_tier）。1 以上なら首もとに蝶ネクタイをつける
var ribbon_tier := 0
## おてつだいボーナスの数（Params.help_bonus_count）。その数だけ光の玉が体のまわりを回る
var help_bonus := 0
## 体と光の玉の色を反転して描くか（2体目のパチモン）
var inverted := false
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func show_exclaims(n: int) -> void:
	exclaim_count = n
	exclaim_anim = 0.0
	if n > 0:
		var tw := create_tween()
		tw.tween_property(self, "exclaim_anim", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hit(p: Vector2) -> bool:
	var local := p - global_position
	var body := Vector2(local.x / (BODY_RX + 12), local.y / (BODY_RY + 12)).length() <= 1.0
	var icon := (show_icon or show_menu) and local.distance_to(ICON_POS + Vector2(0, -_float_y())) <= ICON_RADIUS + 12
	return body or icon


## アイテムを出す手の位置（親ノードの座標。浮き上がりに合わせて動く）
func hand_position(id: String) -> Vector2:
	var hand := RIGHT_HAND if id == "berry" else LEFT_HAND
	return position + hand + Vector2(0, -_float_y())


## 体が浮き上がっている量（上向きが正）
func _float_y() -> float:
	return sin(_t * 1.8) * 6.0


func _draw() -> void:
	# ふわふわ浮いて、影は浮き上がるほど小さくなる。頭上のアイコンと「…」も体と一緒に動かし、間隔を一定に保つ
	var float_y := _float_y()
	var shadow_s := 1.0 - float_y / 60.0
	draw_colored_polygon(ItemArt.ellipse(Vector2(0, BODY_RY + 8), BODY_RX * 0.8 * shadow_s, 12 * shadow_s), Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2(0, -float_y), 0.0, Vector2.ONE)
	# 光の玉は奥側を体より先に、手前側を体のあとに描いて、体のまわりを回って見えるようにする
	_draw_orbs(false)
	_draw_body()
	if ribbon_tier > 0:
		draw_set_transform(Vector2(0, -float_y) + BOWTIE_POS, 0.0, Vector2.ONE * BOWTIE_SCALE)
		_draw_bowtie()
		draw_set_transform(Vector2(0, -float_y), 0.0, Vector2.ONE)
	_draw_orbs(true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_icon:
		_draw_icon(-float_y)
	elif show_menu and exclaim_count == 0:
		_draw_menu(-float_y)
	if exclaim_count > 0:
		_draw_exclaims()


func _draw_body() -> void:
	var size := Vector2(TEXTURE.get_width(), TEXTURE.get_height()) * (SPRITE_HEIGHT / TEXTURE.get_height())
	draw_texture_rect(_inverted_texture() if inverted else TEXTURE, Rect2(SPRITE_CENTER - size / 2, size), false)


## 体の画像の色（透明度はそのまま）を反転したもの
static func _inverted_texture() -> ImageTexture:
	if _inverted == null:
		var img := TEXTURE.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(1.0 - c.r, 1.0 - c.g, 1.0 - c.b, c.a))
		_inverted = ImageTexture.create_from_image(img)
	return _inverted


## 蝶ネクタイ（BOWTIE_POS を原点にした座標）。足2本・羽2枚・結び目を描き、段階 4 は虹色が流れるように変わる
func _draw_bowtie() -> void:
	var c := Vector2.ZERO
	var w := BOWTIE_HALF.x
	var h := BOWTIE_HALF.y
	var wings := []
	for side in [-1.0, 1.0]:
		# 角ばった羽の形を角切りでなめらかにして、ふっくら丸みのある羽にする
		var rough := PackedVector2Array()
		for p in [Vector2(4, -4), Vector2(w * 0.55, -h), Vector2(w, -h * 0.85), Vector2(w + 2, 0),
				Vector2(w, h * 0.85), Vector2(w * 0.55, h), Vector2(4, 4)]:
			rough.append(c + Vector2(side * p.x, p.y))
		wings.append(_smooth(rough, 3))
	# 結び目から下へ八の字に垂れる2本の足（端は燕尾に切り込む）
	var tails := []
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for p in [Vector2(-2, 3), Vector2(4, 3), Vector2(14, h + 11), Vector2(10, h + 8), Vector2(5, h + 13)]:
			pts.append(c + Vector2(side * p.x, p.y))
		tails.append(pts)
	var knot := ItemArt.rounded_rect(c, Vector2(6, 7), 5)
	if ribbon_tier >= 4:
		_draw_rainbow_bowtie(tails + wings, knot)
		return
	var fill: Color = BOWTIE_COLORS[ribbon_tier][0]
	var line: Color = BOWTIE_COLORS[ribbon_tier][1]
	for t in tails:
		draw_colored_polygon(t, fill.darkened(0.06))
		ItemArt.outline(self, t, line, 2.0)
	for i in wings.size():
		draw_colored_polygon(wings[i], fill)
		# 羽のひだ（結び目から外へ広がる影）
		var side := -1.0 if i == 0 else 1.0
		draw_line(c + Vector2(side * 7, -2), c + Vector2(side * (w - 8), -h + 6), fill.darkened(0.25), 2.0)
		draw_line(c + Vector2(side * 7, 2), c + Vector2(side * (w - 8), h - 6), fill.darkened(0.25), 2.0)
		ItemArt.outline(self, wings[i], line, 2.0)
	draw_colored_polygon(knot, fill.darkened(0.12))
	ItemArt.outline(self, knot, line, 2.0)
	_draw_brooch(c)
	if ribbon_tier == 3:
		# 金色はときどききらっと光る
		var a := clampf(sin(_t * 2.6) * 2.0 - 1.0, 0.0, 1.0)
		_draw_sparkle(c + Vector2(-w + 8, -h + 5), 7.0 * a, Color(1, 1, 0.9, a))


## parts は足と羽（描く順）。片側ずつ交互に並んでいて、左右で色相を半周ずらす
func _draw_rainbow_bowtie(parts: Array, knot: PackedVector2Array) -> void:
	var hue := fmod(_t * RAINBOW_SPEED, 1.0)
	for i in parts.size():
		var pts: PackedVector2Array = parts[i]
		var cols := PackedColorArray()
		for pt in pts:
			# 位置ごとに色相をずらして、羽の上を虹色が流れるようにする
			var shift := absf(pt.x) / BOWTIE_HALF.x * 0.3 + pt.y / BOWTIE_HALF.y * 0.12
			cols.append(Color.from_hsv(fmod(hue + (i % 2) * 0.5 + shift + 1.0, 1.0), RAINBOW_SAT, 1.0))
		draw_polygon(pts, cols)
		ItemArt.outline(self, pts, Color(1, 1, 1, 0.9), 2.0)
	draw_colored_polygon(knot, Color.from_hsv(fmod(hue + 0.25, 1.0), RAINBOW_SAT * 0.8, 1.0))
	ItemArt.outline(self, knot, Color(1, 1, 1, 0.9), 2.0)
	_draw_brooch(Vector2.ZERO)


## 結び目につける赤い宝石のブローチ。下半分を濃くして、左上に白いハイライトを入れる
func _draw_brooch(c: Vector2) -> void:
	var gem := ItemArt.ellipse(c, 5.5, 6.5)
	draw_colored_polygon(gem, BROOCH_COLOR)
	draw_colored_polygon(ItemArt.ellipse(c + Vector2(0, 2.2), 4.2, 3.6), BROOCH_COLOR.darkened(0.25))
	draw_colored_polygon(ItemArt.ellipse(c + Vector2(-1.8, -2.4), 1.8, 1.5), Color(1, 1, 1, 0.85))
	ItemArt.outline(self, gem, BROOCH_COLOR.darkened(0.55), 1.5)


## 閉じた多角形の角を切り落とす（チャイキン法）。回数を重ねるほど丸くなる
func _smooth(pts: PackedVector2Array, times: int) -> PackedVector2Array:
	for _k in times:
		var out := PackedVector2Array()
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		pts = out
	return pts


## おてつだいボーナスの光の玉。help_bonus 個の玉が、それぞれ傾きの違う別の軌道（_orbit_point）を回る。
## front なら手前側（楕円の下半分）にある軌跡と玉だけ、そうでなければ奥側だけを描く。奥ほど小さく薄くする
func _draw_orbs(front: bool) -> void:
	for i in help_bonus:
		var a := _orb_angle(i)
		# 通ったあとに円周の1/4ぶんの光の軌跡を残す。玉から離れるほど細く薄くする
		for k in range(TRAIL_STEPS, 0, -1):
			var b := a - TRAIL_ARC * k / TRAIL_STEPS
			if (sin(b) >= 0.0) != front:
				continue
			var fade := 1.0 - float(k) / TRAIL_STEPS
			var d := sin(b)
			var r := ORB_RADIUS * (0.85 + 0.25 * d) * (0.35 + 0.65 * fade)
			_disc_circle(_orbit_point(i, b), r, Color(ORB_GLOW, (0.75 + 0.25 * d) * 0.35 * fade))
	for i in help_bonus:
		var a := _orb_angle(i)
		var depth := sin(a)
		if (depth >= 0.0) != front:
			continue
		var p := _orbit_point(i, a)
		var s := 0.85 + 0.25 * depth
		var alpha := 0.75 + 0.25 * depth
		# 外側ほど薄い光を重ねて、白い芯がぼんやり光って見えるようにする
		var pulse := 1.0 + 0.12 * sin(_t * 5.0 + i * 1.7)
		for k in 4:
			_disc_circle(p, ORB_RADIUS * s * pulse * (2.6 - k * 0.45), Color(ORB_GLOW, alpha * (0.1 + k * 0.06)))
		_disc_circle(p, ORB_RADIUS * s, Color(1, 1, 0.92, alpha))
		_disc_circle(p + Vector2(-1.5, -1.5) * s, ORB_RADIUS * s * 0.45, Color(1, 1, 1, alpha))


## 中心 p・半径 r の円を、白い円の画像（_disc_texture）に color をかけて描く。
## 同じ画像の四角形は続けて描くとまとめて1回の描画になる
func _disc_circle(p: Vector2, r: float, color: Color) -> void:
	if inverted:
		# 2体目のパチモンは体と同じく光の玉と軌跡の色も反転する（透明度はそのまま）
		color = Color(1.0 - color.r, 1.0 - color.g, 1.0 - color.b, color.a)
	draw_texture_rect(_disc_texture(), Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, color)


## 白い円の画像（全インスタンスで共有し、最初に使うときに一度だけ作る）。ふちの1ピクセルだけをなめらかにする
static func _disc_texture() -> ImageTexture:
	if _disc == null:
		var img := Image.create(DISC_SIZE, DISC_SIZE, false, Image.FORMAT_RGBA8)
		var c := DISC_SIZE / 2.0
		for y in DISC_SIZE:
			for x in DISC_SIZE:
				var d := Vector2(x + 0.5 - c, y + 0.5 - c).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(c - d, 0.0, 1.0)))
		_disc = ImageTexture.create_from_image(img)
	return _disc


## i 番目の玉が軌道の上でいまいる角度
func _orb_angle(i: int) -> float:
	return _t * ORBIT_SPEED * (1.0 + ORBIT_SPEED_STEP * i) + TAU * i / help_bonus


## i 番目の軌道で角度 a の位置。横長の楕円を 180°/個数 × i だけ傾ける（sin(a) が正なら手前側）。
## 1個と2個のときは、1個目を左上から右下、2個目を右上から左下への斜めの軌道にする
func _orbit_point(i: int, a: float) -> Vector2:
	var tilt := PI * i / help_bonus
	if help_bonus <= 2:
		tilt = PI / 4 if i == 0 else -PI / 4
	return ORBIT_CENTER + Vector2(cos(a) * ORBIT_RADIUS.x, sin(a) * ORBIT_RADIUS.y).rotated(tilt)


## 4つの角があるきらめき
func _draw_sparkle(p: Vector2, r: float, color: Color) -> void:
	if r <= 0.5:
		return
	var t := r * 0.28
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, -r), p + Vector2(t, -t), p + Vector2(r, 0), p + Vector2(t, t),
		p + Vector2(0, r), p + Vector2(-t, t), p + Vector2(-r, 0), p + Vector2(-t, -t),
	]), color)


func _draw_icon(bob: float) -> void:
	HeadMark.draw_icon(self, ICON_POS + Vector2(0, bob), icon_full)


func _draw_menu(bob: float) -> void:
	HeadMark.draw_menu(self, ICON_POS + Vector2(0, bob))


func _draw_exclaims() -> void:
	HeadMark.draw_exclaims(self, Vector2(0, ICON_POS.y), exclaim_count, exclaim_anim)
