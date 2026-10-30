extends Node
## 画面全体の組み立てと操作。

const Sim = preload("res://scripts/sim.gd")
const Params = preload("res://scripts/params.gd")
const FieldBackground = preload("res://scripts/field_background.gd")
const PseudonView = preload("res://scripts/pseudon_view.gd")
const ItemPile = preload("res://scripts/item_pile.gd")
const FlyingItem = preload("res://scripts/flying_item.gd")
const StorageBox = preload("res://scripts/storage_box.gd")
const ItemIcon = preload("res://scripts/item_icon.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const HelpLogTable = preload("res://scripts/help_log_table.gd")
const Desk = preload("res://scripts/desk.gd")
const FieldClock = preload("res://scripts/field_clock.gd")
const Fairy = preload("res://scripts/fairy.gd")
const FairyView = preload("res://scripts/fairy_view.gd")
const Presets = preload("res://scripts/presets.gd")
const Bed = preload("res://scripts/bed.gd")
const Dist = preload("res://scripts/dist.gd")
const DistChart = preload("res://scripts/dist_chart.gd")
const Omikuji = preload("res://scripts/omikuji.gd")
const Balloon = preload("res://scripts/balloon.gd")
const GearIcon = preload("res://scripts/gear_icon.gd")
const Fireworks = preload("res://scripts/fireworks.gd")
const FONT = preload("res://fonts/MPLUSRounded1c-Bold.ttf")

const VIEW_SIZE := Vector2(720, 1280)
const FIELD_HEIGHT := 1040.0
## 画面下部の操作パネルの上端。チーム全体の設定の行を足した分だけフィールドに重ねて上へ広げる
const PANEL_TOP := 972.0
const PSEUDON_POS := Vector2(360, 505)
const PILE_Y := 636.0
const PILE_GAP := 88.0
const BOX_POS := Vector2(138, 764)
const DESK_POS := Vector2(606, 560)
## ベッド（「ねむる」の札付き）の中心
const BED_POS := Vector2(478, 352)
const SLEEP_POPUP_W := 380.0
## おみくじの風船（地面の位置）と設定欄
const BALLOON_POS := Vector2(584, 846)
const OMIKUJI_POPUP_W := 600.0
## あたりの花火を打ち上げる範囲（大あたりはこの中いっぱいに出す）
const FIREWORKS_AREA := Rect2(80, 140, 560, 620)
## 上限のあたりで、風船の数字が0になってからさらに膨らみ始めるまでの間と、膨らむ時間・倍率
const GRAND_COUNTDOWN_SEC := 0.4
const GRAND_INFLATE_SEC := 1.0
const GRAND_INFLATE := 3.0
## 回数の確率分布のグラフを出す欄
const DIST_POPUP_W := 600.0
const DIST_POPUP_Y := 300.0
const DIST_CHART_H := 300.0
## スキル回数の欄の下に出す連続不発の分布のグラフの高さ
const MISS_CHART_H := 220.0
## 連続不発の分布は上限（初期値65）までまとめずに棒を並べる
const MISS_MAX_BARS := 100
## 睡眠時間（分）の刻みと範囲
const SLEEP_STEP_MIN := 30
const SLEEP_MIN_MIN := 30
const SLEEP_MAX_MIN := 24 * 60
## 妖精が休む地上の位置と、回復するとき漂うパチモンの肩の高さ（パチモンの左右）、色
const FAIRY_REST_OFFSETS := [Vector2(-128, 52), Vector2(128, 52)]
const FAIRY_FLY_OFFSETS := [Vector2(-128, -42), Vector2(128, -42)]
const FAIRY_COLORS := [Color("ff9ccf"), Color("8fd3ff")]
const FAIRY_POPUP_W := 400.0
const FAIRY_INFO_W := 300.0
## 妖精の初期の変身先（へんしんリストの「回復役」の枠）
const FAIRY_PRESET := 1
const MIN_HOURS := 1
const MAX_HOURS := 24
const TOAST_SEC := 2.5
const CUTIN_PAUSE_SEC := 0.9
const REPEAT_DELAY_SEC := 0.4
const REPEAT_INTERVAL_SEC := 0.08
## 設定パネルの幅。ブラウザの幅が VIEW_SIZE.x + これ以上あれば、フィールドと並べて表示する
const SETTINGS_W := 470.0
const SETTINGS_SLIDE_SEC := 0.22
## おてつだいの記録パネルの幅（画面右からせり出す）
const LOG_W := 540.0

const TEXT_DARK := Color("5a4632")
const CREAM := Color("fff7e6")
## 天井で出たスキルの目印の色
const CEILING_COLOR := Color("e2483d")
## 時計の中心（フィールド右上）
const CLOCK_POS := Vector2(VIEW_SIZE.x - 70, 70)
## 時計の下の歯車アイコン（表示設定の欄を開く）と、その欄の幅
const GEAR_POS := Vector2(VIEW_SIZE.x - 70, 162)
const VIEW_POPUP_W := 380.0
## 昼・夕方・夜にフィールド背景へ重ねる色（昼は重ねない）
const PHASE_TINTS := {
	FieldClock.Phase.DAY: Color(1, 0.6, 0.25, 0.0),
	FieldClock.Phase.EVENING: Color(1, 0.55, 0.2, 0.3),
	FieldClock.Phase.NIGHT: Color(0.04, 0.06, 0.22, 0.55),
}
const PHASE_FADE_SEC := 0.35

var sim: Sim
var fairies: Array[Fairy] = []
var fairy_views: Array[FairyView] = []
## 計算条件の保存先。設定パネルと妖精の変身で共有する
var presets: Presets
var hours := 3
## 睡眠時間（分）。初期値は8時間30分（げんきが100回復する長さ）
var sleep_minutes := Sim.SLEEP_FULL_MIN
var omikuji := Omikuji.new()
## 表示設定（初期値はどちらも非表示）
var box_shown := false
var omikuji_shown := false
var piles := {}
var cutin_active := false
var cutin_closable := false
## カットインで「!」を出しているもの（パチモンか妖精）
var cutin_actor: Node2D
## なぞり回収中か、直前の指の位置、このなぞりで回収済みの山
var swiping := false
var swipe_last := Vector2.ZERO
var swiped := {}

## 縦長の画面（VIEW_SIZE）をブラウザの中央に置くため、全レイヤーを同じだけずらす
var layers: Array[CanvasLayer] = []
var ui_theme: Theme
var actor_root: Node2D
var pseudon: PseudonView
var storage_box: StorageBox
var desk: Desk
var bed: Bed
var balloon: Balloon
var fireworks: Fireworks
## あたりで割れた風船を、カットインの暗転が明けたら出し直す
var balloon_respawn := false
var clock: FieldClock
var gear: GearIcon
var phase_tint: ColorRect
var phase := FieldClock.phase_at(FieldClock.START_SEC)
var phase_tween: Tween
var dim: ColorRect
var hud_label: RichTextLabel
var log_panel: PanelContainer
var log_scrim: ColorRect
## 設定パネルと記録パネルのレイヤー。上限のあたりの演出中は隠す
var side_layers: Array[CanvasLayer] = []
var log_open := false
var log_slide := 0.0
var log_tween: Tween
var log_title: Label
var log_scroll: ScrollContainer
var log_table: HelpLogTable
var hours_label: Label
var advance_button: Button
var genki_button: Button
## げんきの初期値（「げんき：nから減少」のとき横に出す）
var genki_start_row: HBoxContainer
var genki_start_spin: SpinBox
## チーム全体のおてつだいボーナスの数といいキャンプチケット（パチモンと妖精の全員に入る）
var help_bonus_spin: SpinBox
var camp_check: CheckBox
var status_label: RichTextLabel
var toast_box: VBoxContainer
var box_popup: PanelContainer
var box_popup_label: Label
var box_popup_timer: SceneTreeTimer
var bubble: PanelContainer
## 妖精の設定欄（妖精ごとではなく1つを使い回す）。開いている妖精の番号、閉じていれば -1
var fairy_popup: PanelContainer
var fairy_popup_index := -1
var fairy_title: Label
var fairy_heal_check: CheckBox
var fairy_amount: SpinBox
## 効果の対象のチェック（パチモン・妖精1・妖精2）
var fairy_target_checks: Array[CheckBox] = []
var fairy_preset: OptionButton
var fairy_summary: Label
## 変身の (i) で出す説明の吹き出し
var fairy_info: PanelContainer
var fairy_info_text: Label
var bubble_label: Label
## 睡眠の設定欄（睡眠時間と「ねむる」ボタン）
var sleep_popup: PanelContainer
var sleep_time_label: Label
var sleep_summary: Label
## 表示設定の欄（収容箱・おみくじを出すかのトグル）
var view_popup: PanelContainer
var omikuji_popup: PanelContainer
var omikuji_check: CheckBox
var omikuji_chance: SpinBox
var omikuji_limit: SpinBox
var omikuji_summary: Label
var omikuji_chart: DistChart
var omikuji_dist: RichTextLabel
## 食材回数・スキル回数の (i) で出す確率分布の欄。出している項目（"ingredient" か "skill"）、閉じていれば ""
var dist_popup: PanelContainer
var dist_popup_kind := ""
var dist_title: Label
var dist_chart: DistChart
var dist_summary: RichTextLabel
## スキル回数の欄だけに出す、連続不発の分布（見出し・グラフ・説明）
var miss_section: VBoxContainer
var miss_chart: DistChart
var miss_summary: RichTextLabel
var blocker: Control
var settings: SettingsPanel
var settings_scrim: ColorRect
var settings_open := false
## 0＝閉じている、1＝せり出しきった状態
var settings_slide := 0.0
var settings_tween: Tween


func _ready() -> void:
	sim = Sim.new()
	presets = Presets.new()
	for i in FAIRY_REST_OFFSETS.size():
		var f := Fairy.new("妖精%d" % (i + 1))
		f.preset = FAIRY_PRESET
		presets.restore(FAIRY_PRESET, f.sim.params)
		f.sim.reset()
		fairies.append(f)
	ui_theme = Theme.new()
	ui_theme.default_font = FONT
	ui_theme.default_font_size = 22
	_build_field()
	_build_panel()
	_build_overlays()
	_build_log_view()
	_build_settings()
	_refresh()
	get_viewport().size_changed.connect(_center_layers)
	_center_layers()


# ---------------------------------------------------------------- 画面の組み立て

## 縦長の画面を中央に置く。横に余った領域は背景色のまま。
## 幅が広く設定パネル（左）・記録パネル（右）を並べて出せるときは、残りの幅の中央にフィールドを置く。
func _center_layers() -> void:
	var view := get_viewport().get_visible_rect().size
	var offset := ((view - VIEW_SIZE) / 2).floor()
	var wide := _is_wide()
	if wide:
		var left := SETTINGS_W * settings_slide
		var right := LOG_W * log_slide
		offset.x = floorf(left + (view.x - left - right - VIEW_SIZE.x) / 2)
	for layer in layers:
		layer.offset = offset
	if settings != null:
		settings.size = Vector2(_side_width(SETTINGS_W), view.y)
		settings.position = Vector2(-settings.size.x * (1.0 - settings_slide), 0)
		settings.visible = settings_slide > 0.0
		settings_scrim.size = view
		settings_scrim.visible = settings_open and not wide
		settings_scrim.modulate.a = settings_slide
	if log_panel != null:
		log_panel.size = Vector2(_side_width(LOG_W), view.y)
		log_panel.position = Vector2(view.x - log_panel.size.x * log_slide, 0)
		log_panel.visible = log_slide > 0.0
		log_scrim.size = view
		log_scrim.visible = log_open and not wide
		log_scrim.modulate.a = log_slide


## 開いているパネルをすべてフィールドの横に並べられるか
func _is_wide() -> bool:
	var need := VIEW_SIZE.x
	if settings_open:
		need += SETTINGS_W
	if log_open:
		need += LOG_W
	return get_viewport().get_visible_rect().size.x >= need


func _side_width(w: float) -> float:
	# 狭い画面では外側をタップして閉じられるよう、反対側に少し隙間を残す
	return minf(w, get_viewport().get_visible_rect().size.x - 80.0)


func _layer(n: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = n
	add_child(layer)
	layers.append(layer)
	return layer


func _build_field() -> void:
	var field := _layer(0)
	# 背景の波や影がフィールドの外へはみ出さないよう切り取る
	var field_clip := Control.new()
	field_clip.size = Vector2(VIEW_SIZE.x, FIELD_HEIGHT)
	field_clip.clip_contents = true
	field_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_clip.add_child(FieldBackground.new())
	# 夕方・夜の色合いは背景だけに重ねる
	phase_tint = ColorRect.new()
	phase_tint.size = field_clip.size
	phase_tint.color = PHASE_TINTS[phase]
	phase_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_clip.add_child(phase_tint)
	field.add_child(field_clip)

	storage_box = StorageBox.new()
	storage_box.label = "きのみ・食材収容箱"
	storage_box.position = BOX_POS
	storage_box.visible = box_shown
	field.add_child(storage_box)

	desk = Desk.new()
	desk.position = DESK_POS
	field.add_child(desk)

	bed = Bed.new()
	bed.position = BED_POS
	bed.canopy = sim.params.camp_ticket
	field.add_child(bed)

	clock = FieldClock.new()
	clock.position = CLOCK_POS
	clock.time_shown.connect(_on_time_shown)
	field.add_child(clock)

	gear = GearIcon.new()
	gear.position = GEAR_POS
	field.add_child(gear)

	var hud := PanelContainer.new()
	hud.theme = ui_theme
	hud.position = Vector2(16, 16)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.85), 20, 8))
	hud_label = RichTextLabel.new()
	hud_label.bbcode_enabled = true
	hud_label.fit_content = true
	hud_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud_label.scroll_active = false
	# 食材回数・スキル回数の (i) を押せるようにする（それ以外の場所はフィールドへ通す）
	hud_label.mouse_filter = Control.MOUSE_FILTER_PASS
	hud_label.meta_underlined = false
	hud_label.meta_clicked.connect(_on_hud_meta_clicked)
	hud_label.add_theme_font_size_override("normal_font_size", 20)
	hud_label.add_theme_color_override("default_color", TEXT_DARK)
	hud.add_child(hud_label)
	field.add_child(hud)

	# 暗転はUIパネルも含めて画面全体にかける
	var dim_layer := _layer(2)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = VIEW_SIZE
	dim.modulate.a = 0.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim_layer.add_child(dim)

	# パチモンとドロップは暗転より手前に出す
	var actors := _layer(3)
	actor_root = Node2D.new()
	actors.add_child(actor_root)
	pseudon = PseudonView.new()
	pseudon.position = PSEUDON_POS
	actor_root.add_child(pseudon)
	for i in fairies.size():
		var fv := FairyView.new()
		fv.rest_pos = PSEUDON_POS + FAIRY_REST_OFFSETS[i]
		fv.fly_pos = PSEUDON_POS + FAIRY_FLY_OFFSETS[i]
		fv.droop_y = PSEUDON_POS.y + PseudonView.RIGHT_HAND.y
		fv.position = fv.rest_pos
		fv.color = FAIRY_COLORS[i]
		fv.phase = i * 2.3
		actor_root.add_child(fv)
		fairy_views.append(fv)
	# おみくじの風船。あたりの演出を暗転の上に出すため、パチモンと同じ層に置く
	balloon = Balloon.new()
	balloon.position = BALLOON_POS
	actor_root.add_child(balloon)
	fireworks = Fireworks.new()
	actor_root.add_child(fireworks)
	fireworks.shake_target = actor_root


func _build_panel() -> void:
	var layer := _layer(1)
	var panel := PanelContainer.new()
	panel.theme = ui_theme
	panel.position = Vector2(0, PANEL_TOP)
	panel.size = Vector2(VIEW_SIZE.x, VIEW_SIZE.y - PANEL_TOP)
	var sb := _style(CREAM, 0, 14)
	sb.corner_radius_top_left = 28
	sb.corner_radius_top_right = 28
	sb.border_width_top = 4
	sb.border_color = Color("f0d9a8")
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	# チーム全体の設定: おてつだいボーナスの数（0〜5）といいキャンプチケット
	var team := HBoxContainer.new()
	team.theme = SettingsPanel.make_theme(ui_theme)
	team.add_theme_constant_override("separation", 6)
	v.add_child(team)
	team.add_child(_label("おてつだいボーナス", 18))
	help_bonus_spin = SpinBox.new()
	help_bonus_spin.min_value = 0
	help_bonus_spin.max_value = 5
	help_bonus_spin.step = 1
	help_bonus_spin.value = sim.params.help_bonus_count
	help_bonus_spin.suffix = "個"
	help_bonus_spin.custom_minimum_size = Vector2(110, 0)
	help_bonus_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_bonus_spin.select_all_on_focus = true
	help_bonus_spin.value_changed.connect(func(x: float) -> void: _set_team("help_bonus_count", int(x)))
	team.add_child(help_bonus_spin)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team.add_child(gap)
	camp_check = CheckBox.new()
	camp_check.text = "いいキャンプチケット"
	camp_check.button_pressed = sim.params.camp_ticket
	camp_check.focus_mode = Control.FOCUS_NONE
	camp_check.add_theme_font_size_override("font_size", 18)
	camp_check.toggled.connect(func(on: bool) -> void: _set_team("camp_ticket", on))
	team.add_child(camp_check)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	v.add_child(row1)
	var minus := _button("－", Color("ffe9bf"), TEXT_DARK)
	minus.custom_minimum_size = Vector2(56, 56)
	_add_hold_repeat(minus, _change_hours.bind(-1))
	row1.add_child(minus)
	hours_label = _label("", 24)
	hours_label.custom_minimum_size = Vector2(92, 0)
	hours_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row1.add_child(hours_label)
	var plus := _button("＋", Color("ffe9bf"), TEXT_DARK)
	plus.custom_minimum_size = Vector2(56, 56)
	_add_hold_repeat(plus, _change_hours.bind(1))
	row1.add_child(plus)
	advance_button = _button("", Color("4fbf6a"), Color.WHITE)
	advance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	advance_button.add_theme_font_size_override("font_size", 26)
	advance_button.pressed.connect(_on_advance)
	row1.add_child(advance_button)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	v.add_child(row2)
	# タップで切り替えるトグル
	genki_button = _toggle()
	genki_button.pressed.connect(_on_genki_toggled)
	row2.add_child(genki_button)
	# げんきの初期値。パチモンと妖精の両方に入る
	genki_start_row = HBoxContainer.new()
	genki_start_row.add_theme_constant_override("separation", 6)
	row2.add_child(genki_start_row)
	genki_start_row.add_child(_label("初期値", 18))
	genki_start_spin = SpinBox.new()
	genki_start_spin.theme = SettingsPanel.make_theme(ui_theme)
	genki_start_spin.min_value = 0
	genki_start_spin.max_value = Sim.GENKI_MAX
	genki_start_spin.step = 1
	genki_start_spin.value = sim.genki_start
	genki_start_spin.custom_minimum_size = Vector2(110, 0)
	genki_start_spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	genki_start_spin.select_all_on_focus = true
	genki_start_spin.value_changed.connect(_on_genki_start_changed)
	genki_start_row.add_child(genki_start_spin)
	var reset := _button("リセット", Color("e5534b"), Color.WHITE)
	reset.add_theme_font_size_override("font_size", 18)
	reset.pressed.connect(_on_reset)
	row2.add_child(reset)

	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.scroll_active = false
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.add_theme_font_size_override("normal_font_size", 17)
	status_label.add_theme_color_override("default_color", TEXT_DARK)
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(status_label)


func _build_overlays() -> void:
	var layer := _layer(4)

	toast_box = VBoxContainer.new()
	toast_box.theme = ui_theme
	# 取得の表示は右上の時計の下に出す
	toast_box.position = Vector2(VIEW_SIZE.x - 236, CLOCK_POS.y + FieldClock.RADIUS + 14)
	toast_box.size = Vector2(220, 0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 8)
	layer.add_child(toast_box)

	box_popup = PanelContainer.new()
	box_popup.theme = ui_theme
	box_popup.visible = false
	box_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var popup_style := _style(Color.WHITE, 18, 12)
	popup_style.set_border_width_all(3)
	popup_style.border_color = Color("f0a43a")
	box_popup.add_theme_stylebox_override("panel", popup_style)
	box_popup_label = _label("", 19)
	box_popup.add_child(box_popup_label)
	layer.add_child(box_popup)

	bubble = PanelContainer.new()
	bubble.theme = ui_theme
	bubble.visible = false
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.position = Vector2(40, 1060)
	bubble.size = Vector2(640, 170)
	bubble.pivot_offset = Vector2(320, 0)
	var bubble_style := _style(Color.WHITE, 36, 18)
	bubble_style.set_border_width_all(4)
	bubble_style.border_color = Color("f0a43a")
	bubble.add_theme_stylebox_override("panel", bubble_style)
	bubble_label = _label("", 24)
	bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bubble.add_child(bubble_label)
	layer.add_child(bubble)

	_build_fairy_popup(layer)
	_build_sleep_popup(layer)
	_build_omikuji_popup(layer)
	_build_view_popup(layer)
	_build_dist_popup(layer)

	# カットイン中はタップをここで受け止める
	var blocker_layer := _layer(5)
	blocker = Control.new()
	blocker.size = VIEW_SIZE
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.visible = false
	blocker.gui_input.connect(_on_blocker_input)
	blocker_layer.add_child(blocker)


## 妖精の設定欄: 回復する／しない、回復量、変身プルダウン（設定パネルと同じ見た目）。
## 変身は保存機能がないので、項目を選んだ時点でその設定を妖精に入れる
func _build_fairy_popup(layer: CanvasLayer) -> void:
	fairy_popup = PanelContainer.new()
	fairy_popup.theme = SettingsPanel.make_theme(ui_theme)
	fairy_popup.visible = false
	fairy_popup.custom_minimum_size = Vector2(FAIRY_POPUP_W, 0)
	var sb := _style(CREAM, 22, 12)
	sb.set_border_width_all(3)
	sb.border_color = Color("e6cf9f")
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	fairy_popup.add_theme_stylebox_override("panel", sb)
	layer.add_child(fairy_popup)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	fairy_popup.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	fairy_title = _label("", 22)
	fairy_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fairy_title)
	var close := _button("×", Color("ffe9bf"), TEXT_DARK)
	close.custom_minimum_size = Vector2(48, 48)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_hide_fairy_popup)
	top.add_child(close)

	fairy_heal_check = CheckBox.new()
	fairy_heal_check.text = "回復する"
	fairy_heal_check.focus_mode = Control.FOCUS_NONE
	fairy_heal_check.add_theme_font_size_override("font_size", 18)
	fairy_heal_check.toggled.connect(_on_fairy_heals_toggled)
	v.add_child(fairy_heal_check)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	v.add_child(preset_row)
	preset_row.add_child(_label("変身", 18))
	preset_row.add_child(_info_button())
	fairy_preset = OptionButton.new()
	fairy_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fairy_preset.focus_mode = Control.FOCUS_NONE
	fairy_preset.fit_to_longest_item = false
	fairy_preset.clip_text = true
	fairy_preset.add_theme_font_size_override("font_size", 18)
	fairy_preset.get_popup().add_theme_font_size_override("font_size", 20)
	fairy_preset.item_selected.connect(_on_fairy_preset_selected)
	preset_row.add_child(fairy_preset)

	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 6)
	v.add_child(amount_row)
	var amount_label := _label("回復量（マイナスで減る）", 18)
	amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(amount_label)
	fairy_amount = SpinBox.new()
	fairy_amount.min_value = -Sim.GENKI_MAX
	fairy_amount.max_value = Sim.GENKI_MAX
	fairy_amount.step = 1
	fairy_amount.custom_minimum_size = Vector2(110, 0)
	fairy_amount.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fairy_amount.select_all_on_focus = true
	fairy_amount.value_changed.connect(func(x: float) -> void:
		if fairy_popup_index >= 0:
			fairies[fairy_popup_index].heal_amount = int(x))
	amount_row.add_child(fairy_amount)

	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 10)
	v.add_child(target_row)
	target_row.add_child(_label("効果の対象", 18))
	for k in fairies.size() + 1:
		var cb := CheckBox.new()
		cb.text = "パチモン" if k == 0 else fairies[k - 1].label
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 17)
		cb.toggled.connect(func(on: bool) -> void:
			if fairy_popup_index >= 0:
				fairies[fairy_popup_index].targets[k] = on)
		target_row.add_child(cb)
		fairy_target_checks.append(cb)

	fairy_summary = _label("", 15)
	fairy_summary.add_theme_color_override("font_color", Color("8a7660"))
	fairy_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fairy_summary.custom_minimum_size = Vector2(FAIRY_POPUP_W - 40, 0)
	v.add_child(fairy_summary)

	fairy_info = PanelContainer.new()
	fairy_info.visible = false
	fairy_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var isb := _style(Color.WHITE, 12, 8)
	isb.set_border_width_all(2)
	isb.border_color = Color("e6cf9f")
	isb.shadow_color = Color(0, 0, 0, 0.2)
	isb.shadow_size = 4
	fairy_info.add_theme_stylebox_override("panel", isb)
	fairy_info_text = _label("", 15)
	fairy_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fairy_info_text.custom_minimum_size = Vector2(FAIRY_INFO_W, 0)
	fairy_info.add_child(fairy_info_text)
	layer.add_child(fairy_info)


## 「変身」の横の (i)。タップかマウスを乗せると説明の吹き出しを出す
func _info_button() -> Button:
	var b := Button.new()
	b.text = "i"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(28, 28)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 17)
	var color := Color("8a7660")
	for state in ["normal", "hover", "pressed"]:
		var sb := _style(color.lightened(0.15) if state == "hover" else color, 14, 0)
		sb.content_margin_left = 0
		sb.content_margin_right = 0
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, Color.WHITE)
	# タッチでもマウスでも、押したときと乗せたときに出し、外れたら消す（タッチは他の場所を触ると外れる）
	b.pressed.connect(_show_fairy_info.bind(b))
	b.mouse_entered.connect(_show_fairy_info.bind(b))
	b.mouse_exited.connect(func() -> void: fairy_info.visible = false)
	return b


## (i) の下に吹き出しを出す。設定欄からはみ出しても画面の中に収める
func _show_fairy_info(b: Button) -> void:
	_update_fairy_info_text()
	fairy_info.reset_size()
	var at := b.global_position + Vector2(b.size.x / 2 - fairy_info.size.x / 2, b.size.y + 6)
	at.x = clampf(at.x, 12, VIEW_SIZE.x - fairy_info.size.x - 12)
	fairy_info.position = at
	fairy_info.visible = true


## 吹き出しの説明。名前は今変身している枠の設定名
func _update_fairy_info_text() -> void:
	if fairy_popup_index < 0:
		return
	var slot := presets.slot_name(fairies[fairy_popup_index].preset)
	fairy_info_text.text = "「%s」のパラメータ変更は以下の手順で行います。\n1. 設定パネルで「%s」に「変身」\n2. 任意のパラメータを設定\n3. 「記憶」を選択" % [slot, slot]
	fairy_info.reset_size()


func _show_fairy_popup(i: int) -> void:
	fairy_popup_index = i
	var f := fairies[i]
	fairy_title.text = "%sの設定" % f.label
	fairy_heal_check.set_pressed_no_signal(f.heals)
	fairy_amount.set_value_no_signal(f.heal_amount)
	for k in fairy_target_checks.size():
		fairy_target_checks[k].set_pressed_no_signal(f.targets[k])
	# へんしんリストは設定パネルで記憶し直せるので、開くたびに名前を取り直す
	fairy_preset.clear()
	for k in Presets.SLOT_COUNT:
		fairy_preset.add_item(presets.slot_name(k), k)
		fairy_preset.set_item_disabled(k, not presets.is_saved(k))
	fairy_preset.select(f.preset)
	_update_fairy_summary()
	fairy_popup.reset_size()
	# 妖精の下に出す（休んでいる地上の位置の下。漂っていても同じ場所）
	var at: Vector2 = fairy_views[i].rest_pos
	var x := clampf(at.x - FAIRY_POPUP_W / 2, 12, VIEW_SIZE.x - FAIRY_POPUP_W - 12)
	fairy_popup.position = Vector2(x, at.y + 52)
	fairy_popup.visible = true
	_refresh()


func _hide_fairy_popup() -> void:
	if fairy_popup_index < 0:
		return
	# 入力途中の回復量を確定させる
	get_viewport().gui_release_focus()
	fairy_popup_index = -1
	fairy_popup.visible = false
	fairy_info.visible = false
	_refresh()


## 回復するにしたら今からおてつだいを始める。しないにしたら休ませる（持っている分とストックは捨てる）
func _on_fairy_heals_toggled(on: bool) -> void:
	var f := fairies[fairy_popup_index]
	f.heals = on
	f.sim.restart_help()
	_refresh()


func _on_fairy_preset_selected(k: int) -> void:
	var f := fairies[fairy_popup_index]
	if not presets.restore(k, f.sim.params):
		return
	f.preset = k
	f.sim.clamp_stock()
	_update_fairy_summary()
	_update_fairy_info_text()
	_refresh()


func _update_fairy_summary() -> void:
	var p := fairies[fairy_popup_index].sim.params
	fairy_summary.text = "%s：おてつだい時間 %d秒・スキル %.1f%%・ストック %d回・連続不発上限 %d回・最大所持数 %d" % [
		p.pseudon_name, int(p.help_sec()), p.skill_chance() * 100.0, p.max_skill_stock, p.skill_ceiling, p.carry_limit()]


## 睡眠の設定欄: 睡眠時間（30分刻み）と「ねむる」ボタン。妖精の設定欄と同じ見た目
func _build_sleep_popup(layer: CanvasLayer) -> void:
	sleep_popup = PanelContainer.new()
	sleep_popup.theme = SettingsPanel.make_theme(ui_theme)
	sleep_popup.visible = false
	sleep_popup.custom_minimum_size = Vector2(SLEEP_POPUP_W, 0)
	var sb := _style(CREAM, 22, 12)
	sb.set_border_width_all(3)
	sb.border_color = Color("e6cf9f")
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	sleep_popup.add_theme_stylebox_override("panel", sb)
	layer.add_child(sleep_popup)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	sleep_popup.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	var title := _label("睡眠", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := _button("×", Color("ffe9bf"), TEXT_DARK)
	close.custom_minimum_size = Vector2(48, 48)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_hide_sleep_popup)
	top.add_child(close)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var time_title := _label("睡眠時間", 18)
	time_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(time_title)
	var minus := _button("－", Color("ffe9bf"), TEXT_DARK)
	minus.custom_minimum_size = Vector2(48, 48)
	_add_hold_repeat(minus, _change_sleep.bind(-SLEEP_STEP_MIN))
	row.add_child(minus)
	sleep_time_label = _label("", 20)
	sleep_time_label.custom_minimum_size = Vector2(124, 0)
	sleep_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(sleep_time_label)
	var plus := _button("＋", Color("ffe9bf"), TEXT_DARK)
	plus.custom_minimum_size = Vector2(48, 48)
	_add_hold_repeat(plus, _change_sleep.bind(SLEEP_STEP_MIN))
	row.add_child(plus)

	sleep_summary = _label("", 15)
	sleep_summary.add_theme_color_override("font_color", Color("8a7660"))
	sleep_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sleep_summary.custom_minimum_size = Vector2(SLEEP_POPUP_W - 40, 0)
	v.add_child(sleep_summary)

	var go := _button("ねむる", Color("6a7fd6"), Color.WHITE)
	go.custom_minimum_size = Vector2(0, 56)
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(_on_sleep)
	v.add_child(go)


func _show_sleep_popup() -> void:
	_update_sleep_popup()
	sleep_popup.reset_size()
	# 札の下に出す
	var x := clampf(BED_POS.x + Bed.TAG_POS.x - SLEEP_POPUP_W / 2, 12, VIEW_SIZE.x - SLEEP_POPUP_W - 12)
	sleep_popup.position = Vector2(x, BED_POS.y + Bed.TAG_POS.y + 60)
	sleep_popup.visible = true


func _hide_sleep_popup() -> void:
	sleep_popup.visible = false


func _change_sleep(delta: int) -> void:
	sleep_minutes = clampi(sleep_minutes + delta, SLEEP_MIN_MIN, SLEEP_MAX_MIN)
	_update_sleep_popup()


## 起きたときに回復する量（せいかく補正込み）を眠るもの（パチモンと回復する妖精）ごとに出す
func _update_sleep_popup() -> void:
	sleep_time_label.text = "%d時間%02d分" % [sleep_minutes / 60, sleep_minutes % 60]
	if sim.genki_mode == Sim.GenkiMode.ALWAYS_HIGH:
		sleep_summary.text = "げんきは81以上で固定のため回復しません。おてつだいは進みます。"
		return
	var parts := PackedStringArray(["パチモン +%d" % sim.sleep_recovery(sleep_minutes)])
	for f in fairies:
		if f.heals:
			parts.append("%s +%d" % [f.label, f.sim.sleep_recovery(sleep_minutes)])
	sleep_summary.text = "起きたときのげんき回復（100まで）：%s" % "・".join(parts)


## 表示設定の欄: 画面に出すものを選ぶ。睡眠の設定欄と同じ見た目
func _build_view_popup(layer: CanvasLayer) -> void:
	view_popup = PanelContainer.new()
	view_popup.theme = SettingsPanel.make_theme(ui_theme)
	view_popup.visible = false
	view_popup.custom_minimum_size = Vector2(VIEW_POPUP_W, 0)
	var sb := _style(CREAM, 22, 12)
	sb.set_border_width_all(3)
	sb.border_color = Color("e6cf9f")
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	view_popup.add_theme_stylebox_override("panel", sb)
	layer.add_child(view_popup)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	view_popup.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	var title := _label("表示設定", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := _button("×", Color("ffe9bf"), TEXT_DARK)
	close.custom_minimum_size = Vector2(48, 48)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_hide_view_popup)
	top.add_child(close)

	_view_toggle(v, "きのみ・食材収容箱", box_shown, _set_box_shown)


## 表示設定の欄に「名前　[表示／非表示]」の行を足す。押すたびに on_toggled(on) を呼ぶ
func _view_toggle(v: VBoxContainer, title: String, on: bool, on_toggled: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var name_label := _label(title, 18)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 48)
	b.add_theme_font_size_override("font_size", 18)
	# 押した見た目が残らないよう toggle_mode は使わず、状態は meta に持つ
	b.pressed.connect(func() -> void:
		var x: bool = not b.get_meta("on")
		_style_view_toggle(b, x)
		on_toggled.call(x))
	_style_view_toggle(b, on)
	row.add_child(b)
	return b


func _style_view_toggle(b: Button, on: bool) -> void:
	b.set_meta("on", on)
	b.text = "表示" if on else "非表示"
	if on:
		_apply_button_styles(b, Color("7cc47f"), Color.WHITE)
	else:
		_apply_button_styles(b, Color("e8dcc4"), Color("8a7660"))


func _show_view_popup() -> void:
	view_popup.reset_size()
	# 歯車の左下に出す
	var x := clampf(GEAR_POS.x + GearIcon.RADIUS - VIEW_POPUP_W, 12, VIEW_SIZE.x - VIEW_POPUP_W - 12)
	view_popup.position = Vector2(x, GEAR_POS.y + GearIcon.RADIUS + 12)
	view_popup.visible = true


func _hide_view_popup() -> void:
	view_popup.visible = false


## 収容箱を出す／隠す。隠しても、きのみ・食材は収容箱に入る（タップで中身を見られなくなるだけ）
func _set_box_shown(on: bool) -> void:
	box_shown = on
	storage_box.visible = on
	if not on:
		_hide_box_popup()


## おみくじの設定欄: 有効／無効、あたりの確率、連続はずれの上限。睡眠の設定欄と同じ見た目
func _build_omikuji_popup(layer: CanvasLayer) -> void:
	omikuji_popup = PanelContainer.new()
	omikuji_popup.theme = SettingsPanel.make_theme(ui_theme)
	omikuji_popup.visible = false
	omikuji_popup.custom_minimum_size = Vector2(OMIKUJI_POPUP_W, 0)
	var sb := _style(CREAM, 22, 12)
	sb.set_border_width_all(3)
	sb.border_color = Color("e6cf9f")
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	omikuji_popup.add_theme_stylebox_override("panel", sb)
	layer.add_child(omikuji_popup)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	omikuji_popup.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	var title := _label("おみくじ", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := _button("×", Color("ffe9bf"), TEXT_DARK)
	close.custom_minimum_size = Vector2(48, 48)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_hide_omikuji_popup)
	top.add_child(close)

	omikuji_check = CheckBox.new()
	omikuji_check.text = "有効にする"
	omikuji_check.button_pressed = omikuji.enabled
	omikuji_check.focus_mode = Control.FOCUS_NONE
	omikuji_check.add_theme_font_size_override("font_size", 18)
	omikuji_check.toggled.connect(func(on: bool) -> void:
		omikuji.enabled = on
		_refresh())
	v.add_child(omikuji_check)

	omikuji_chance = _omikuji_spin(v, "あたりの確率", 0.0, 100.0, 0.1, "%")
	omikuji_chance.value = omikuji.chance * 100.0
	omikuji_chance.value_changed.connect(func(x: float) -> void:
		omikuji.chance = x / 100.0
		_refresh())
	omikuji_limit = _omikuji_spin(v, "連続はずれの上限", 0.0, Omikuji.LIMIT_MAX, 1.0, "回")
	omikuji_limit.value = omikuji.limit
	omikuji_limit.value_changed.connect(func(x: float) -> void:
		omikuji.limit = int(x)
		_refresh())

	omikuji_summary = _label("", 15)
	omikuji_summary.add_theme_color_override("font_color", Color("8a7660"))
	omikuji_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	omikuji_summary.custom_minimum_size = Vector2(OMIKUJI_POPUP_W - 40, 0)
	v.add_child(omikuji_summary)

	# 連続はずれの分布（スキル連続不発の分布と同じ形）
	v.add_child(HSeparator.new())
	v.add_child(_label("連続はずれの分布", 20))
	omikuji_chart = _miss_chart("連続はずれの回数")
	v.add_child(omikuji_chart)
	omikuji_dist = _dist_text()
	v.add_child(omikuji_dist)


func _omikuji_spin(v: VBoxContainer, title: String, lo: float, hi: float, step: float, suffix: String) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var label := _label(title, 18)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.suffix = suffix
	spin.custom_minimum_size = Vector2(130, 0)
	spin.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spin.select_all_on_focus = true
	row.add_child(spin)
	return spin


func _show_omikuji_popup() -> void:
	omikuji_check.set_pressed_no_signal(omikuji.enabled)
	omikuji_chance.set_value_no_signal(omikuji.chance * 100.0)
	omikuji_limit.set_value_no_signal(omikuji.limit)
	_update_omikuji_summary()
	omikuji_popup.reset_size()
	# 風船の上に出す（膨らんでいても重ならないよう、風船のてっぺんより上）
	var s := omikuji_popup.get_combined_minimum_size()
	var x := clampf(BALLOON_POS.x - s.x / 2, 12, VIEW_SIZE.x - s.x - 12)
	var y := clampf(balloon.top_y() - 52 - s.y, 12, PANEL_TOP - s.y - 12)
	omikuji_popup.position = Vector2(x, y)
	omikuji_popup.visible = true


func _hide_omikuji_popup() -> void:
	# 入力途中の値を確定させる
	if omikuji_popup.visible:
		get_viewport().gui_release_focus()
	omikuji_popup.visible = false


func _update_omikuji_summary() -> void:
	_update_omikuji_dist()
	if not omikuji.enabled:
		omikuji_summary.text = "有効にすると、パチモンのメインスキルが1回出るたびにあたり／はずれを引きます。"
	else:
		omikuji_summary.text = "いまの連続はずれ %d回。上限%d回まではずれたら、次は必ずあたり。" % [omikuji.miss, omikuji.limit]


func _build_dist_popup(layer: CanvasLayer) -> void:
	dist_popup = PanelContainer.new()
	dist_popup.theme = SettingsPanel.make_theme(ui_theme)
	dist_popup.visible = false
	dist_popup.custom_minimum_size = Vector2(DIST_POPUP_W, 0)
	var sb := _style(CREAM, 22, 12)
	sb.set_border_width_all(3)
	sb.border_color = Color("e6cf9f")
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 8
	dist_popup.add_theme_stylebox_override("panel", sb)
	layer.add_child(dist_popup)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	dist_popup.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	dist_title = _label("", 22)
	dist_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(dist_title)
	var close := _button("×", Color("ffe9bf"), TEXT_DARK)
	close.custom_minimum_size = Vector2(48, 48)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(_hide_dist_popup)
	top.add_child(close)

	dist_chart = DistChart.new()
	dist_chart.custom_minimum_size = Vector2(0, DIST_CHART_H)
	v.add_child(dist_chart)

	dist_summary = _dist_text()
	v.add_child(dist_summary)

	miss_section = VBoxContainer.new()
	miss_section.add_theme_constant_override("separation", 8)
	v.add_child(miss_section)
	miss_section.add_child(HSeparator.new())
	miss_section.add_child(_label("スキル連続不発の分布", 20))
	miss_chart = _miss_chart("連続不発の回数")
	miss_section.add_child(miss_chart)
	miss_summary = _dist_text()
	miss_section.add_child(miss_summary)


## 連続不発・連続はずれの分布のグラフ（件数の棒＋理論上の分布）
func _miss_chart(x_title: String) -> DistChart:
	var chart := DistChart.new()
	chart.custom_minimum_size = Vector2(0, MISS_CHART_H)
	chart.bands = false
	chart.max_bars = MISS_MAX_BARS
	chart.x_title = x_title
	return chart


func _dist_text() -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.custom_minimum_size = Vector2(DIST_POPUP_W - 40, 0)
	t.add_theme_font_size_override("normal_font_size", 17)
	t.add_theme_color_override("default_color", TEXT_DARK)
	return t


func _on_hud_meta_clicked(meta: Variant) -> void:
	# フィールドのタップとして扱わない（_unhandled_input で欄が閉じないように）
	get_viewport().set_input_as_handled()
	if cutin_active:
		return
	var kind := str(meta)
	if dist_popup.visible and dist_popup_kind == kind:
		_hide_dist_popup()
		return
	_hide_box_popup()
	_hide_fairy_popup()
	_hide_sleep_popup()
	dist_popup_kind = kind
	_update_dist_popup()
	dist_popup.reset_size()
	dist_popup.visible = true
	_place_dist_popup()
	# 説明文の折り返しが決まってから高さを合わせる
	_place_dist_popup.call_deferred()


## 高さに合わせて置く。下にはみ出すときは上へずらす
func _place_dist_popup() -> void:
	dist_popup.reset_size()
	var y := minf(DIST_POPUP_Y, VIEW_SIZE.y - dist_popup.size.y - 16)
	dist_popup.position = Vector2((VIEW_SIZE.x - DIST_POPUP_W) / 2, maxf(16.0, y))


func _hide_dist_popup() -> void:
	dist_popup.visible = false
	dist_popup_kind = ""


## 確率分布のグラフと、実際の回数が分布のどこにいるか（下位・上位○%）
func _update_dist_popup() -> void:
	var d: Dist
	var actual: int
	var name: String
	if dist_popup_kind == "skill":
		d = sim.skill_dist
		actual = sim.totals["skills"]
		name = "スキル回数"
	else:
		d = sim.ingredient_dist
		actual = sim.totals["ingredient_helps"]
		name = "食材回数"
	dist_title.text = "%sの確率分布" % name
	dist_chart.show_dist(d, actual)
	var actual_text := "[color=%s]現時点での%d回[/color]" % [DistChart.ACTUAL_COLOR.to_html(false), actual]
	var lines := PackedStringArray()
	lines.append("%sは %s" % [actual_text, percentile_text(d, actual)])
	lines.append("[color=%s]期待値 %.1f回[/color]（破線）" % [DistChart.MEAN_COLOR.to_html(false), d.mean()])
	# 背景の色見本（グラフの左から：下位5%・下位5〜15%・期待値まわり70%・上位5〜15%・上位5%）
	var bands := [
		[DistChart.TAIL_BANDS[0][2], "下位5%"],
		[DistChart.TAIL_BANDS[1][2], "下位5〜15%"],
		[DistChart.BAND_COLOR, "期待値まわり70%"],
		[DistChart.TAIL_BANDS[2][2], "上位5〜15%"],
		[DistChart.TAIL_BANDS[3][2], "上位5%"],
	]
	var chips := PackedStringArray()
	for b in bands:
		chips.append("[bgcolor=%s] %s [/bgcolor]" % [(b[0] as Color).to_html(false), b[1]])
	lines.append("赤系は下位、青は期待値まわり70%、緑系は上位の範囲です。")
	lines.append(" ".join(chips))
	dist_summary.text = "\n".join(lines)
	miss_section.visible = dist_popup_kind == "skill"
	if miss_section.visible:
		_update_miss_dist()


## 実際に起きた連続不発の回数の集計（スキルが予約されるまでに続けて不発だった回数、予約1回で1件）。
## 今続いている不発カウントの位置を紫、連続不発上限の棒を赤、集計の平均を青の破線、理論上の平均を緑の破線、理論上の分布を緑の実線にする
func _update_miss_dist() -> void:
	miss_summary.text = _fill_miss_chart(miss_chart, sim.miss_runs, sim.params.skill_chance(), sim.params.skill_ceiling, sim.skill_miss, {
		"what": "スキルが予約されるまでに続けて不発だった回数を、予約1回で1件として数えています。",
		"event": "予約", "none": "まだスキルが予約されていません。", "now": "今の連続不発"})


## おみくじの設定欄の連続はずれの分布
func _update_omikuji_dist() -> void:
	omikuji_dist.text = _fill_miss_chart(omikuji_chart, omikuji.miss_runs, omikuji.chance, omikuji.limit, omikuji.miss, {
		"what": "あたりが出るまでに続けてはずれた回数を、あたり1回で1件として数えています。",
		"event": "あたり", "none": "まだあたりが出ていません。", "now": "今の連続はずれ"})


## 連続不発（連続はずれ）の集計 runs をグラフに入れ、説明の文を返す。
## p は1回で出る確率、ceiling は連続の上限（上限まで続いたら次は必ず出る）、miss は今続いている回数。
## words の event は「予約」「あたり」など1件に数えるできごと
func _fill_miss_chart(chart: DistChart, runs: PackedInt32Array, p: float, ceiling: int, miss: int, words: Dictionary) -> String:
	var total := 0
	var longest := 0
	for k in runs.size():
		total += runs[k]
		if runs[k] > 0:
			longest = k
	ceiling = maxi(0, ceiling)
	var theory := Sim.miss_run_mean(p, ceiling)
	# 集計が0件でも、軸と理論上の平均の破線は出す
	var d := Dist.new()
	d.p = PackedFloat64Array()
	d.p.resize(maxi(runs.size(), ceiling + 1))
	for k in runs.size():
		d.p[k] = float(runs[k]) / total if total > 0 else 0.0
	chart.accent = ceiling
	chart.count_total = maxi(total, 1)
	chart.x_range = Vector2i(0, ceiling)
	chart.show_mean = total > 0
	chart.ref_mean = theory
	# 理論上の分布は確率のまま、右の目盛り（%）で重ねる。0件のときも出す
	chart.ref_pmf = Sim.miss_run_pmf(p, ceiling)
	chart.ref_axis = true
	chart.show_dist(d, miss)
	var lines := PackedStringArray()
	lines.append(words["what"])
	lines.append("[color=%s]理論上の平均 %.1f回[/color]（緑の破線）" % [DistChart.REF_COLOR.to_html(false), theory])
	lines.append("[color=%s]理論上の分布[/color]（緑の実線、右の目盛りで確率）" % DistChart.REF_COLOR.to_html(false))
	if total > 0:
		lines.append("集計 %d件　[color=%s]平均 %.1f回[/color]（青の破線）　最長 %d回　[color=%s]上限%d回で%s %d件[/color]" % [
			total, DistChart.MEAN_COLOR.to_html(false), d.mean(), longest,
			DistChart.ACCENT_COLOR.to_html(false), ceiling, words["event"], runs[ceiling] if ceiling < runs.size() else 0])
	else:
		lines.append(words["none"])
	lines.append("[color=%s]%s %d回[/color]（%sが出たら集計に入ります）" % [DistChart.ACTUAL_COLOR.to_html(false), words["now"], miss, words["event"]])
	return "\n".join(lines)


## 実際の回数 x が分布の下側・上側のどちらに寄っているかを「下位○%」「上位○%」で表す。
## 下位は x 回以下になる確率、上位は x 回以上になる確率で、小さいほうを出す。
static func percentile_text(d: Dist, x: int) -> String:
	var lower := d.at_most(x)
	var upper := d.at_least(x)
	if lower <= upper:
		return "下位 %s（%d回以下になる確率）" % [_pct_text(lower), x]
	return "上位 %s（%d回以上になる確率）" % [_pct_text(upper), x]


static func _pct_text(v: float) -> String:
	var pct := v * 100.0
	if pct < 0.1:
		return "0.1%未満"
	return "%.1f%%" % pct


## 眠る。そのあいだもおてつだいは進み、起きた時点でげんきが回復する。妖精は回復するものだけが眠る
func _on_sleep() -> void:
	if cutin_active:
		return
	_hide_sleep_popup()
	_hide_box_popup()
	sim.sleep(sleep_minutes)
	for f in fairies:
		f.sim.sleep(sleep_minutes, f.heals and _fairies_shown())
	clock.show_elapsed(sim.elapsed_sec)
	_refresh()


## フィールドの机をタップすると、画面右からせり出す、おてつだい1回ごとの記録。
## 設定パネルと同じく中央寄せのずらし（_layer）は使わず、画面右端に付ける
func _build_log_view() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	side_layers.append(layer)
	# 狭い画面ではパネルがフィールドに重なる。外側のタップはここで受けて閉じる
	log_scrim = ColorRect.new()
	log_scrim.color = Color(0, 0, 0, 0.35)
	log_scrim.visible = false
	log_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	log_scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_set_log_open(false))
	layer.add_child(log_scrim)

	log_panel = PanelContainer.new()
	log_panel.theme = ui_theme
	log_panel.visible = false
	var sb := _style(CREAM, 0, 18)
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	sb.corner_radius_top_left = 28
	sb.corner_radius_bottom_left = 28
	sb.border_width_left = 4
	sb.border_color = Color("e6cf9f")
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 12
	log_panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(log_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	log_panel.add_child(v)

	var top := HBoxContainer.new()
	v.add_child(top)
	log_title = _label("", 24)
	log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(log_title)
	var close := _button("×", Color("ffe9bf"), TEXT_DARK)
	close.custom_minimum_size = Vector2(56, 56)
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(_set_log_open.bind(false))
	top.add_child(close)

	v.add_child(HelpLogTable.new(true))
	log_scroll = ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(log_scroll)
	log_table = HelpLogTable.new()
	log_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_table)
	log_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: log_table.queue_redraw())
	log_scroll.resized.connect(log_table.queue_redraw)


func _set_log_open(open: bool) -> void:
	if open == log_open:
		return
	log_open = open
	_refresh()
	if open:
		_update_log()
		log_scroll.scroll_vertical = 0
	if log_tween != null:
		log_tween.kill()
	log_tween = create_tween()
	log_tween.tween_method(_set_log_slide, log_slide, 1.0 if open else 0.0, SETTINGS_SLIDE_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_center_layers()


func _set_log_slide(t: float) -> void:
	log_slide = t
	_center_layers()


## 開いたままでも「すすめる」やリセットに合わせて記録を更新する
func _update_log() -> void:
	log_title.text = "おてつだいの記録（全%d回）" % sim.totals["helps"]
	var slots: Array = sim.params.ingredients.map(func(ing: Dictionary) -> String: return ing["id"])
	log_table.set_log(sim.help_log, slots, sim.params.active_ingredients().size())


## 設定パネルは画面の左端に付けるので、中央寄せのずらし（_layer）は使わない
func _build_settings() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	side_layers.append(layer)
	# 狭い画面ではパネルがフィールドに重なる。外側のタップはここで受けて閉じる
	settings_scrim = ColorRect.new()
	settings_scrim.color = Color(0, 0, 0, 0.35)
	settings_scrim.visible = false
	settings_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_set_settings_open(false))
	layer.add_child(settings_scrim)
	settings = SettingsPanel.new()
	settings.presets = presets
	settings.setup(sim.params, ui_theme)
	settings.visible = false
	settings.changed.connect(_on_params_changed)
	settings.stored.connect(_on_preset_stored)
	settings.close_requested.connect(_set_settings_open.bind(false))
	layer.add_child(settings)


func _set_settings_open(open: bool) -> void:
	if open == settings_open:
		return
	settings_open = open
	_refresh()
	if not open:
		# 入力途中の数値を確定させる
		get_viewport().gui_release_focus()
	if settings_tween != null:
		settings_tween.kill()
	settings_tween = create_tween()
	settings_tween.tween_method(_set_settings_slide, settings_slide, 1.0 if open else 0.0, SETTINGS_SLIDE_SEC) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_center_layers()


func _set_settings_slide(t: float) -> void:
	settings_slide = t
	_center_layers()


func _on_params_changed() -> void:
	sim.clamp_stock()
	_refresh()


## 設定パネルで枠 k に記憶したら、その枠に変身している妖精にもすぐ入れ直す
func _on_preset_stored(k: int) -> void:
	for f in fairies:
		if f.preset == k and presets.restore(k, f.sim.params):
			f.sim.clamp_stock()
	if fairy_popup_index >= 0:
		_update_fairy_summary()
	_refresh()


## チーム全体の設定（おてつだいボーナスの数・いいキャンプチケット）をパチモンと妖精の全員に入れる。
## 次の「すすめる」から反映される
func _set_team(key: String, value: Variant) -> void:
	var all: Array[Sim] = [sim]
	for f in fairies:
		all.append(f.sim)
	for s in all:
		s.params.set(key, value)
		s.clamp_stock()
	bed.canopy = sim.params.camp_ticket
	settings.refresh_summary()
	if fairy_popup_index >= 0:
		_update_fairy_summary()
	_refresh()


func _style(color: Color, radius: int, pad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad * 1.5
	sb.content_margin_right = pad * 1.5
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_DARK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _apply_button_styles(b: Control, color: Color, text_color: Color) -> void:
	b.add_theme_stylebox_override("normal", _style(color, 18, 8))
	b.add_theme_stylebox_override("hover", _style(color.lightened(0.08), 18, 8))
	b.add_theme_stylebox_override("pressed", _style(color.darkened(0.12), 18, 8))
	b.add_theme_stylebox_override("disabled", _style(color.darkened(0.25), 18, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, text_color)
	b.focus_mode = Control.FOCUS_NONE


func _button(text: String, color: Color, text_color: Color) -> Button:
	var b := Button.new()
	b.text = text
	_apply_button_styles(b, color, text_color)
	return b


# 押した瞬間に1回反応し、押しっぱなしならしばらく待ってから連続で反応させる
func _add_hold_repeat(b: Button, action: Callable) -> void:
	var timer := Timer.new()
	b.add_child(timer)
	timer.timeout.connect(func() -> void:
		timer.start(REPEAT_INTERVAL_SEC)
		action.call())
	b.button_down.connect(func() -> void:
		action.call()
		timer.start(REPEAT_DELAY_SEC))
	b.button_up.connect(timer.stop)


func _toggle() -> Button:
	var b := _button("", Color("ffe9bf"), TEXT_DARK)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 18)
	return b


# ---------------------------------------------------------------- 操作

func _change_hours(delta: int) -> void:
	hours = clampi(hours + delta, MIN_HOURS, MAX_HOURS)
	_refresh()


func _on_advance() -> void:
	if cutin_active:
		return
	_hide_box_popup()
	sim.advance(hours * 3600.0)
	for f in fairies:
		if f.heals and _fairies_shown():
			f.sim.advance(hours * 3600.0)
		else:
			f.sim.idle(hours * 3600.0)
	clock.show_elapsed(sim.elapsed_sec)
	_refresh()


func _on_genki_toggled() -> void:
	var decay := sim.genki_mode == Sim.GenkiMode.ALWAYS_HIGH
	sim.set_genki_mode(Sim.GenkiMode.DECAY if decay else Sim.GenkiMode.ALWAYS_HIGH)
	for f in fairies:
		f.sim.set_genki_mode(sim.genki_mode)
		# 「81以上で固定」のあいだ妖精はいないので、出てきた時点からおてつだいを始める
		if decay and f.heals:
			f.sim.restart_help()
	if not decay:
		_hide_fairy_popup()
	if sleep_popup.visible:
		_update_sleep_popup()
	_refresh()


## げんきの初期値を変えたとき。パチモンも妖精も、今のげんきがその値から減り始め直す
func _on_genki_start_changed(x: float) -> void:
	sim.set_genki_start(int(x))
	for f in fairies:
		f.sim.set_genki_start(int(x))
	if sleep_popup.visible:
		_update_sleep_popup()
	_refresh()


func _on_reset() -> void:
	if cutin_active:
		return
	sim.reset()
	for f in fairies:
		f.sim.reset()
	omikuji.reset()
	clock.show_elapsed(sim.elapsed_sec, false)
	for id in piles:
		piles[id].queue_free()
	piles.clear()
	for t in toast_box.get_children():
		t.queue_free()
	_hide_box_popup()
	_hide_sleep_popup()
	_hide_omikuji_popup()
	_hide_view_popup()
	_hide_dist_popup()
	_refresh()


## 時計の針が回るのに合わせて、昼・夕方・夜の境目を越えたら背景の色を変える
func _on_time_shown(sec: float) -> void:
	var p := FieldClock.phase_at(sec)
	if p == phase:
		return
	phase = p
	if phase_tween != null:
		phase_tween.kill()
	phase_tween = create_tween()
	phase_tween.tween_property(phase_tint, "color", PHASE_TINTS[p], PHASE_FADE_SEC)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		swiping = false
		return
	if event is InputEventMouseMotion and swiping and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_on_swipe(_field_pos(event))
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p := _field_pos(event)
	if p.y > PANEL_TOP or cutin_active:
		return
	get_viewport().set_input_as_handled()
	# 設定パネルの入力欄を編集中なら確定させる
	get_viewport().gui_release_focus()
	# 押したままフィールド上をなぞると、通った山を回収する
	swiping = true
	swipe_last = p
	swiped.clear()
	var had_popup := box_popup.visible
	_hide_box_popup()
	var had_fairy_popup := fairy_popup_index
	_hide_fairy_popup()
	var had_sleep_popup := sleep_popup.visible
	_hide_sleep_popup()
	var had_omikuji_popup := omikuji_popup.visible
	_hide_omikuji_popup()
	var had_view_popup := view_popup.visible
	_hide_view_popup()
	_hide_dist_popup()
	for id in piles:
		if piles[id].hit(p):
			swiped[id] = true
			_collect(id)
			return
	if pseudon.hit(p):
		# アイコンが出ていなければ設定パネルを開け閉めする
		if sim.has_icon():
			_on_pseudon_tap()
		else:
			_set_settings_open(not settings_open)
		return
	for i in fairies.size():
		if _fairies_shown() and fairy_views[i].hit(p):
			# アイコンが出ていなければ（回復しない設定ならいつでも）設定欄を開け閉めする
			if fairies[i].heals and fairies[i].sim.has_icon():
				_on_fairy_tap(i)
			elif had_fairy_popup != i:
				_show_fairy_popup(i)
			return
	if gear.hit(p):
		if not had_view_popup:
			_show_view_popup()
		return
	if balloon.hit(p):
		if not had_omikuji_popup:
			_show_omikuji_popup()
		return
	if bed.hit(p):
		if not had_sleep_popup:
			_show_sleep_popup()
		return
	if desk.hit(p):
		_set_log_open(not log_open)
		return
	if box_shown and storage_box.hit(p):
		if not had_popup:
			_show_box_popup(storage_box)
		return


func _field_pos(event: InputEventMouse) -> Vector2:
	return actor_root.get_global_transform_with_canvas().affine_inverse() * event.position


func _on_swipe(p: Vector2) -> void:
	if cutin_active:
		swiping = false
		return
	get_viewport().set_input_as_handled()
	# 速くなぞっても取りこぼさないよう、前回の位置との間を細かく調べる
	var steps := maxi(1, ceili(swipe_last.distance_to(p) / (ItemPile.HIT_RADIUS * 0.5)))
	for i in range(1, steps + 1):
		var q := swipe_last.lerp(p, float(i) / steps)
		if q.y > PANEL_TOP:
			continue
		for id in piles:
			if not swiped.has(id) and piles[id].hit(q):
				swiped[id] = true
				_collect(id)
	swipe_last = p


func _on_pseudon_tap() -> void:
	var result := sim.drop()
	var stock: int = result["stock"]
	_spawn_drops(result["items"])
	if stock > 0:
		# おみくじはスキル1回（ストック1つ）ごとに引く。結果はカットインの「！」のあとで見せる
		var lot := omikuji.draw_for(stock)
		_start_cutin(pseudon, stock, _skill_lines(sim.params, result["ceiling"], "肌のツヤが%dポイントアップ！" % stock), lot)
	_refresh()


## 妖精をタップしたとき。持っていたきのみ・食材は消え、スキルのストックがあればパチモン・妖精のげんきを増減する
func _on_fairy_tap(i: int) -> void:
	var f := fairies[i]
	var result := f.sim.drop(false)
	var stock: int = result["stock"]
	if stock > 0:
		var amount := f.heal_for(stock)
		# 効果の対象にチェックの入っているもの（妖精は回復しているものだけ）
		var names := PackedStringArray()
		if f.targets[0]:
			sim.add_genki(amount)
			names.append("パチモン")
		for j in fairies.size():
			if f.targets[j + 1] and fairies[j].heals and _fairies_shown():
				fairies[j].sim.add_genki(amount)
				names.append(fairies[j].label)
		var effect := "だれにも効かなかった！"
		if not names.is_empty():
			effect = "%sのげんきが%dポイント%s！" % ["と".join(names), absi(amount), "ダウン" if amount < 0 else "アップ"]
		_start_cutin(fairy_views[i], stock, _skill_lines(f.sim.params, result["ceiling"], effect))
	else:
		# 連続不発上限に近いほど深く沈む（上限でパチモンの手の高さ）
		fairy_views[i].fizzle(float(f.sim.skill_miss) / maxi(1, f.sim.params.skill_ceiling))
	_refresh()


## 妖精を出すか。げんきが「81以上で固定」のあいだは回復の意味がないので出さない
func _fairies_shown() -> bool:
	return sim.genki_mode == Sim.GenkiMode.DECAY


func _collect(id: String) -> void:
	var pile: ItemPile = piles[id]
	var got := sim.collect(id)
	if got > 0:
		pile.set_count(pile.count - got)
		_toast(id, "×%d" % got)
	else:
		var kind_name := "きのみ" if sim.params.is_berry(id) else "食材"
		_toast(id, "%sがいっぱい" % kind_name)
		pile.bounce()
	_refresh()


# ---------------------------------------------------------------- ぽこぽこ

func _pile_position(id: String) -> Vector2:
	var ids := sim.params.item_ids()
	var i := ids.find(id)
	return Vector2(PSEUDON_POS.x + (i - (ids.size() - 1) / 2.0) * PILE_GAP, PILE_Y)


func _get_pile(id: String) -> ItemPile:
	if not piles.has(id):
		var pile := ItemPile.new()
		pile.item_id = id
		pile.position = _pile_position(id)
		actor_root.add_child(pile)
		actor_root.move_child(pile, 0)
		piles[id] = pile
	return piles[id]


func _spawn_drops(items: Dictionary) -> void:
	var delay := 0.0
	for id in sim.params.item_ids():
		var n := int(items.get(id, 0))
		if n <= 0:
			continue
		var pile := _get_pile(id)
		# 個数が多いときは何個かずつまとめて飛ばす
		var hops := mini(n, 6)
		for k in hops:
			var amount := n / hops + (1 if k < n % hops else 0)
			_launch(id, amount, pile, delay, k)
			delay += 0.11


func _launch(id: String, amount: int, pile: ItemPile, delay: float, k: int) -> void:
	var fly := FlyingItem.new()
	fly.item_id = id
	fly.visible = false
	var to := pile.position + Vector2((k % 3 - 1) * 10, -8)
	actor_root.add_child(fly)
	var tw := fly.create_tween()
	tw.tween_interval(delay)
	# 出す瞬間の手の位置から飛ばす（体はふわふわ動いている）
	var from := {"pos": Vector2.ZERO}
	tw.tween_callback(func():
		from["pos"] = pseudon.hand_position(id)
		fly.position = from["pos"]
		fly.visible = true
	)
	tw.tween_method(func(t: float): fly.position = _arc(from["pos"], to, t), 0.0, 1.0, 0.42)
	tw.tween_callback(func():
		var on_field := int(sim.on_field.get(id, 0))
		pile.set_count(mini(pile.count + amount, on_field))
		pile.bounce()
		fly.queue_free()
	)


func _arc(from: Vector2, to: Vector2, t: float) -> Vector2:
	var p := from.lerp(to, t)
	p.y -= sin(t * PI) * 90.0
	return p


# ---------------------------------------------------------------- メインスキルのカットイン

## スキルの吹き出しの文。天井で出た分があれば「スキル天井をたたいた！」を挟む
func _skill_lines(p: Params, by_ceiling: int, effect: String) -> PackedStringArray:
	var lines := PackedStringArray(["%sのメインスキル！" % p.pseudon_name])
	if by_ceiling > 0:
		lines.append("スキル天井をたたいた！")
	lines.append(effect)
	return lines


## actor（パチモンか妖精）の頭上に「!」を出してから、スキルの吹き出しを出す
## lot はおみくじの結果（Omikuji.draw_for）。パチモンのときだけ渡す
func _start_cutin(actor: Node2D, stock: int, lines: PackedStringArray, lot := {}) -> void:
	cutin_active = true
	cutin_closable = false
	cutin_actor = actor
	_hide_box_popup()
	blocker.visible = true
	create_tween().tween_property(dim, "modulate:a", 1.0, 0.15)
	actor.show_exclaims(stock)
	await get_tree().create_timer(CUTIN_PAUSE_SEC).timeout
	if not cutin_active:
		return
	# おみくじ: あたりなら風船を割って花火、はずれなら膨らませる。演出のあとで吹き出しを出す
	if lot.get("hits", 0) > 0:
		var grand: bool = lot["tier"] == Omikuji.Tier.GRAND
		if grand:
			# 上限であたったときは、設定パネルと記録パネルを隠して画面いっぱいに見せる
			_show_side_panels(false)
			# カウントダウンが0になるのを見せ、さらに3倍まで膨らませてから割る
			balloon.set_state(0, 1.0)
			await get_tree().create_timer(GRAND_COUNTDOWN_SEC).timeout
			balloon.overinflate(GRAND_INFLATE, GRAND_INFLATE_SEC)
			await get_tree().create_timer(GRAND_INFLATE_SEC + 0.1).timeout
			if not cutin_active:
				_show_side_panels(true)
				return
		await get_tree().create_timer(_pop_balloon(lot["tier"])).timeout
		if grand:
			_show_side_panels_after_fireworks()
		if not cutin_active:
			return
	elif not lot.is_empty():
		_sync_balloon(true)
	bubble_label.text = "\n".join(lines)
	bubble.visible = true
	bubble.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cutin_closable = true


func _on_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and cutin_closable:
		_end_cutin()


func _end_cutin() -> void:
	cutin_active = false
	cutin_closable = false
	bubble.visible = false
	cutin_actor.show_exclaims(0)
	create_tween().tween_property(dim, "modulate:a", 0.0, 0.2)
	blocker.visible = false
	if balloon_respawn:
		balloon_respawn = false
		get_tree().create_timer(0.2).timeout.connect(func() -> void: balloon.respawn(omikuji.remaining(), omikuji.ratio()))
	else:
		_sync_balloon()


## 設定パネルと記録パネルを出す／隠す（開いていたパネルは開いたまま戻る）
func _show_side_panels(on: bool) -> void:
	for layer in side_layers:
		layer.visible = on


## 降ってくるきのみなどの演出がすべて終わってから、設定パネルと記録パネルを出す
func _show_side_panels_after_fireworks() -> void:
	while fireworks.is_running():
		await get_tree().process_frame
	_show_side_panels(true)


## 風船を割って段階 tier の花火を始める。吹き出しを出すまで待つ秒数を返す
func _pop_balloon(tier: int) -> float:
	var wait := fireworks.start(tier, balloon.center(), balloon.body_color(), FIREWORKS_AREA)
	balloon.pop()
	balloon_respawn = true
	return wait


# ---------------------------------------------------------------- 表示

func _toast(id: String, text: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.add_theme_stylebox_override("panel", _style(Color(1, 1, 1, 0.92), 20, 6))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ItemIcon.new(id))
	row.add_child(_label("%s %s" % [sim.params.item_name(id), text], 18))
	panel.add_child(row)
	toast_box.add_child(panel)
	var tw := panel.create_tween()
	tw.tween_interval(TOAST_SEC)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


func _show_box_popup(box: StorageBox) -> void:
	var lines: Array[String] = []
	lines.append("きのみ %d/%d" % [Sim.sum(sim.berry_box), Sim.BERRY_BOX_MAX])
	lines.append("食材　%d/%d" % [Sim.sum(sim.ingredient_box), Sim.INGREDIENT_BOX_MAX])
	for ing in sim.params.ingredients:
		lines.append("%s %d" % [ing["name"], int(sim.ingredient_box.get(ing["id"], 0))])
	box_popup_label.text = "\n".join(lines)
	box_popup.reset_size()
	box_popup.visible = true
	var s := box_popup.get_combined_minimum_size()
	var x := clampf(box.position.x - s.x / 2, 12, VIEW_SIZE.x - s.x - 12)
	box_popup.position = Vector2(x, box.position.y - 70 - s.y)
	var timer := get_tree().create_timer(3.0)
	box_popup_timer = timer
	timer.timeout.connect(func():
		if box_popup_timer == timer:
			_hide_box_popup()
	)


func _hide_box_popup() -> void:
	box_popup.visible = false
	box_popup_timer = null


## 期待値のかっこ書き（小数第1位まで）
func _expected_text(v: float) -> String:
	return "（%.1f）" % v


## 期待値の横の (i)。押すと確率分布のグラフを出す（_on_hud_meta_clicked）。
## 指でも押しやすいよう、前後の空白も押せる範囲に入れる
func _info_link(kind: String) -> String:
	return "[url=%s][color=%s] ⓘ  [/color][/url]" % [kind, DistChart.MEAN_COLOR.to_html(false)]


func _format_hours(sec: float) -> String:
	var total_min := int(round(sec / 60.0))
	return "%d時間%02d分" % [total_min / 60, total_min % 60]


## 風船に今のはずれ回数と割合を入れる。カットイン中は「！」のあとまで前の状態のままにする
func _sync_balloon(now := false) -> void:
	balloon.floating = omikuji.enabled
	if cutin_active and not now:
		return
	balloon.set_state(omikuji.remaining(), omikuji.ratio())


func _refresh() -> void:
	pseudon.ribbon_tier = sim.params.ribbon_tier()
	pseudon.help_bonus = sim.params.help_bonus_count
	hours_label.text = "%d時間" % hours
	advance_button.text = "%d時間分すすめる" % hours
	genki_button.text = "げんき：81以上で固定" if sim.genki_mode == Sim.GenkiMode.ALWAYS_HIGH else "げんき：%dから減少" % sim.genki_start
	genki_start_row.visible = sim.genki_mode == Sim.GenkiMode.DECAY
	var genki := "81以上"
	if sim.genki_mode == Sim.GenkiMode.DECAY:
		genki = str(sim.genki_at(sim.elapsed_sec))
		for f in fairies:
			if f.heals:
				genki += "・%s %d" % [f.label, f.sim.genki_at(f.sim.elapsed_sec)]
	# おてつだいの累計（リセットで 0 に戻る）
	var t := sim.totals
	var ceiling_count := "%d回" % t["skill_ceiling_hits"]
	if t["skill_ceiling_hits"] > 0:
		ceiling_count = "[color=%s]%s[/color]" % [CEILING_COLOR.to_html(false), ceiling_count]
	# 「○回」の縦位置をそろえるため、項目名・回数・期待値の3列の表にする。
	# 期待値は「すすめる」ごとに二項分布で求めた値の合計（Sim._add_expected）
	var rows := [
		["おてつだい回数", "%d回" % t["helps"], "（）内は期待値"],
		["きのみ回数", "%d回" % t["berry_helps"], _expected_text(t["exp_berry_helps"])],
		["食材回数", "%d回" % t["ingredient_helps"], _expected_text(t["exp_ingredient_helps"]) + _info_link("ingredient")],
		["スキル回数", "%d回" % t["skills"], _expected_text(t["exp_skills"]) + _info_link("skill")],
		["　うち天井", ceiling_count, ""],
		["いつのまに育成回数", "%d回" % t["full_helps"], ""],
	]
	var table := "[table=3]"
	for row in rows:
		table += "[cell padding=0,0,16,0]%s[/cell][cell][right]%s[/right][/cell][cell]%s[/cell]" % row
	table += "[/table]"
	hud_label.text = "%s（Lv.%d）\n経過 %s ・ げんき %s\n%s" % [
		sim.params.pseudon_name, sim.params.level, _format_hours(sim.elapsed_sec), genki, table]
	if dist_popup.visible:
		_update_dist_popup()
	_sync_balloon()
	if omikuji_popup.visible:
		_update_omikuji_summary()

	pseudon.show_icon = sim.has_icon()
	pseudon.show_menu = not pseudon.show_icon and not settings_open
	pseudon.icon_full = sim.is_full()
	for i in fairies.size():
		var f := fairies[i]
		var fv := fairy_views[i]
		fv.visible = _fairies_shown()
		fv.active = f.heals
		fv.show_icon = f.heals and f.sim.has_icon()
		# 回復しない設定のときはいつも「…」（設定欄を開いているあいだは出さない）
		fv.show_menu = not fv.show_icon and fairy_popup_index != i
		fv.icon_full = f.sim.is_full()

	var lines: Array[String] = []
	if sim.elapsed_sec == 0.0:
		lines.append("「すすめる」でおてつだいを進めます。")
		lines.append("パチモンのアイコンをタップすると結果が出ます。")
	var stock_note := ""
	if sim.ceiling_stock > 0:
		stock_note = " [bgcolor=%s][color=#ffffff] 天井%s [/color][/bgcolor]" % [
			CEILING_COLOR.to_html(false), "" if sim.ceiling_stock == sim.skill_stock else "×%d" % sim.ceiling_stock]
	lines.append("所持 %d/%d　スキルストック %d/%d%s　スキル天井まで あと%d回" % [
		sim.held_count(), sim.params.carry_limit(), sim.skill_stock, sim.params.max_skill_stock, stock_note,
		maxi(1, sim.params.skill_ceiling + 1 - sim.skill_miss)])
	status_label.text = "\n".join(lines)
	if log_open:
		_update_log()
