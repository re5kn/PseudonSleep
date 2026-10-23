extends Node2D
## おみくじの風船。position は地面の位置（糸の根元）。タップすると設定欄を開く。
## 無効のときは地面に接地し、有効のときは糸を張って宙に浮く。
## 連続はずれの上限に対するはずれ回数の割合で膨らみ（上限でもとの5倍）、カウントダウンの数（上限＋1−連続はずれ）を風船に書く。

const ItemArt = preload("res://scripts/item_art.gd")
const FONT = preload("res://fonts/MPLUSRounded1c-Bold.ttf")

const RX := 16.0
const RY := 19.0
## 上限のときの大きさ（もとの何倍か）
const MAX_SCALE := 5.0
## 浮いているときの糸の長さ
const FLOAT_HEIGHT := 64.0
## 割れる直前に膨らむとき、倍率が1増えるごとに内側（左）へ寄せる量（3倍で画面の中央に来る）
const OVER_SHIFT := 112.0
const FONT_SIZE := 17.0
const LINE := Color("0d2738")
const RUBBER := Color("ff7f9e")
const RUBBER_FULL := Color("f2354f")
const STRING := Color("8a7660")

## カウントダウンの数（上限＋1−連続はずれ）
var count := 0
## 上限に対する割合（0〜1）。表示はなめらかに追いかける
var ratio := 0.0
## 宙に浮いているか（おみくじが有効か）
var floating := false
## あたりで割れて消えているあいだ
var popped := false

var _ratio_shown := 0.0
var _lift := 0.0
var _appear := 1.0
## 上限のあたりで割れる前にさらに膨らませる倍率（ふだんは1）
var _over := 1.0
var _boing := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	_ratio_shown = lerpf(_ratio_shown, ratio, 1.0 - exp(-delta * 6.0))
	_lift = move_toward(_lift, 1.0 if floating else 0.0, delta * 2.5)
	_boing = maxf(0.0, _boing - delta * 1.6)
	queue_redraw()


## カウントダウンの数と割合を入れる。数が変わったときはぷるんと揺らす
func set_state(n: int, r: float) -> void:
	if n != count and not popped:
		_boing = 1.0
	count = n
	ratio = r


## あたりで割る（花火は main 側で出す）
func pop() -> void:
	popped = true


## 割れたあとの新しい風船。しぼんだ状態からふくらんで出てくる
func respawn(n: int, r: float) -> void:
	popped = false
	_over = 1.0
	count = n
	ratio = r
	_ratio_shown = r
	_appear = 0.0
	create_tween().tween_property(self, "_appear", 1.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## ゴムの色。上限に近いほど濃い赤
func body_color() -> Color:
	return RUBBER.lerp(RUBBER_FULL, _ratio_shown)


## 割れる直前に sec 秒かけて scale 倍まで膨らませる（上限のあたり）
func overinflate(scale: float, sec: float) -> void:
	create_tween().tween_property(self, "_over", scale, sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func scale_factor() -> float:
	return (1.0 + (MAX_SCALE - 1.0) * _ratio_shown) * _appear * _over


## 糸の結び目（風船の下端）の位置
func knot() -> Vector2:
	var ground := Vector2(0, -1)
	var up := Vector2(sin(_t * 1.3) * 6.0, -FLOAT_HEIGHT + sin(_t * 2.1) * 5.0)
	# 割れる直前に膨らむときは、画面の右端からはみ出さないよう内側へ寄せる（糸も一緒に）
	return ground.lerp(up, _ease(_lift)) + Vector2(-OVER_SHIFT * (_over - 1.0), 0)


## 風船の中心（フィールド上の位置）
func center() -> Vector2:
	return position + _body_center()


## 風船のいちばん上の高さ（フィールド上）
func top_y() -> float:
	return center().y - RY * scale_factor()


func hit(p: Vector2) -> bool:
	var local := p - position
	var s := scale_factor()
	var c := _body_center()
	var body := Vector2((local.x - c.x) / (RX * s + 14), (local.y - c.y) / (RY * s + 14)).length() <= 1.0
	var tag := Rect2(_tag_pos() - Vector2(56, 24), Vector2(112, 48)).has_point(local)
	var root := Rect2(-24, -FLOAT_HEIGHT - 10, 48, FLOAT_HEIGHT + 20).has_point(local)
	return body or tag or root


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _body_center() -> Vector2:
	var s := scale_factor()
	var k := knot()
	# 割れる直前に膨らんでいるあいだは、張りつめてぷるぷる震える
	var tremble := Vector2(sin(_t * 61.0), cos(_t * 53.0)) * 5.0 * (_over - 1.0)
	# 地面ではやや傾いて転がっている
	return k + Vector2(4.0 * (1.0 - _lift), -RY * s - 3.0 * s) + tremble


func _tag_pos() -> Vector2:
	return _body_center() + Vector2(0, -RY * scale_factor() - 32 + sin(_t * 3.0) * 4.0)


func _draw() -> void:
	var s := scale_factor()
	var k := knot()
	var lift := _ease(_lift)
	# 影は浮くほど小さく薄く
	var shadow_r := maxf(RX * s, 10.0) * (1.0 - 0.4 * lift)
	draw_colored_polygon(ItemArt.ellipse(Vector2(0, 4), shadow_r, shadow_r * 0.22), Color(0, 0, 0, 0.18 - 0.08 * lift))
	_draw_string(k, lift)
	# 地面の重り（浮いているときに糸をつなぐ杭）
	var peg := PackedVector2Array([Vector2(-7, 4), Vector2(7, 4), Vector2(5, -6), Vector2(-5, -6)])
	draw_colored_polygon(peg, Color("b38a55"))
	ItemArt.outline(self, peg, LINE, 2.0)
	if popped or s <= 0.01:
		return
	_draw_body(s)
	ItemArt.name_tag(self, _tag_pos(), "おみくじ", FONT)


## 糸。浮いているときは結び目から杭まで、地面では横にたるんで寝ている
func _draw_string(k: Vector2, lift: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		var floating_pt := k.lerp(Vector2(0, -4), t) + Vector2(sin(t * PI * 2.0 + _t * 2.0) * 4.0 * (1.0 - t), 0)
		var lying_pt := Vector2(lerpf(k.x, 34.0, t), -2.0 + sin(t * PI * 2.5) * 3.0)
		pts.append(lying_pt.lerp(floating_pt, lift))
	draw_polyline(pts, STRING, 2.0, true)


func _draw_body(s: float) -> void:
	var c := _body_center()
	# 割合が増えたときのぷるん（横に広がって縦に縮む）
	var wobble := sin(_boing * PI * 4.0) * _boing * 0.08
	var rx := RX * s * (1.0 + wobble)
	var ry := RY * s * (1.0 - wobble)
	var tilt := (1.0 - _lift) * 0.35 + sin(_t * 1.3) * 0.05 * _lift
	# 下がすぼまった卵形
	var body := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40
		var y := sin(a)
		var squeeze := 1.0 - 0.12 * maxf(0.0, y)
		body.append(c + Vector2(cos(a) * rx * squeeze, y * ry).rotated(tilt))
	var color := body_color()
	draw_colored_polygon(body, color)
	# 下側の影と、左上のつや
	var shade := PackedVector2Array()
	for i in 21:
		var a := PI * 0.1 + PI * 0.8 * i / 20
		shade.append(c + Vector2(cos(a) * rx * 0.86, sin(a) * ry * 0.92).rotated(tilt))
	shade.append(c + Vector2(0, ry * 0.35).rotated(tilt))
	draw_colored_polygon(shade, color.darkened(0.12))
	ItemArt.outline(self, body, LINE, 2.0 + s * 0.4)
	draw_colored_polygon(ItemArt.ellipse(c + Vector2(-rx * 0.42, -ry * 0.48).rotated(tilt), rx * 0.2, ry * 0.26), Color(1, 1, 1, 0.55))
	draw_circle(c + Vector2(-rx * 0.2, -ry * 0.72).rotated(tilt), maxf(1.5, rx * 0.06), Color(1, 1, 1, 0.7))
	# 結び目
	var bottom := c + Vector2(0, ry).rotated(tilt)
	var kn := PackedVector2Array([bottom + Vector2(-4, 6).rotated(tilt), bottom + Vector2(4, 6).rotated(tilt), bottom + Vector2(0, -1).rotated(tilt)])
	draw_colored_polygon(kn, color.darkened(0.2))
	ItemArt.outline(self, kn, LINE, 1.6)
	# はずれ回数。風船と一緒に膨らむ
	var size := int(round(FONT_SIZE * s))
	var text := str(count)
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := c + Vector2(-w / 2, size * 0.36)
	draw_string_outline(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, int(size * 0.16)), LINE)
	draw_string(FONT, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
