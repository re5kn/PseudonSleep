extends Node2D
## 時計の下の歯車アイコン。タップで表示設定の欄を開く。時計と同じ色合いで描く。

const FieldClock = preload("res://scripts/field_clock.gd")
const ItemArt = preload("res://scripts/item_art.gd")

const RADIUS := 24.0
const TEETH := 8
## 歯の付け根の半径と、歯の幅（角度の割合。1で歯と谷が同じ幅）
const ROOT_RADIUS := 18.0
const TOOTH_RATIO := 0.9
const HOLE_RADIUS := 7.0


func hit(p: Vector2) -> bool:
	return global_position.distance_to(p) <= RADIUS + 8.0


func _draw() -> void:
	draw_colored_polygon(_gear(Vector2(0, 3), RADIUS + 2, ROOT_RADIUS + 2), Color(0, 0, 0, 0.15))
	var body := _gear(Vector2.ZERO, RADIUS, ROOT_RADIUS)
	draw_colored_polygon(body, FieldClock.RIM)
	ItemArt.outline(self, body, FieldClock.RIM_DARK, 2.5)
	draw_circle(Vector2.ZERO, ROOT_RADIUS - 6, FieldClock.FACE)
	draw_circle(Vector2.ZERO, HOLE_RADIUS, FieldClock.RIM_DARK)
	draw_circle(Vector2.ZERO, HOLE_RADIUS - 2.5, FieldClock.RIM)


## 歯車の輪郭。歯は台形（先が少し細い）
func _gear(c: Vector2, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var step := TAU / TEETH
	var half := step * TOOTH_RATIO / 4.0
	for i in TEETH:
		var a := step * i - PI / 2
		pts.append(c + Vector2.from_angle(a - half * 1.35) * r_in)
		pts.append(c + Vector2.from_angle(a - half) * r_out)
		pts.append(c + Vector2.from_angle(a + half) * r_out)
		pts.append(c + Vector2.from_angle(a + half * 1.35) * r_in)
		# 谷は付け根の円に沿わせる
		pts.append(c + Vector2.from_angle(a + step / 2) * r_in)
	return pts
