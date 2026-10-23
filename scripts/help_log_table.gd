extends Control
## おてつだい1回ごとの記録の表。ScrollContainer に入れて使い、見えている行だけ描く。
## header = true なら列の見出しだけを描く。
## パチモンをタップした時点には、おてつだいの行のあいだに色つきの「タップ」行を挟む。
## 日ごとの区切り（その日の最後の行のあと）には、その日に集めたきのみ・食材とスキルの予約数のまとめを挟む（#81）。

const ItemArt = preload("res://scripts/item_art.gd")
const Sim = preload("res://scripts/sim.gd")
const FieldClock = preload("res://scripts/field_clock.gd")
const FONT = preload("res://fonts/MPLUSRounded1c-Bold.ttf")

const ROW_H := 46.0
const FONT_SIZE := 20
const TEXT_DARK := Color("5a4632")
const TEXT_MUTED := Color("a08c74")
const STRIPE := Color(0.96, 0.9, 0.78, 0.45)
const EXCLAIM_FILL := Color("ffd93b")
const CEILING_COLOR := Color("e2483d")
## タップ前（まだストックにあるだけ）のスキルの濃さ
const RESERVED_ALPHA := 0.4
const TAP_BAND := Color("d6effa")
const TAP_COLOR := Color("2f86c4")
const DAY_BAND := Color("f1dcb4")
const DAY_COLOR := Color("8a5a2b")
## 列の左端と幅
const COL_K := Vector2(0, 48)
const COL_DAY := Vector2(58, 72)
const COL_TIME := Vector2(136, 70)
const COL_ITEM := Vector2(216, 140)
const COL_SKILL := Vector2(364, 120)

var header := false
var entries: Array[Dictionary] = []
## entries の各行が何回目のおてつだいか（タップの行は 0）
var help_numbers: PackedInt32Array = []
## 表に並べる行。{"e": entries の番号} か、日ごとのまとめの1行 {"day": n日目, "line": 0 ならきのみ、1〜 は食材枠}
var rows: Array[Dictionary] = []
## 食材枠の食材 id（枠の順）
var slot_ids: Array = []
## 日ごとのまとめ（day_summaries の結果）
var summaries := {}


func _init(is_header: bool = false) -> void:
	header = is_header
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(COL_SKILL.x + COL_SKILL.y, ROW_H)


## slots は食材枠の食材 id（枠の順）、active_slots は今解放されている枠の数。
## now_sec は今の経過秒で、その日（4:00〜翌3:59）が終わっていれば最後の日のまとめも出す
func set_log(list: Array[Dictionary], slots: Array = [], active_slots: int = 0, now_sec: float = 0.0) -> void:
	entries = list
	slot_ids = slots
	summaries = day_summaries(entries, slot_ids)
	help_numbers.resize(entries.size())
	rows.clear()
	var k := 0
	for i in entries.size():
		if not Sim.is_tap(entries[i]):
			k += 1
			help_numbers[i] = k
		else:
			help_numbers[i] = 0
		rows.append({"e": i})
		# その日の最後の行のあとにまとめを入れる
		var d := day_of(entries[i])
		var next_day: int = day_of(entries[i + 1]) if i + 1 < entries.size() \
			else FieldClock.day_and_clock(now_sec)[0]
		if next_day != d:
			for line in summary_lines(summaries[d], active_slots):
				rows.append({"day": d, "line": line})
	custom_minimum_size.y = ROW_H * maxi(1, rows.size())
	queue_redraw()


static func day_of(e: Dictionary) -> int:
	return FieldClock.day_and_clock(e["t"])[0]


## 日ごとに集めた数をまとめる。{n日目: {"berry": 個, "skill": 予約した回数, "ingredients": [枠ごとの個数]}}
## 食材は記録の食材 id から枠を引く。スキルは発動（タップ）を待たず、予約した回で数える
static func day_summaries(list: Array[Dictionary], slots: Array) -> Dictionary:
	var out := {}
	for e in list:
		var d := day_of(e)
		if not out.has(d):
			var ings: Array = []
			ings.resize(slots.size())
			ings.fill(0)
			out[d] = {"berry": 0, "skill": 0, "ingredients": ings}
		if Sim.is_tap(e) or e["id"] == "":
			continue
		var sum: Dictionary = out[d]
		var slot := slots.find(e["id"])
		if slot >= 0:
			sum["ingredients"][slot] += int(e["amount"])
		else:
			sum["berry"] += int(e["amount"])
		if int(e["skill"]) != Sim.Skill.NONE:
			sum["skill"] += 1
	return out


## まとめに出す行。0 はきのみとスキル、1〜 は食材枠（今解放されている枠か、その日に集めた枠）
static func summary_lines(sum: Dictionary, active_slots: int) -> Array:
	var lines := [0]
	var ings: Array = sum["ingredients"]
	for i in ings.size():
		if i < active_slots or ings[i] > 0:
			lines.append(i + 1)
	return lines


func _text(s: String, col: Vector2, y: float, align: HorizontalAlignment, color: Color) -> void:
	var base := y + ROW_H / 2 + FONT_SIZE * 0.36
	draw_string(FONT, Vector2(col.x, base), s, align, col.y, FONT_SIZE, color)


func _draw() -> void:
	if header:
		_text("回", COL_K, 0, HORIZONTAL_ALIGNMENT_RIGHT, TEXT_MUTED)
		_text("日", COL_DAY, 0, HORIZONTAL_ALIGNMENT_CENTER, TEXT_MUTED)
		_text("時刻", COL_TIME, 0, HORIZONTAL_ALIGNMENT_CENTER, TEXT_MUTED)
		_text("獲得", COL_ITEM, 0, HORIZONTAL_ALIGNMENT_LEFT, TEXT_MUTED)
		_text("スキル", COL_SKILL, 0, HORIZONTAL_ALIGNMENT_LEFT, TEXT_MUTED)
		return
	if entries.is_empty():
		_text("まだ記録がありません", Vector2(0, size.x), 0, HORIZONTAL_ALIGNMENT_CENTER, TEXT_MUTED)
		return
	# 何千行あっても重くならないよう、スクロールで見えている範囲だけ描く
	var first := 0
	var last := rows.size() - 1
	var scroll := get_parent() as ScrollContainer
	if scroll != null:
		first = clampi(int(scroll.scroll_vertical / ROW_H), 0, last)
		last = clampi(int((scroll.scroll_vertical + scroll.size.y) / ROW_H) + 1, 0, last)
	for r in range(first, last + 1):
		var row: Dictionary = rows[r]
		if row.has("e"):
			_draw_row(row["e"], r * ROW_H)
		else:
			_draw_summary_line(row["day"], row["line"], r * ROW_H)


func _draw_row(i: int, y: float) -> void:
	var e: Dictionary = entries[i]
	if Sim.is_tap(e):
		_draw_tap_row(e, y)
		return
	if help_numbers[i] % 2 == 0:
		draw_rect(Rect2(0, y, size.x, ROW_H), STRIPE)
	_text(str(help_numbers[i]), COL_K, y, HORIZONTAL_ALIGNMENT_RIGHT, TEXT_DARK)
	_draw_time(e, y)
	var cy := y + ROW_H / 2
	if e["id"] == "":
		_text("いつのまに育成", COL_ITEM, y, HORIZONTAL_ALIGNMENT_LEFT, TEXT_MUTED)
	else:
		ItemArt.draw_item(self, e["id"], Vector2(COL_ITEM.x + 18, cy + 2), 0.95)
		_text("×%d" % e["amount"], Vector2(COL_ITEM.x + 42, 100), y, HORIZONTAL_ALIGNMENT_LEFT, TEXT_DARK)
	# おてつだいの行で発動したスキルはまだストックにあるだけなので、薄くして「予約」と書く
	match int(e["skill"]):
		Sim.Skill.HIT:
			_exclaim(Vector2(COL_SKILL.x + 20, cy), 1, EXCLAIM_FILL, CEILING_COLOR, RESERVED_ALPHA)
			_text("予約", Vector2(COL_SKILL.x + 44, 80), y, HORIZONTAL_ALIGNMENT_LEFT, TEXT_MUTED)
		Sim.Skill.CEILING:
			# 天井で出た回は色を反転させ、横に「天井」と添える
			_exclaim(Vector2(COL_SKILL.x + 20, cy), 1, CEILING_COLOR, Color.WHITE, RESERVED_ALPHA)
			_text("天井予約", Vector2(COL_SKILL.x + 44, 90), y, HORIZONTAL_ALIGNMENT_LEFT,
				Color(CEILING_COLOR, RESERVED_ALPHA))


## 日ごとのまとめの1行。line 0 は「n日目のまとめ」ときのみ・スキルの予約数、1〜 は食材枠ごとの数
func _draw_summary_line(day: int, line: int, y: float) -> void:
	draw_rect(Rect2(0, y, size.x, ROW_H), DAY_BAND)
	draw_rect(Rect2(0, y, 5, ROW_H), DAY_COLOR)
	var sum: Dictionary = summaries[day]
	var cy := y + ROW_H / 2
	var label := Vector2(10, COL_TIME.x + COL_TIME.y - 10)
	if line == 0:
		draw_rect(Rect2(0, y, size.x, 2), DAY_COLOR)
		_text("%d日目のまとめ" % day, label, y, HORIZONTAL_ALIGNMENT_LEFT, DAY_COLOR)
		ItemArt.draw_item(self, "berry", Vector2(COL_ITEM.x + 18, cy + 2), 0.95)
		_text("×%d" % sum["berry"], Vector2(COL_ITEM.x + 42, 100), y, HORIZONTAL_ALIGNMENT_LEFT, TEXT_DARK)
		_exclaim(Vector2(COL_SKILL.x + 20, cy), 1, EXCLAIM_FILL, CEILING_COLOR)
		_text("×%d回" % sum["skill"], Vector2(COL_SKILL.x + 44, 80), y, HORIZONTAL_ALIGNMENT_LEFT, TEXT_DARK)
		return
	_text("食材枠%d" % line, label, y, HORIZONTAL_ALIGNMENT_RIGHT, DAY_COLOR)
	ItemArt.draw_item(self, slot_ids[line - 1], Vector2(COL_ITEM.x + 18, cy + 2), 0.95)
	_text("×%d" % sum["ingredients"][line - 1], Vector2(COL_ITEM.x + 42, 100), y, HORIZONTAL_ALIGNMENT_LEFT, TEXT_DARK)


## 「n日目」と時刻を、時計と同じ時刻（朝4:00 始まり、4:00 で日付が変わる）で出す
func _draw_time(e: Dictionary, y: float) -> void:
	var when := FieldClock.day_and_clock(e["t"])
	_text("%d日目" % when[0], COL_DAY, y, HORIZONTAL_ALIGNMENT_CENTER, TEXT_DARK)
	_text(when[1], COL_TIME, y, HORIZONTAL_ALIGNMENT_CENTER, TEXT_DARK)


## タップした時点の行。回の列は空けて、出した数と使ったスキルのストックを書く
func _draw_tap_row(e: Dictionary, y: float) -> void:
	draw_rect(Rect2(0, y + 3, size.x, ROW_H - 6), TAP_BAND)
	draw_rect(Rect2(0, y + 3, 5, ROW_H - 6), TAP_COLOR)
	_draw_time(e, y)
	var amount := int(e["amount"])
	_text("タップ" if amount == 0 else "タップ %d個" % amount, COL_ITEM, y, HORIZONTAL_ALIGNMENT_LEFT, TAP_COLOR)
	# 使ったストックはパチモンの頭上と同じ「!」「!!」で出す
	var stock := int(e["stock"])
	if stock > 0:
		_exclaim(Vector2(COL_SKILL.x + 20, y + ROW_H / 2), stock, EXCLAIM_FILL, CEILING_COLOR)


## パチモンの頭上に出る「!」と同じ形の小さな印。n 個並べるとギザギザも横に伸ばす。alpha で薄くする
func _exclaim(c: Vector2, n: int, fill: Color, mark: Color, alpha: float = 1.0) -> void:
	var burst := ItemArt.burst(c, 14.0, 1.0 + 0.3 * (n - 1))
	draw_colored_polygon(burst, Color(fill, alpha))
	ItemArt.outline(self, burst, Color(CEILING_COLOR, alpha), 2.0)
	var w := 40.0 * n
	draw_set_transform(c, ItemArt.EXCLAIM_TILT)
	draw_string(FONT, Vector2(-w / 2, 8), "!".repeat(n), HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(mark, alpha))
	draw_set_transform(Vector2.ZERO)
