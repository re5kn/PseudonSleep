extends Control
## 回数の確率分布の棒グラフ。横軸が回数、縦軸が確率質量。
## 実際の回数の棒を色を変えて示し、期待値の位置に縦の破線を引く。

const Dist = preload("res://scripts/dist.gd")

## 棒の数がこれを超えるときは、何回分かずつまとめて1本にする
const MAX_BARS := 60
## 表示範囲の外に残す確率（両端それぞれ）
const TAIL := 0.0005
const PAD_LEFT := 64.0
const PAD_RIGHT := 12.0
## 右に理論上の分布の目盛り（%）を出すときの右の余白
const PAD_RIGHT_REF := 52.0
const PAD_TOP := 12.0
const PAD_BOTTOM := 44.0
const BAR_COLOR := Color("f2b56b")
## 現時点の回数の棒（背景の赤・緑・青、期待値の青い破線と重ならない紫）
const ACTUAL_COLOR := Color("8a4fb8")
const MEAN_COLOR := Color("4a78c2")
## 期待値まわりの範囲（CENTRAL の確率で入る回数）の背景
const BAND_COLOR := Color("d6e6fa")
const CENTRAL := 0.7
## 端の背景。[下位の確率の位置から, 上位の確率の位置まで, 色]（下位は赤系、上位は緑系）
## 下位5%・下位10%（期待値まわりの範囲の手前、15%まで）、上位10%（85%から）・上位5%
const TAIL_BANDS := [
	[0.0, 0.05, Color("f4c2c2")],
	[0.05, 0.15, Color("fae0e0")],
	[0.85, 0.95, Color("dcefd6")],
	[0.95, 1.0, Color("b9dfae")],
]
## 目立たせる回数の棒（連続不発の上限など）
const ACCENT_COLOR := Color("d9534f")
## 理論上の平均の破線（ref_mean）と理論上の分布の実線（ref_pmf）
const REF_COLOR := Color("3a9a5b")
const AXIS_COLOR := Color("8a7660")
const TEXT_COLOR := Color("5a4632")
const FONT_SIZE := 14
## 縦軸の目盛りの区切り数（上端が 1, 2, 2.5, 5 × 10^n なので、きりのよい値になる）
const Y_TICKS := 5

var dist: Dist
var actual := 0
var mean := 0.0
## 期待値まわり・下位・上位の背景を塗るか
var bands := true
## 棒をまとめずに並べる上限の本数
var max_bars := MAX_BARS
var x_title := "回数"
## ACCENT_COLOR で塗る回数（−1 ならなし）。実際の回数の棒の色が優先
var accent := -1
## 0 より大きければ、分布を件数 count_total の集計とみなして縦軸を件数で表す
var count_total := 0
## 横軸に必ず入れる回数の範囲（x > y ならなし）
var x_range := Vector2i(0, -1)
## 分布の平均の破線を引くか
var show_mean := true
## 0 以上なら、その位置に理論上の平均の破線を REF_COLOR で引く
var ref_mean := -1.0
## 空でなければ、理論上の分布（要素 i が「i 回」の確率。dist と同じ割合の単位）を REF_COLOR の実線で重ねる
var ref_pmf := PackedFloat64Array()
## true なら ref_pmf を確率のまま、右の目盛り（%）で描く（棒とは別の目盛り）
var ref_axis := false


func show_dist(d: Dist, actual_count: int) -> void:
	dist = d
	actual = actual_count
	mean = d.mean()
	queue_redraw()


func _draw() -> void:
	if dist == null:
		return
	var font := get_theme_default_font()
	var span := dist.span(TAIL)
	var first := mini(span.x, actual)
	var last := maxi(span.y, actual)
	if x_range.x <= x_range.y:
		first = mini(first, x_range.x)
		last = maxi(last, x_range.y)
	var width := ceili(float(last - first + 1) / max_bars)
	# まとめる単位の倍数から始めて、棒の区切りをそろえる
	first -= posmod(first, width)
	var bars := (last - first) / width + 1
	var masses := PackedFloat64Array()
	masses.resize(bars)
	for b in bars:
		for x in range(first + b * width, first + (b + 1) * width):
			masses[b] += dist.mass(x)
	var refs := PackedFloat64Array()
	if not ref_pmf.is_empty():
		refs.resize(bars)
		for b in bars:
			for x in range(first + b * width, first + (b + 1) * width):
				if x >= 0 and x < ref_pmf.size():
					refs[b] += ref_pmf[x]
	var top := 0.0
	for m in masses:
		top = maxf(top, m)
	var ref_max := 0.0
	for m in refs:
		ref_max = maxf(ref_max, m)
	if not ref_axis:
		top = maxf(top, ref_max)
	var y_max := _nice_ceil(top)
	if count_total > 0:
		# 件数の目盛りが整数になるよう、上端は Y_TICKS 以上のきりのよい件数にする
		y_max = maxf(_nice_ceil(top * count_total), Y_TICKS) / count_total

	var pad_right := PAD_RIGHT_REF if ref_axis and not refs.is_empty() else PAD_RIGHT
	var plot := Rect2(PAD_LEFT, PAD_TOP, size.x - PAD_LEFT - pad_right, size.y - PAD_TOP - PAD_BOTTOM)
	# 実線の目盛りの上端（右の目盛りなら確率の、そうでなければ棒と同じ上端）
	var ref_top := _nice_ceil(ref_max) if ref_axis else y_max
	var bar_w := plot.size.x / bars

	if bands:
		_draw_bands(plot, first, width, bar_w)

	# 縦軸（確率質量、%）の目盛り
	for i in Y_TICKS + 1:
		var v := y_max * i / float(Y_TICKS)
		var y := plot.end.y - plot.size.y * i / float(Y_TICKS)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(AXIS_COLOR, 0.25), 1.0)
		var label := "%d件" % roundi(v * count_total) if count_total > 0 else _percent(v)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(plot.position.x - tw - 6, y + FONT_SIZE * 0.35), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		if ref_axis and not refs.is_empty():
			draw_string(font, Vector2(plot.end.x + 6, y + FONT_SIZE * 0.35), _percent(ref_top * i / float(Y_TICKS)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, REF_COLOR)

	for b in bars:
		var h := plot.size.y * masses[b] / y_max if y_max > 0.0 else 0.0
		var lo := first + b * width
		var has_actual := actual >= lo and actual < lo + width
		var has_accent := accent >= lo and accent < lo + width
		var r := Rect2(plot.position.x + b * bar_w + 1, plot.end.y - h, maxf(1.0, bar_w - 2), h)
		if has_actual and h < 3.0:
			# 高さ0でも実際の回数の位置がわかるよう、軸の上に短く出す
			r = Rect2(r.position.x, plot.end.y - 3.0, r.size.x, 3.0)
		draw_rect(r, ACTUAL_COLOR if has_actual else ACCENT_COLOR if has_accent else BAR_COLOR)

	# 理論上の分布の実線（棒の中心を結ぶ）
	if not refs.is_empty() and ref_top > 0.0:
		var pts := PackedVector2Array()
		for b in bars:
			pts.append(Vector2(plot.position.x + (b + 0.5) * bar_w, plot.end.y - plot.size.y * minf(refs[b] / ref_top, 1.0)))
		draw_polyline(pts, REF_COLOR, 2.5, true)

	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, AXIS_COLOR, 2.0)
	draw_line(plot.position, Vector2(plot.position.x, plot.end.y), AXIS_COLOR, 2.0)

	# 期待値の位置（棒の中心が回数にあたる）
	if show_mean:
		var mx := plot.position.x + ((mean - first) / width + 0.5) * bar_w
		draw_dashed_line(Vector2(mx, plot.position.y), Vector2(mx, plot.end.y), MEAN_COLOR, 4.0, 6.0)
	if ref_mean >= 0.0:
		var rx := plot.position.x + ((ref_mean - first) / width + 0.5) * bar_w
		draw_dashed_line(Vector2(rx, plot.position.y), Vector2(rx, plot.end.y), REF_COLOR, 4.0, 6.0)

	# 横軸（回数）の目盛り。棒が多いときは 1, 2, 5 × 10^n 本おきに間引き、きりのよい回数に置く
	var step := roundi(_nice_ceil(ceilf(bars / 8.0)))
	for b in bars:
		if posmod(first / width + b, step) != 0:
			continue
		var label := str(first + b * width)
		if width > 1:
			label += "〜"
		var cx := plot.position.x + (b + 0.5) * bar_w
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(cx - tw / 2, plot.end.y + FONT_SIZE + 6), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	var xw := font.get_string_size(x_title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(plot.end.x - xw, size.y - 4), x_title,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)


## 期待値まわり70%と下位・上位の範囲の背景
func _draw_bands(plot: Rect2, first: int, width: int, bar_w: float) -> void:
	# 期待値まわり70%の範囲の背景。端は小数なので棒の途中に来る（棒をまとめていても回数の位置で塗る）
	var band := dist.central(CENTRAL)
	var bx0 := plot.position.x + (band.x - first + 0.5) / width * bar_w
	var bx1 := plot.position.x + (band.y - first + 0.5) / width * bar_w
	draw_rect(Rect2(bx0, plot.position.y, bx1 - bx0, plot.size.y), BAND_COLOR)
	# 下位5%・10%、上位10%・5%の背景（グラフの端より外は塗らない）。期待値まわりの範囲とすき間なく並ぶ
	for t in TAIL_BANDS:
		var a := plot.position.x + (dist.quantile(t[0]) - first + 0.5) / width * bar_w
		var z := plot.position.x + (dist.quantile(t[1]) - first + 0.5) / width * bar_w
		a = clampf(a, plot.position.x, plot.end.x)
		z = clampf(z, plot.position.x, plot.end.x)
		draw_rect(Rect2(a, plot.position.y, z - a, plot.size.y), t[2])


## 目盛りの上端（1, 2, 2.5, 5 × 10^n のうち v 以上の最小）
static func _nice_ceil(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var e := pow(10.0, floorf(log(v) / log(10.0)))
	for m in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if m * e >= v - 1e-12:
			return m * e
	return 10.0 * e


static func _percent(v: float) -> String:
	var pct := v * 100.0
	if absf(pct - roundf(pct)) < 1e-6:
		return "%d%%" % roundi(pct)
	return "%.1f%%" % pct
