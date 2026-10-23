extends SceneTree
## ロジックのテスト。 godot --headless -s res://tests/test_sim.gd で実行する。
## 基礎資料「おてつだい計算モデル」の計算例その1・その2と突き合わせる。
## 計算例はレベル補正なし・最大所持数25・食材2枠なので、そのパラメータを組んで使う。
## 計算例は毎回タップする前提なので、スキルのストックも毎回空にしながら進める。

const Sim = preload("res://scripts/sim.gd")
const Params = preload("res://scripts/params.gd")
const FieldClock = preload("res://scripts/field_clock.gd")
const Presets = preload("res://scripts/presets.gd")
const Dist = preload("res://scripts/dist.gd")
const Main = preload("res://scripts/main.gd")
const HelpLogTable = preload("res://scripts/help_log_table.gd")
const Omikuji = preload("res://scripts/omikuji.gd")

var failures := 0


func _init() -> void:
	_test_level_factor()
	_test_default_params()
	_test_modifiers()
	_test_event()
	_test_ex_mode()
	_test_camp_ticket()
	_test_presets()
	_test_preset_defaults()
	_test_slots_by_level()
	_test_subskill_slots()
	_test_skill_ceiling()
	_test_skill_ceiling_stock2()
	_test_miss_runs_tap()
	_test_skill_miss_reset_on_tap()
	_test_omikuji()
	_test_tap_log()
	_test_day_summary()
	_test_add_genki()
	_test_genki_start()
	_test_genki_nature()
	_test_fairy_sim()
	_test_sleep()
	_test_name_width()
	_test_example1_help_count()
	_test_example2_help_count()
	_test_carry_over()
	_test_example1_distribution()
	_test_example2_distribution()
	_test_capacity()
	_test_skill_stock()
	_test_collect_limits()
	_test_time_phase()
	_test_expected_values()
	_test_distributions()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   ", label)
	else:
		failures += 1
		printerr("  FAIL ", label)


## 計算例のパラメータ（基準2600秒・レベル補正なし・最大所持数25・食材2個/3個の2枠）
func _example_params() -> Params:
	var p := Params.new()
	p.base_help_sec = 2600.0
	p.level = 1
	p.ingredient_prob = 0.25
	p.skill_prob = 0.05
	p.skill_ceiling = 78
	p.max_carry = 25
	p.berries_per_help = 2
	p.max_skill_stock = 1
	p.unlock_slots_by_level = false
	p.ingredients = [
		{"id": "ing_a", "name": "食材A", "amount": 2},
		{"id": "ing_b", "name": "食材B", "amount": 3},
	]
	return p


func _tapping_sim() -> Sim:
	# 「毎回タップ」は所持数があふれない状態なので、最大所持数を十分大きくして表す
	var p := _example_params()
	p.max_carry = 1000000
	return Sim.new(p)


func _test_level_factor() -> void:
	print("レベル補正")
	check(Params.level_factor(1) == 1.0, "Lv.1は1")
	check(_near(Params.level_factor(60), 0.882, 1e-9), "Lv.60は0.882 (got %f)" % Params.level_factor(60))
	var p := Params.new()
	p.base_help_sec = 2400.0
	p.level = 60
	check(p.help_sec() == 2116.0, "2400秒×0.882=2116.8は2116秒 (got %f)" % p.help_sec())


func _test_default_params() -> void:
	print("初期パラメータ（基準2200秒・Lv.60・最大所持数22・スキルストック2・天井65・食材1/2/4個）")
	var p := Params.new()
	check(p.help_sec() == 1940.0, "2200秒×0.882=1940.4は1940秒 (got %f)" % p.help_sec())
	check(p.carry_limit() == 22, "最大所持数22")
	check(p.max_skill_stock == 2, "スキルストック上限2")
	check(p.skill_ceiling == 65, "スキル連続不発上限65")
	check(_near(p.ingredient_chance(), 0.151, 1e-9) and _near(p.skill_chance(), 0.039, 1e-9), "食材確率15.1%・スキル確率3.9%")
	check(p.berry_amount() == 1, "きのみ1個")
	var amounts := []
	for ing in p.ingredients:
		amounts.append(ing["amount"])
	check(amounts == [1, 2, 4], "食材枠の数 1/2/4 (got %s)" % str(amounts))
	p.max_carry = 1000000
	var s := Sim.new(p)
	var r := s.advance(16 * 3600.0)
	# 57600 ÷ (1940×0.45) = 65.9…
	check(r["helps"] == 65, "げんき81以上16時間でおてつだい65回 (got %d)" % r["helps"])
	# 食材枠は3枠から等確率
	var counts := {"ing_a": 0, "ing_b": 0, "ing_c": 0}
	s.rng.seed = 42
	for i in 3000:
		s.reset()
		var items: Dictionary = s.advance(16 * 3600.0)["items"]
		counts["ing_a"] += int(items.get("ing_a", 0)) / 1
		counts["ing_b"] += int(items.get("ing_b", 0)) / 2
		counts["ing_c"] += int(items.get("ing_c", 0)) / 4
	var total := float(counts["ing_a"] + counts["ing_b"] + counts["ing_c"])
	for id in counts:
		check(_near(counts[id] / total, 1.0 / 3.0, 0.02), "%sが選ばれる割合 約1/3 (got %.3f)" % [id, counts[id] / total])


func _test_modifiers() -> void:
	print("サブスキル・せいかく・おやすみリボンの補正")
	var p := Params.new()
	p.base_help_sec = 2400.0
	p.subskills = {"speed_m": true}
	# 基礎資料の計算例: 2400×0.882×0.86 = 1820.448
	check(p.help_sec() == 1820.0, "おてつだいスピードMで1820秒 (got %f)" % p.help_sec())
	p.subskills = {"speed_m": true, "speed_s": true}
	p.help_bonus_count = 5
	# 0.14+0.07+0.05×5 = 0.46 → 上限0.35
	check(_near(p.speed_reduction(), 0.35, 1e-9), "短縮は35%%で頭打ち (got %f)" % p.speed_reduction())
	p.subskills = {}
	p.help_bonus_count = 3
	check(_near(p.speed_reduction(), 0.15, 1e-9), "おてつだいボーナス3つで15%%")
	p.help_bonus_count = 0
	p.nature_up = Params.Nature.SPEED
	check(p.help_sec() == floorf(2400.0 * 0.882 * 0.9), "せいかくでおてつだいスピード上昇は時間0.9倍")
	p.nature_up = Params.Nature.NONE
	p.nature_down = Params.Nature.SPEED
	check(p.help_sec() == floorf(2400.0 * 0.882 * 1.075), "せいかくでおてつだいスピード下降は時間1.075倍")
	p.nature_down = Params.Nature.NONE
	p.ribbon_sleep_hours = 2000
	check(p.help_sec() == floorf(2400.0 * 0.882), "最終進化形はリボンで時間が変わらない")
	check(p.carry_limit() == 22 + 8, "リボン2000時間で最大所持数+8")
	p.evolutions_left = 1
	check(p.help_sec() == floorf(2400.0 * 0.882 * 0.88), "あと1回進化・2000時間で0.88倍")
	p.evolutions_left = 2
	p.ribbon_sleep_hours = 500
	check(p.help_sec() == floorf(2400.0 * 0.882 * 0.89), "あと2回進化・500時間で0.89倍")
	check(p.carry_limit() == 22 + 3, "リボン500時間で最大所持数+3")
	p.ribbon_sleep_hours = 199
	check(p.help_sec() == floorf(2400.0 * 0.882) and p.carry_limit() == 22, "200時間未満は補正なし")
	var tiers := []
	for h in [0, 199, 200, 499, 500, 999, 1000, 1999, 2000, 99999]:
		p.ribbon_sleep_hours = h
		tiers.append(p.ribbon_tier())
	check(tiers == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4], "リボンの段階は200・500・1000・2000時間で上がる (got %s)" % [tiers])
	p.ribbon_sleep_hours = 199
	p.subskills = {"carry_l": true, "carry_m": true, "carry_s": true, "berry_s": true}
	check(p.carry_limit() == 22 + 18 + 12 + 6, "最大所持数アップL・M・S")
	check(p.berry_amount() == 2, "きのみの数Sで+1個")
	p.ingredient_prob = 0.2
	p.skill_prob = 0.05
	p.subskills = {"ing_m": true, "ing_s": true, "skill_s": true}
	p.nature_up = Params.Nature.INGREDIENT
	p.nature_down = Params.Nature.SKILL
	check(_near(p.ingredient_chance(), 0.2 * 1.2 * 1.54, 1e-9), "食材確率 = 基準×せいかく1.2×(1+0.36+0.18) (got %f)" % p.ingredient_chance())
	check(_near(p.skill_chance(), 0.05 * 0.8 * 1.18, 1e-9), "スキル確率 = 基準×せいかく0.8×(1+0.18) (got %f)" % p.skill_chance())


func _test_event() -> void:
	print("イベント補正")
	var p := Params.new()
	p.event_berry_add = 2
	p.event_ingredient_add = 1
	p.event_skill_mult = 1.5
	p.event_carry_add = 10
	p.event_carry_mult = 1.5
	# OFF のあいだは値を入れても効かない
	check(p.carry_limit() == 22 and p.berry_amount() == 1 and p.ingredient_amount(p.ingredients[0]) == 1, "OFF なら補正なし")
	check(_near(p.skill_chance(), 0.039, 1e-9), "OFF ならスキル確率も変わらない")
	p.event_on = true
	check(p.berry_amount() == 3, "きのみ+2個 (got %d)" % p.berry_amount())
	check(p.ingredient_amount(p.ingredients[1]) == 3, "食材+1個")
	check(_near(p.skill_chance(), 0.039 * 1.5, 1e-9), "スキル確率1.5倍")
	# (22+10)×1.5 = 48
	check(p.carry_limit() == 48, "最大所持数 (22+10)×1.5=48 (got %d)" % p.carry_limit())
	p.event_carry_add = 0
	p.event_carry_mult = 1.1
	# 22×1.1 = 24.2 → 25
	check(p.carry_limit() == 25, "最大所持数 22×1.1=24.2は切り上げて25 (got %d)" % p.carry_limit())
	# 食材を拾うたびに増加数のぶん多く持ってくる
	p.ingredient_prob = 1.0
	p.max_carry = 1000000
	var s := Sim.new(p)
	s.advance(16 * 3600.0)
	var ok := true
	for e in s.help_log:
		if not Sim.is_tap(e) and e["id"] != "":
			ok = ok and e["amount"] == {"ing_a": 2, "ing_b": 3, "ing_c": 5}[e["id"]]
	check(ok and s.help_log.size() > 0, "おてつだいで食材を枠の数+1個持ってくる")


func _test_ex_mode() -> void:
	print("EXモード補正")
	var p := Params.new()
	p.ex_help_time_pct = -10.0
	p.ex_ingredient_add = 1
	p.ex_extra_ingredient = 2
	p.ex_extra_ingredient_prob = 1.0
	p.ex_skill_mult = 1.25
	# OFF のあいだは値を入れても効かない
	check(p.help_sec() == 1940.0 and p.ingredient_amount(p.ingredients[0]) == 1 and not p.has_extra_ingredient(), "OFF なら補正なし")
	p.ex_on = true
	# 2200×0.882×0.9 = 1746.36
	check(p.help_sec() == 1746.0, "おてつだい時間−10%%は1746秒 (got %f)" % p.help_sec())
	check(p.ingredient_amount(p.ingredients[2]) == 5 and p.has_extra_ingredient(), "食材+1個・追加あり")
	check(_near(p.skill_chance(), 0.039 * 1.25, 1e-9), "スキル確率1.25倍")
	p.event_on = true
	p.event_ingredient_add = 1
	p.event_skill_mult = 1.5
	check(p.ingredient_amount(p.ingredients[0]) == 3, "イベントとEXモードの食材の増加数は足し算")
	check(_near(p.skill_chance(), 0.039 * 1.5 * 1.25, 1e-9), "イベントとEXモードのスキル倍率は掛け算")
	p.event_on = false
	# 確率100%なら食材を拾うたびに 枠の数+1+2個
	p.ingredient_prob = 1.0
	p.max_carry = 1000000
	var s := Sim.new(p)
	s.advance(16 * 3600.0)
	var ok := true
	for e in s.help_log:
		if not Sim.is_tap(e) and e["id"] != "":
			ok = ok and e["amount"] == {"ing_a": 4, "ing_b": 5, "ing_c": 7}[e["id"]]
	check(ok and s.help_log.size() > 0, "確率100%%なら毎回 +1+2個")
	p.ex_extra_ingredient_prob = 0.0
	check(not p.has_extra_ingredient(), "確率0%%なら追加なし")


func _test_camp_ticket() -> void:
	print("いいキャンプチケット")
	var p := Params.new()
	check(p.help_sec() == 1940.0 and p.carry_limit() == 22, "OFF なら補正なし")
	p.camp_ticket = true
	# 2200×0.882÷1.2 = 1617.0
	check(p.help_sec() == 1617.0, "おてつだい時間÷1.2は1617秒 (got %f)" % p.help_sec())
	check(p.carry_limit() == 27, "最大所持数22×1.2=26.4は切り上げて27 (got %d)" % p.carry_limit())
	p.max_carry = 25
	check(p.carry_limit() == 30, "25×1.2=30.0はそのまま30 (got %d)" % p.carry_limit())
	p.max_carry = 23
	p.event_on = true
	p.event_carry_mult = 1.1
	# 23×1.1×1.2 = 30.36 → 31
	check(p.carry_limit() == 31, "イベント1.1倍とチケットで23×1.1×1.2=30.36→31 (got %d)" % p.carry_limit())
	p.event_on = false
	p.ex_on = true
	p.ex_help_time_pct = -10.0
	# 2200×0.882×0.9÷1.2 = 1455.3
	check(p.help_sec() == 1455.0, "EXモード−10%%とチケットで1455秒 (got %f)" % p.help_sec())


func _test_presets() -> void:
	print("計算条件のセーブ・ロード（設定1〜設定6）")
	var path := "user://test_presets.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var pr := Presets.new(path)
	check(pr.slot_name(5) == "設定6" and not pr.is_saved(5), "設定6は空で、既定の設定名")
	var p := Params.new()
	p.pseudon_name = "ためし"
	p.level = 33
	p.skill_prob = 0.051
	p.subskills = {"speed_m": true, "carry_s": true}
	p.nature_up = Params.Nature.SKILL
	p.ingredients[2]["amount"] = 7
	p.event_on = true
	p.event_carry_mult = 1.5
	p.camp_ticket = true
	pr.store(2, p)
	check(pr.slot_name(2) == "ためし", "設定名は名前欄から取る")
	# ファイルから読み直して、別の Params に戻す
	var pr2 := Presets.new(path)
	check(pr2.is_saved(2) and pr2.slot_name(2) == "ためし", "ファイルに残る")
	var q := Params.new()
	q.pseudon_name = "べつ"
	check(pr2.restore(2, q), "変身できる")
	check(q.pseudon_name == "ためし" and q.level == 33 and typeof(q.level) == TYPE_INT, "名前とLV（整数のまま）")
	check(_near(q.skill_prob, 0.051, 1e-9) and q.nature_up == Params.Nature.SKILL, "スキル確率とせいかく")
	check(q.has_subskill("speed_m") and q.has_subskill("carry_s") and q.subskills.size() == 2, "サブスキル")
	check(q.ingredients[2]["amount"] == 7 and q.ingredients[2]["id"] == "ing_c", "食材枠の数（id はそのまま）")
	check(q.event_on and _near(q.event_carry_mult, 1.5, 1e-9), "イベント")
	check(not q.camp_ticket, "いいキャンプチケットはチーム全体の設定なので変身で変わらない")
	q.camp_ticket = true
	check(q.help_sec() == p.help_sec() and q.carry_limit() == p.carry_limit(), "計算に使う値も同じ")
	check(not pr2.restore(5, q) and q.pseudon_name == "ためし", "空の枠では変身しない")
	# ファイルには記憶した枠だけが入り、ほかの枠は初期設定のまま
	var saved: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.size() == 6, "ファイルは6枠 (got %d)" % saved.size())
	check(saved[0] == null and saved[1] == null and saved[2] is Dictionary, "初期設定の枠はファイルに書かない")
	check(pr2.slot_name(4) == "No.25実Sいじ", "記憶していない枠は初期設定")
	# 常に上書き
	p.pseudon_name = "うわがき"
	p.level = 10
	pr2.store(2, p)
	var pr3 := Presets.new(path)
	check(pr3.slot_name(2) == "うわがき" and int(pr3.slots[2]["params"]["level"]) == 10, "同じ枠は上書き")
	check(not pr3.slots[2]["params"].has("help_bonus_count") and not pr3.slots[2]["params"].has("camp_ticket"),
		"おてつだいボーナス数とチケットは記憶しない")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# 以前の保存データ（サブスキルのおてつだいボーナス・他のメンバーの数・チケット）は読み捨てる
	var old := Params.new()
	old.help_bonus_count = 2
	old.apply_dict({"subskills": {"help_bonus": true, "speed_s": true}, "other_help_bonus": 4, "camp_ticket": true})
	check(old.subskills.keys() == ["speed_s"] and old.help_bonus_count == 2 and not old.camp_ticket, "以前の保存データ")


func _test_preset_defaults() -> void:
	print("へんしんリストの初期設定")
	var path := "user://test_presets_defaults.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var pr := Presets.new(path)
	var names := []
	for i in Presets.SLOT_COUNT:
		names.append(pr.slot_name(i))
	check(names == ["ベアビヲ9", "回復役", "本島EXバフ", "砂浜EXデバフ", "No.25実Sいじ", "設定6"], "設定名 (got %s)" % str(names))
	check(pr.is_saved(0) and pr.is_saved(4) and not pr.is_saved(5), "設定1〜5は変身でき、設定6は空")
	var p := Params.new()
	p.level = 10
	p.skill_prob = 0.5
	pr.restore(0, p)
	check(p.pseudon_name == "ベアビヲ9" and p.to_dict() == Params.new().to_dict(), "設定1: 名前とパラメータの初期値（ベアビヲ9）に戻る")
	pr.restore(4, p)
	check(p.pseudon_name == "No.25実Sいじ" and p.level == 25 and p.base_help_sec == 2700.0, "設定5: 名前・LV25・2700秒")
	check(_near(p.ingredient_prob, 0.207, 1e-9) and _near(p.skill_prob, 0.021, 1e-9), "設定5: 食材20.7%%・スキル2.1%%")
	check(p.skill_ceiling == 78 and p.max_skill_stock == 1 and p.max_carry == 22 and p.berries_per_help == 2, "設定5: 天井78・ストック1・所持22・きのみ2")
	check(p.ingredients[0]["amount"] == 1 and p.evolutions_left == 1 and p.ribbon_sleep_hours == 0, "設定5: 食材1の数1・進化1回・睡眠0")
	check(p.subskills.keys() == ["berry_s"], "設定5: きのみの数S")
	check(p.nature_up == Params.Nature.SPEED and p.nature_down == Params.Nature.INGREDIENT, "設定5: スピード↑食材↓")
	check(not p.ex_on and not p.event_on, "設定5: 補正なし")
	pr.restore(1, p)
	check(p.pseudon_name == "回復役" and p.level == 25 and p.base_help_sec == 4000.0, "設定2: 名前・LV25・4000秒")
	check(_near(p.ingredient_prob, 0.25, 1e-9) and _near(p.skill_prob, 0.02, 1e-9), "設定2: 食材25%%・スキル2%%")
	check(p.skill_ceiling == 40 and p.max_skill_stock == 2 and p.max_carry == 13 and p.berries_per_help == 1, "設定2: 天井40・ストック2・所持13・きのみ1")
	check(p.evolutions_left == 1 and p.subskills.is_empty() and p.nature_up == Params.Nature.NONE and p.nature_down == Params.Nature.NONE, "設定2: 進化1回・サブスキルとせいかくなし")
	var base := Params.new()
	pr.restore(2, p)
	check(p.pseudon_name == "本島EXバフ" and p.level == base.level and p.base_help_sec == base.base_help_sec, "設定3: パラメータはベアビヲ9と同じ")
	check(p.ex_on and _near(p.ex_help_time_pct, -10.0, 1e-9) and _near(p.ex_skill_mult, 1.25, 1e-9), "設定3: EX −10%%・スキル1.25倍")
	pr.restore(3, p)
	check(p.pseudon_name == "砂浜EXデバフ" and p.ex_on and _near(p.ex_help_time_pct, 35.0, 1e-9) and _near(p.ex_skill_mult, 1.0, 1e-9), "設定4: EX +35%%")
	# 2200×0.882×1.35 = 2619.54
	check(p.help_sec() == 2619.0, "設定4: おてつだい時間2619秒 (got %f)" % p.help_sec())


func _test_slots_by_level() -> void:
	print("レベルによる食材枠の解放")
	var p := Params.new()
	p.level = 29
	check(p.active_ingredients().size() == 1, "Lv.29は1枠")
	p.level = 30
	check(p.active_ingredients().size() == 2, "Lv.30で2枠")
	p.level = 60
	check(p.active_ingredients().size() == 3, "Lv.60で3枠")
	p.level = 10
	p.ingredient_prob = 1.0
	p.max_carry = 1000000
	var s := Sim.new(p)
	var items: Dictionary = s.advance(16 * 3600.0)["items"]
	check(not items.has("ing_b") and not items.has("ing_c"), "未解放の枠の食材は出ない")


func _test_subskill_slots() -> void:
	print("サブスキルを選べる数")
	var p := Params.new()
	var expect := {1: 0, 9: 0, 10: 1, 24: 1, 25: 2, 49: 2, 50: 3, 69: 3, 70: 4, 79: 4, 80: 5, 100: 5}
	for lv in expect:
		p.level = lv
		check(p.subskill_slots() == expect[lv], "Lv.%dは%d個 (got %d)" % [lv, expect[lv], p.subskill_slots()])
	p.level = 80
	p.subskills = {"berry_s": true, "speed_m": true, "ing_s": true, "carry_l": true, "carry_s": true}
	p.level = 50
	p.trim_subskills()
	check(p.subskills.keys() == ["berry_s", "carry_l", "carry_s"], "Lv.50に下げると下の項目から外れる (got %s)" % str(p.subskills.keys()))
	p.level = 80
	p.trim_subskills()
	check(p.subskills.size() == 3, "レベルを上げても自動では付かない")


func _test_skill_ceiling() -> void:
	print("スキル連続不発上限")
	var p := Params.new()
	p.max_carry = 1000000
	p.skill_prob = 0.0
	p.skill_ceiling = 5
	p.max_skill_stock = 1
	var s := Sim.new(p)
	var r := s.advance(p.help_sec() * 0.45 * 5 + 1)
	check(r["helps"] == 5 and r["skills"] == 0 and s.skill_miss == 5, "5回続けて不発 (helps %d, skills %d)" % [r["helps"], r["skills"]])
	r = s.advance(p.help_sec() * 0.45)
	check(r["skills"] == 1 and r["skill_ceiling_hits"] == 1, "天井5なら6回目で必ず発動")
	check(s.ceiling_stock == 1, "天井で出たストックを覚えている")
	r = s.advance(p.help_sec() * 0.45 * 20)
	check(r["skills"] == 0 and s.skill_miss == 0, "ストックが上限のあいだは抽選せず、不発カウントも0のまま")
	var d := s.drop()
	check(d["ceiling"] == 1 and s.ceiling_stock == 0, "タップで天井分を知らせて消費")
	r = s.advance(p.help_sec() * 0.45 * 5)
	check(r["skills"] == 0, "タップ後も5回目までは発動しない (got %d)" % r["skills"])
	r = s.advance(p.help_sec() * 0.45)
	check(r["skills"] == 1, "タップ後はまた6回目で発動 (got %d)" % r["skills"])
	var helps := s.help_log.filter(func(e: Dictionary) -> bool: return not Sim.is_tap(e))
	var kinds := helps.map(func(e: Dictionary) -> int: return e["skill"])
	check(kinds.size() == 32 and kinds[5] == Sim.Skill.CEILING and kinds[31] == Sim.Skill.CEILING and kinds.count(Sim.Skill.CEILING) == 2
		and kinds.count(Sim.Skill.HIT) == 0, "記録では6回目と32回目が天井 (%d件)" % kinds.size())
	check(s.miss_runs.size() == 6 and s.miss_runs[5] == 2 and Array(s.miss_runs).count(0) == 5, "連続不発の集計：5回不発のあと予約が2回")
	s.reset()
	check(s.miss_runs.is_empty(), "リセットで連続不発の集計も消える")


func _test_omikuji() -> void:
	print("おみくじ")
	var o := Omikuji.new()
	check(not o.enabled and is_equal_approx(o.chance, 0.10) and o.limit == 10, "初期値は無効・あたり10%・連続はずれの上限10")
	check(o.draw_for(3)["hits"] == 0 and o.miss == 0, "無効のあいだは引かない")
	o.enabled = true
	o.chance = 0.0
	o.limit = 4
	check(o.remaining() == 5, "カウントダウンは上限4なら5から")
	var r := o.draw_for(4)
	check(r["hits"] == 0 and o.miss == 4 and is_equal_approx(o.ratio(), 1.0), "4回続けてはずれ")
	check(o.remaining() == 1, "上限まではずれるとカウントダウンは1")
	r = o.draw_for(1)
	check(r["hits"] == 1 and r["tier"] == Omikuji.Tier.GRAND and o.miss == 0, "上限4なら5回目で必ずあたり（格別の演出）")
	check(o.miss_runs.size() == 5 and o.miss_runs[4] == 1, "連続はずれの集計：4回はずれのあとのあたりが1件")
	r = o.draw_for(2)
	check(r["hits"] == 0 and o.miss == 2, "ストック2なら2回引く")
	o.chance = 1.0
	r = o.draw_for(2)
	check(r["hits"] == 2 and r["tier"] == Omikuji.Tier.MEDIUM and o.miss == 0, "ストック2で2回あたり、演出ははずれ2回から引いた1回目のほう")
	check(Omikuji.tier_for(0, 9) == Omikuji.Tier.SMALL and Omikuji.tier_for(3, 9) == Omikuji.Tier.MEDIUM
		and Omikuji.tier_for(6, 9) == Omikuji.Tier.LARGE and Omikuji.tier_for(8, 9) == Omikuji.Tier.LARGE
		and Omikuji.tier_for(9, 9) == Omikuji.Tier.GRAND, "割合で3段階、上限で格別")
	o.limit = 0
	o.chance = 0.0
	check(o.draw() == Omikuji.Tier.GRAND and is_equal_approx(o.ratio(), 1.0), "上限0なら毎回あたり")
	o.limit = 10
	o.miss = 7
	o.reset()
	check(o.miss == 0 and o.miss_runs.is_empty(), "リセットではずれ回数と集計を消す")


## 連続不発の集計は予約の時点で1件。ストックがあるタップで途切れた分は数えない
func _test_miss_runs_tap() -> void:
	print("連続不発の集計とタップ")
	var p := Params.new()
	p.max_carry = 1000000
	p.skill_prob = 0.0
	p.skill_ceiling = 5
	p.max_skill_stock = 2
	var s := Sim.new(p)
	var t := p.help_sec() * 0.45
	s.advance(t * 6 + 1)
	check(s.miss_runs.size() == 6 and s.miss_runs[5] == 1 and s.skill_stock == 1, "6回目の予約の時点で、タップ前でも5回が1件")
	s.advance(t * 3)
	s.drop()
	s.advance(t * 6)
	check(s.miss_runs.size() == 6 and s.miss_runs[5] == 2 and s.miss_runs[3] == 0, "タップで途切れた3回は数えず、次も5回不発のあと予約")


## ストック2: 1回目は天井で発動、そのあと不発カウントは0から数え直し、2回目は天井に届く前に通常の抽選で発動する
func _test_skill_ceiling_stock2() -> void:
	print("スキル天井 ストック2（1回目が天井、2回目は天井前）")
	var p := Params.new()
	p.max_carry = 1000000
	p.skill_prob = 0.0
	p.skill_ceiling = 5
	p.max_skill_stock = 2
	var s := Sim.new(p)
	var t := p.help_sec() * 0.45
	var r := s.advance(t * 5 + 1)
	check(r["skills"] == 0 and s.skill_miss == 5, "5回続けて不発 (miss %d)" % s.skill_miss)
	r = s.advance(t)
	check(r["skills"] == 1 and r["skill_ceiling_hits"] == 1, "6回目に天井で1回目が発動")
	check(s.skill_stock == 1 and s.ceiling_stock == 1, "ストック1、うち天井1")
	check(s.skill_miss == 0, "天井で発動したら不発カウントは0に戻る (miss %d)" % s.skill_miss)
	r = s.advance(t * 3)
	check(r["skills"] == 0 and s.skill_miss == 3, "ストックに空きがあるので抽選が続き、0から数え直して3回不発 (miss %d)" % s.skill_miss)
	p.skill_prob = 1.0
	r = s.advance(t)
	check(r["skills"] == 1 and r["skill_ceiling_hits"] == 0, "2回目は天井に届く前（不発3回の次）に通常の抽選で発動")
	check(s.skill_stock == 2 and s.ceiling_stock == 1, "ストック2、うち天井は1回目の1つだけ (stock %d, ceiling %d)" % [s.skill_stock, s.ceiling_stock])
	check(s.skill_miss == 0, "通常の発動でも不発カウントは0に戻る")
	r = s.advance(t * 10)
	check(r["skills"] == 0 and s.skill_miss == 0, "ストックが上限になったら抽選せず、不発カウントも増えない")
	var d := s.drop()
	check(d["stock"] == 2 and d["ceiling"] == 1, "タップでストック2、うち天井1を知らせる (stock %d, ceiling %d)" % [d["stock"], d["ceiling"]])


## ストック2でストック1のときにタップすると、不発カウントも0に戻る。ストックがないタップでは戻らない（#39）
func _test_skill_miss_reset_on_tap() -> void:
	print("タップで不発カウントを0に戻す")
	var p := Params.new()
	p.max_carry = 1000000
	p.skill_prob = 0.0
	p.skill_ceiling = 5
	p.max_skill_stock = 2
	var s := Sim.new(p)
	var t := p.help_sec() * 0.45
	s.advance(t * 6 + 1)
	check(s.skill_stock == 1 and s.skill_miss == 0, "6回目に天井で発動してストック1")
	var r := s.advance(t * 3)
	check(r["skills"] == 0 and s.skill_miss == 3, "その後3回不発 (miss %d)" % s.skill_miss)
	var d := s.drop()
	check(d["stock"] == 1 and s.skill_stock == 0, "タップでストックが空になる")
	check(s.skill_miss == 0, "タップで不発カウントも0に戻る (miss %d)" % s.skill_miss)
	r = s.advance(t * 5)
	check(r["skills"] == 0 and s.skill_miss == 5, "タップ後は0から数え直して5回不発 (miss %d)" % s.skill_miss)
	r = s.advance(t)
	check(r["skills"] == 1 and r["skill_ceiling_hits"] == 1, "タップ後6回目で天井発動（タップ前の3回は数えない）")
	s.drop()
	r = s.advance(t * 2)
	check(s.skill_stock == 0 and s.skill_miss == 2, "ストックを空にしたあと不発2回 (miss %d)" % s.skill_miss)
	d = s.drop()
	check(d["stock"] == 0 and s.skill_miss == 2, "ストックがないときのタップでは不発カウントは戻らない (miss %d)" % s.skill_miss)
	r = s.advance(t * 2)
	check(s.skill_miss == 4, "そのまま続けて数える (miss %d)" % s.skill_miss)


func _test_tap_log() -> void:
	print("記録にタップした時点の行が入る")
	var p := Params.new()
	p.max_carry = 1000000
	p.skill_prob = 0.0
	p.skill_ceiling = 2
	p.max_skill_stock = 2
	var s := Sim.new(p)
	var t := p.help_sec() * 0.45
	s.advance(t * 3 + 1)
	var held := s.pending_count()
	s.drop()
	var e: Dictionary = s.help_log[-1]
	check(s.help_log.size() == 4 and Sim.is_tap(e), "おてつだい3回のあとにタップの行")
	check(e["t"] == s.elapsed_sec and e["amount"] == held, "タップの時刻と出した数 (%d個)" % e["amount"])
	check(e["stock"] == 1 and e["ceiling"] == 1, "使ったストック1（天井）")
	s.drop()
	check(s.help_log.size() == 4, "何も持っていないときのタップは記録しない")
	s.advance(t)
	check(not Sim.is_tap(s.help_log[-1]) and s.help_log[-1]["t"] > e["t"], "タップのあとのおてつだいはその後ろ")


## 記録の日ごとのまとめ（#81）。4:00 で日付が変わり、スキルは予約した回で数える
func _test_day_summary() -> void:
	print("記録の日ごとのまとめ")
	var slots := ["ing_a", "ing_b", "ing_c"]
	var day := FieldClock.DAY_SEC
	var list: Array[Dictionary] = [
		{"t": 100.0, "id": "berry", "amount": 2, "skill": Sim.Skill.HIT},
		{"t": 200.0, "id": "ing_b", "amount": 3, "skill": Sim.Skill.NONE},
		{"t": 300.0, "tap": true, "amount": 5, "stock": 1, "ceiling": 0},
		{"t": day - 1.0, "id": "berry", "amount": 2, "skill": Sim.Skill.CEILING},
		{"t": day + 1.0, "id": "ing_a", "amount": 1, "skill": Sim.Skill.HIT},
		{"t": day + 2.0, "id": "", "amount": 0, "skill": Sim.Skill.NONE},
	]
	var sums := HelpLogTable.day_summaries(list, slots)
	check(sums.keys() == [1, 2], "1日目と2日目に分かれる")
	check(sums[1]["berry"] == 4 and sums[1]["ingredients"] == [0, 3, 0], "1日目 きのみ4・枠2が3（タップは数えない）")
	check(sums[1]["skill"] == 2 and sums[1]["ceiling"] == 1, "1日目のスキルは予約2回（うち天井1回）")
	check(sums[2]["berry"] == 0 and sums[2]["ingredients"] == [1, 0, 0] and sums[2]["skill"] == 1 and sums[2]["ceiling"] == 0, "2日目 枠1が1・スキル1回（天井なし）")
	check(HelpLogTable.summary_lines(sums[1], 1) == [0, 1, 2], "解放1枠でも集めた枠2の行は出す")
	check(HelpLogTable.summary_lines(sums[2], 3) == [0, 1, 2, 3], "解放3枠ならきのみ＋3行")
	var table := HelpLogTable.new()
	table.set_log(list, slots, 1)
	check(table.rows.size() == list.size() + 3 + 2, "まとめの行は各日の先頭に入る")
	check(table.rows[0] == {"day": 1, "line": 0} and table.rows[3] == {"e": 0}, "1日目のまとめのあとに1日目の記録")
	check(table.rows[7] == {"day": 2, "line": 0} and table.rows[9] == {"e": 4}, "2日目のまとめは2日目の最初の記録の前")
	# まとめの固定表示。1日目は 0〜2 行目（3行）、2日目は 7〜8 行目（2行）
	var h := HelpLogTable.ROW_H
	check(table.pinned_at(0.0)[0] == -1, "一番上ではそのまま（固定しない）")
	check(table.pinned_at(h * 2) == [0, h * 2], "スクロールすると1日目のまとめを上端に固定")
	check(table.pinned_at(h * 5) == [0, h * 4], "2日目のまとめが近づくと押し上げる")
	check(table.pinned_at(h * 7.5) == [1, h * 7.5], "2日目のまとめが上端を越えたら入れ替わる")
	table.free()


## メインスキルでげんきを増減する（#26）。10分ごとに減る区切りはそのまま、0〜150
func _test_genki_start() -> void:
	print("げんきの初期値")
	var s := Sim.new()
	s.set_genki_start(60)
	check(s.genki_at(0.0) == 100, "81以上で固定のときは初期値に関係なく変わらない")
	s.set_genki_mode(Sim.GenkiMode.DECAY)
	check(s.genki_at(s.elapsed_sec) == 60, "減少にすると初期値60から")
	s.advance(1205.0)
	check(s.genki_at(s.elapsed_sec) == 58, "20分で58")
	s.set_genki_start(120)
	check(s.genki_at(s.elapsed_sec) == 120, "途中で変えると今のげんきがその値から減り始め直す")
	s.advance(600.0)
	check(s.genki_at(s.elapsed_sec) == 119, "そこから10分で119")
	s.reset()
	check(s.genki_at(0.0) == 120, "リセット後も初期値から")
	check(is_equal_approx(s.next_help_at, s.params.help_sec() * 0.45), "初期値120なら最初のおてつだいは0.45倍")
	s.set_genki_start(30)
	s.reset()
	check(is_equal_approx(s.next_help_at, s.params.help_sec() * Sim.genki_multiplier(30)), "初期値30なら最初のおてつだいから30の補正")
	s.set_genki_start(999)
	check(s.genki_start == Sim.GENKI_MAX, "上限は150")


func _test_add_genki() -> void:
	print("げんきの増減")
	var s := Sim.new()
	s.add_genki(30)
	check(s.genki_at(0.0) == 100, "81以上で固定のときは変わらない")
	s.set_genki_mode(Sim.GenkiMode.DECAY)
	s.advance(605.0)
	check(s.genki_at(s.elapsed_sec) == 99, "10分で1減る")
	s.add_genki(18)
	check(s.genki_at(s.elapsed_sec) == 117, "18回復して117 (got %d)" % s.genki_at(s.elapsed_sec))
	check(s.genki_at(1200.0) == 116, "減る区切りはそのまま（20分の時点で116）")
	s.add_genki(100)
	check(s.genki_at(s.elapsed_sec) == 150, "上限は150")
	s.add_genki(-200)
	check(s.genki_at(s.elapsed_sec) == 0, "マイナスは0まで")
	s.advance(3600.0)
	check(s.genki_at(s.elapsed_sec) == 0, "0から下がらない")
	s.add_genki(10)
	check(s.genki_at(s.elapsed_sec) == 10, "0から10回復 (got %d)" % s.genki_at(s.elapsed_sec))
	check(s.genki_at(s.elapsed_sec + 600.0) == 9, "そこからまた10分ごとに減る")
	var interval := s.help_interval_at(s.elapsed_sec)
	check(is_equal_approx(interval, s.params.help_sec() * 0.66), "げんき10のおてつだい間隔は0.66倍")
	s.add_genki(80)
	check(is_equal_approx(s.help_interval_at(s.elapsed_sec), s.params.help_sec() * 0.45), "90に回復すると0.45倍")


## せいかくのげんき回復: 増やすときだけ 上昇1.2倍／下降0.88倍（切り捨て）。減らすときは掛けない
func _test_genki_nature() -> void:
	print("せいかくのげんき回復")
	var p := Params.new()
	p.nature_up = Params.Nature.GENKI
	var s := Sim.new(p)
	s.set_genki_mode(Sim.GenkiMode.DECAY)
	s.add_genki(-50)
	s.add_genki(5)
	check(s.genki_at(0.0) == 56, "上昇: 50から5×1.2=6回復 (got %d)" % s.genki_at(0.0))
	s.add_genki(7)
	check(s.genki_at(0.0) == 64, "上昇: 7×1.2=8.4は8 (got %d)" % s.genki_at(0.0))
	s.add_genki(-10)
	check(s.genki_at(0.0) == 54, "減らすときは倍率を掛けない (got %d)" % s.genki_at(0.0))
	p.nature_up = Params.Nature.NONE
	p.nature_down = Params.Nature.GENKI
	s.add_genki(10)
	check(s.genki_at(0.0) == 62, "下降: 10×0.88=8.8は8 (got %d)" % s.genki_at(0.0))
	s.add_genki(-10)
	check(s.genki_at(0.0) == 52, "下降でも減らすときは掛けない (got %d)" % s.genki_at(0.0))


## 妖精: 持っている分はタップで消え、休んでいるあいだは時間だけ進む
func _test_fairy_sim() -> void:
	print("妖精のおてつだい")
	var p := Params.new()
	p.skill_prob = 1.0
	var s := Sim.new(p)
	var t := p.help_sec() * 0.45
	s.advance(t * 2 + 1)
	var held := s.pending_count()
	var d := s.drop(false)
	check(held > 0 and Sim.sum(d["items"]) == held and d["stock"] == 2, "タップで持っていた分とストックを知らせる")
	check(s.pending_count() == 0 and Sim.sum(s.on_field) == 0, "持っていた分はフィールドに出ずに消える")
	s.idle(t * 10)
	check(s.totals["helps"] == 2 and s.elapsed_sec > t * 12, "休んでいるあいだはおてつだいしない")
	s.restart_help()
	check(is_equal_approx(s.next_help_at, s.elapsed_sec + t), "始め直すと今からおてつだい1回分あと")
	# #58 の例: 3時間で82、回復して87、休んで3時間たっても87のまま（パチモンは69）
	var fairy := Sim.new(Params.new())
	var pseudon := Sim.new(Params.new())
	for x in [fairy, pseudon]:
		x.set_genki_mode(Sim.GenkiMode.DECAY)
		x.advance(3 * 3600.0)
		x.add_genki(5)
	check(fairy.genki_at(fairy.elapsed_sec) == 87, "3時間で82、5回復して87 (got %d)" % fairy.genki_at(fairy.elapsed_sec))
	fairy.idle(3 * 3600.0)
	pseudon.advance(3 * 3600.0)
	check(fairy.genki_at(fairy.elapsed_sec) == 87, "休んでいる3時間はげんきが減らない (got %d)" % fairy.genki_at(fairy.elapsed_sec))
	check(pseudon.genki_at(pseudon.elapsed_sec) == 69, "パチモンは3時間で69 (got %d)" % pseudon.genki_at(pseudon.elapsed_sec))
	fairy.restart_help()
	fairy.advance(600.0)
	check(fairy.genki_at(fairy.elapsed_sec) == 86, "また回復するにすると10分で1減る (got %d)" % fairy.genki_at(fairy.elapsed_sec))
	var r := s.advance(t + 1)
	check(r["helps"] == 1, "始め直したあとはおてつだいする")


## 睡眠: 補正なしでは8時間30分で100回復（100まで）。それにせいかく補正を掛けて四捨五入。眠っているあいだもおてつだいとげんきの減少は進む
func _test_sleep() -> void:
	print("睡眠")
	var s := Sim.new()
	check(s.sleep_recovery(510) == 100, "8時間30分で100")
	check(s.sleep_recovery(30) == 6, "30分は5.88で6")
	check(s.sleep_recovery(240) == 47, "4時間は47.06で47")
	check(s.sleep_recovery(600) == 100, "8時間30分より長くても100")
	s.params.nature_up = Params.Nature.GENKI
	check(s.sleep_recovery(240) == 56, "上昇: 47.06×1.2=56.47で56 (got %d)" % s.sleep_recovery(240))
	check(s.sleep_recovery(450) == 106, "上昇: 88.24×1.2=105.9で106 (got %d)" % s.sleep_recovery(450))
	check(s.sleep_recovery(600) == 120, "上昇: 上限100×1.2=120 (got %d)" % s.sleep_recovery(600))
	s.params.nature_up = Params.Nature.NONE
	s.params.nature_down = Params.Nature.GENKI
	check(s.sleep_recovery(510) == 88, "下降: 100×0.88=88 (got %d)" % s.sleep_recovery(510))
	check(s.sleep_recovery(720) == 88, "下降: 長く眠っても88まで (got %d)" % s.sleep_recovery(720))
	s.params.nature_down = Params.Nature.NONE

	s.set_genki_mode(Sim.GenkiMode.DECAY)
	var r := s.sleep(240)
	check(r["helps"] > 0 and s.totals["helps"] == r["helps"], "眠っているあいだもおてつだいする")
	check(is_equal_approx(s.elapsed_sec, 240 * 60.0), "睡眠時間だけ進む")
	check(s.genki_at(s.elapsed_sec) == 100, "100-24+47 は100で止まる (got %d)" % s.genki_at(s.elapsed_sec))
	s.add_genki(-80)
	s.sleep(120)
	# 20から12減って8、2時間=23.5で24回復 → 32
	check(s.genki_at(s.elapsed_sec) == 32, "減ってから起きた時点で回復 (got %d)" % s.genki_at(s.elapsed_sec))
	check(s.genki_at(s.elapsed_sec + 600.0) == 31, "起きたあとも10分ごとに減る")
	s.add_genki(100)
	s.sleep(30)
	check(s.genki_at(s.elapsed_sec) == 129, "100以上なら睡眠では回復しない (got %d)" % s.genki_at(s.elapsed_sec))
	var idle := Sim.new()
	idle.set_genki_mode(Sim.GenkiMode.DECAY)
	idle.sleep(510, false)
	check(idle.totals["helps"] == 0 and idle.genki_at(idle.elapsed_sec) == 100, "休んでいるなら時間だけ進み、げんきは減りも回復もしない (#58)")
	var high := Sim.new()
	high.sleep(510)
	check(high.genki_at(high.elapsed_sec) == 100, "81以上で固定のときは変わらない")


func _test_name_width() -> void:
	print("名前の長さ（全角6文字・半角12文字まで）")
	check(Params.name_width("ベアビヲ9") == 9, "全角4＋半角1で9 (got %d)" % Params.name_width("ベアビヲ9"))
	check(Params.clip_name("あいうえおか") == "あいうえおか", "全角6文字はそのまま")
	check(Params.clip_name("あいうえおかき") == "あいうえおか", "全角7文字目は削る")
	check(Params.clip_name("abcdefghijkl") == "abcdefghijkl", "半角12文字はそのまま")
	check(Params.clip_name("abcdefghijklm") == "abcdefghijkl", "半角13文字目は削る")
	check(Params.clip_name("ベアビヲ9abcd") == "ベアビヲ9abc", "混在は合計12まで (got %s)" % Params.clip_name("ベアビヲ9abcd"))
	check(Params.clip_name("ｱｲｳｴｵｶｷｸｹｺｻｼｽ") == "ｱｲｳｴｵｶｷｸｹｺｻｼ", "半角カナは半角として数える")


func _test_example1_help_count() -> void:
	print("その1: げんき常に81以上 16時間")
	var s := _tapping_sim()
	var r := s.advance(16 * 3600.0)
	check(r["helps"] == 49, "おてつだい49回 (got %d)" % r["helps"])


func _test_example2_help_count() -> void:
	print("その2: げんき100から減少 16時間")
	var s := _tapping_sim()
	s.set_genki_mode(Sim.GenkiMode.DECAY)
	s.reset()
	var r := s.advance(16 * 3600.0)
	check(r["helps"] == 39, "おてつだい39回 (got %d)" % r["helps"])
	check(s.genki_at(16 * 3600.0) == 4, "16時間後のげんき4 (got %d)" % s.genki_at(16 * 3600.0))


func _test_carry_over() -> void:
	print("途中まで進んだおてつだいの持ち越し")
	var s := _tapping_sim()
	var n := 0
	for i in 16:
		n += int(s.advance(3600.0)["helps"])
	check(n == 49, "1時間×16回でも49回 (got %d)" % n)


## おてつだい1回ごとにタップする（おてつだい間隔より短い刻みで進め、そのたびにストックを空にする）
func _advance_tapping(s: Sim, seconds: float) -> Dictionary:
	var step := 1100.0
	var t := 0.0
	while t < seconds:
		var d := minf(step, seconds - t)
		s.advance(d)
		s.drop()
		t += d
	return s.totals


func _run_many(decay: bool, trials: int) -> Dictionary:
	var acc := {"ing": 0.0, "skill": 0.0, "berry_items": 0.0, "ing_items": 0.0, "skill0": 0}
	for i in trials:
		var s := _tapping_sim()
		s.rng.seed = 1000 + i
		if decay:
			s.set_genki_mode(Sim.GenkiMode.DECAY)
		var r := _advance_tapping(s, 16 * 3600.0)
		acc["ing"] += r["ingredient_helps"]
		acc["skill"] += r["skills"]
		var items: Dictionary = r["items"]
		acc["berry_items"] += int(items.get("berry", 0))
		acc["ing_items"] += int(items.get("ing_a", 0)) + int(items.get("ing_b", 0))
		if r["skills"] == 0:
			acc["skill0"] += 1
	for k in ["ing", "skill", "berry_items", "ing_items"]:
		acc[k] /= trials
	acc["skill0"] = float(acc["skill0"]) / trials
	return acc


func _near(x: float, expected: float, tol: float) -> bool:
	return absf(x - expected) <= tol


func _test_example1_distribution() -> void:
	print("その1: 20000回試行の平均")
	var a := _run_many(false, 20000)
	check(_near(a["ing"], 12.25, 0.1), "食材の回数 平均12.25 (got %.3f)" % a["ing"])
	check(_near(a["skill"], 2.45, 0.05), "スキルの回数 平均2.45 (got %.3f)" % a["skill"])
	check(_near(a["berry_items"], 73.5, 0.3), "きのみ 平均73.5個 (got %.3f)" % a["berry_items"])
	check(_near(a["ing_items"], 30.6, 0.3), "食材 平均約30.6個 (got %.3f)" % a["ing_items"])
	check(_near(a["skill0"], 0.081, 0.01), "スキル0回 約8%% (got %.3f)" % a["skill0"])


func _test_example2_distribution() -> void:
	print("その2: 20000回試行の平均")
	var a := _run_many(true, 20000)
	check(_near(a["ing"], 9.75, 0.1), "食材の回数 平均9.75 (got %.3f)" % a["ing"])
	check(_near(a["skill"], 1.95, 0.05), "スキルの回数 平均1.95 (got %.3f)" % a["skill"])
	check(_near(a["ing_items"], 24.4, 0.3), "食材 平均約24.4個 (got %.3f)" % a["ing_items"])
	check(_near(a["skill0"], 0.135, 0.01), "スキル0回 約13.5%% (got %.3f)" % a["skill0"])


func _test_capacity() -> void:
	print("最大所持数25・タップなし")
	var s := Sim.new(_example_params())
	s.rng.seed = 7
	var r := s.advance(16 * 3600.0)
	check(s.held_count() == 25, "所持数は25で止まる (got %d)" % s.held_count())
	check(r["full_helps"] > 0, "いつのまに育成が発生 (got %d)" % r["full_helps"])
	check(r["auto_fed"] == r["full_helps"] * 2, "いつのまに育成のきのみ数")
	# タップしてもフィールドに残したままなら所持数は減らない
	s.drop()
	check(s.held_count() == 25, "フィールドに残した分も所持数に入る")
	var r2 := s.advance(3600.0 * 4)
	check(r2["helps"] == r2["full_helps"], "残置中はすべていつのまに育成")
	var t := s.totals
	var helps := s.help_log.filter(func(e: Dictionary) -> bool: return not Sim.is_tap(e))
	check(helps.size() == t["helps"], "1回ごとの記録はおてつだい回数と同じ件数")
	var full := helps.filter(func(e: Dictionary) -> bool: return e["id"] == "")
	check(full.size() == t["full_helps"], "記録のいつのまに育成の件数が合う")
	check(s.help_log.size() == helps.size() + 1, "タップの行が1つ入る")
	var times := s.help_log.map(func(e: Dictionary) -> float: return e["t"])
	var sorted := times.duplicate()
	sorted.sort()
	check(times == sorted and times[-1] <= s.elapsed_sec, "記録は時刻順")
	s.reset()
	check(s.help_log.is_empty(), "リセットで記録も消える")
	check(t["helps"] == t["berry_helps"] + t["ingredient_helps"] + t["full_helps"],
		"累計でおてつだい = きのみ + 食材 + いつのまに育成 (%d = %d + %d + %d)" % [
			t["helps"], t["berry_helps"], t["ingredient_helps"], t["full_helps"]])
	for id in s.on_field.keys():
		s.collect(id)
	check(s.held_count() == 0, "回収すると所持数0")


func _test_skill_stock() -> void:
	print("スキルのストック上限")
	var p := Params.new()
	p.max_carry = 1000000
	p.max_skill_stock = 1
	p.skill_prob = 1.0
	var s := Sim.new(p)
	s.advance(3600.0 * 5)
	check(s.skill_stock == 1, "通常は1回まで (got %d)" % s.skill_stock)
	p.max_skill_stock = 2
	s.reset()
	s.advance(3600.0 * 5)
	check(s.skill_stock == 2, "スキルとくいは2回まで (got %d)" % s.skill_stock)
	var d := s.drop()
	check(d["stock"] == 2 and s.skill_stock == 0, "タップでストックを消費")


func _test_collect_limits() -> void:
	print("収容箱の上限")
	var s := Sim.new()
	s.on_field = {"berry": 10, "ing_a": 6}
	s.berry_box = {"berry": Sim.BERRY_BOX_MAX - 4}
	s.ingredient_box = {"ing_b": Sim.INGREDIENT_BOX_MAX}
	var got := s.collect("berry")
	check(got == 4, "きのみは空き4個だけ入る (got %d)" % got)
	check(int(s.on_field.get("berry", 0)) == 6, "入りきらない6個はフィールドに残る")
	check(s.collect("ing_a") == 0, "食材箱が800で満杯なら入らない")
	check(int(s.on_field.get("ing_a", 0)) == 6, "食材はフィールドに残る")


## 昼 7:00〜16:00、夕方 16:00〜18:00、夜 18:00〜翌7:00。時計は朝4:00から始まり、日付も朝4:00で変わる
func _test_time_phase() -> void:
	print("time phase")
	var D := FieldClock.Phase.DAY
	var E := FieldClock.Phase.EVENING
	var N := FieldClock.Phase.NIGHT
	check(FieldClock.START_SEC == 4 * 3600.0, "start at 4:00")
	var cases := [[7, D], [15.99, D], [16, E], [17.99, E], [18, N], [23.5, N], [0, N], [6.99, N], [31, D], [40, E], [42, N]]
	for c in cases:
		check(FieldClock.phase_at(c[0] * 3600.0) == c[1], "%.2f h -> phase %d" % [c[0], c[1]])
	# 記録の「n日目」「時刻」はリセットからの経過秒から出す
	check(FieldClock.day_and_clock(0.0) == [1, "4:00"], "elapsed 0 -> day 1 4:00")
	check(FieldClock.day_and_clock(20 * 3600.0) == [1, "0:00"], "elapsed 20h -> day 1 0:00")
	check(FieldClock.day_and_clock(23 * 3600.0 + 59 * 60 + 59) == [1, "3:59"], "elapsed 23:59:59 -> day 1 3:59")
	check(FieldClock.day_and_clock(24 * 3600.0) == [2, "4:00"], "elapsed 24h -> day 2 4:00")
	check(FieldClock.day_and_clock(51 * 3600.0 + 30 * 60) == [3, "7:30"], "elapsed 51.5h -> day 3 7:30")


## 期待値（#71）。「すすめる」1回ごとに、おてつだい回数から求めて足していく。スキルは天井込み
func _test_expected_values() -> void:
	print("期待値の表示（食材は二項分布、スキルは天井込み）")
	var none := 1000000
	check(absf(Sim.skill_mean(30, 0.039, none, 2, 0, 0) - 1.025) < 0.001, "天井に届かなければ B(30, 3.9%%)を上限2で打ち切った1.025回 (got %.4f)" % Sim.skill_mean(30, 0.039, none, 2, 0, 0))
	check(absf(Sim.skill_mean(30, 0.039, none, 1, 0, 0) - (1.0 - pow(0.961, 30))) < 1e-9, "上限1なら1−P(0)")
	check(absf(Sim.skill_mean(5, 0.3, none, 99, 0, 0) - 1.5) < 1e-9, "上限が十分大きく天井もなければ k×p")
	check(absf(Sim.skill_mean(30, 0.039, 65, 2, 35, 0) - 1.025) < 0.001, "不発35から30回では天井65に届かないので1.025回")
	check(absf(Sim.skill_mean(30, 0.039, 65, 2, 36, 0) - 1.328) < 0.001, "不発36からなら30回目までに天井に届いて1.328回 (got %.4f)" % Sim.skill_mean(30, 0.039, 65, 2, 36, 0))
	check(absf(Sim.skill_mean(99, 0.039, 65, 2, 0, 0) - 1.9544) < 0.0001, "不発0から99回で1.9544回")
	check(absf(Sim.skill_mean(6, 0.0, 5, 2, 0, 0) - 1.0) < 1e-9, "確率0でも天井5なら6回目で必ず1回")
	check(Sim.skill_mean(10, 0.5, 65, 2, 0, 2) == 0.0 and Sim.skill_mean(0, 0.5, 65, 2, 0, 0) == 0.0, "空きがない、またはおてつだい0回なら0")

	var p := Params.new()
	p.max_carry = 1000000
	p.max_skill_stock = 2
	var s := Sim.new(p)
	var r := s.advance(p.help_sec() * 0.45 * 30 + 1)
	var k: int = r["helps"]
	var q := p.ingredient_chance()
	check(k == 30, "30回おてつだい (got %d)" % k)
	check(absf(r["exp_ingredient_helps"] - k * q) < 1e-9 and absf(r["exp_berry_helps"] - k * (1.0 - q)) < 1e-9, "食材は k×食材確率、きのみは k×(1−食材確率)")
	var e1 := Sim.skill_mean(k, p.skill_chance(), p.skill_ceiling, 2, 0, 0)
	check(absf(r["exp_skills"] - e1) < 1e-9, "スキルは不発0・ストック0から天井込みで求める")
	var miss := s.skill_miss
	var stock := s.skill_stock
	r = s.advance(p.help_sec() * 0.45 * 10)
	check(absf(r["exp_skills"] - Sim.skill_mean(r["helps"], p.skill_chance(), p.skill_ceiling, 2, miss, stock)) < 1e-9, "タップせずに進めると、そのときの不発カウントとストックから求める (miss %d, stock %d)" % [miss, stock])
	check(absf(s.totals["exp_skills"] - (e1 + r["exp_skills"])) < 1e-9, "累計は「すすめる」ごとの期待値の合計")

	# 天井込みの期待値は、実際の回数の平均と合う（タップしながら24時間ずつ200日）
	var p3 := Params.new()
	p3.max_carry = 100000000
	var s3 := Sim.new(p3)
	s3.rng.seed = 7
	for d in 200:
		s3.advance(24 * 3600.0)
		s3.drop()
	var t3 := s3.totals
	check(absf(t3["skills"] - t3["exp_skills"]) < 4.0 * sqrt(t3["exp_skills"] * 0.05), "24時間ずつ200日でスキル%d回、期待値%.1f回" % [t3["skills"], t3["exp_skills"]])

	# いつのまに育成のおてつだいは数えない
	var p2 := Params.new()
	p2.max_carry = 3
	p2.berries_per_help = 1
	p2.ingredient_prob = 0.0
	var s2 := Sim.new(p2)
	r = s2.advance(p2.help_sec() * 0.45 * 10 + 1)
	check(r["full_helps"] == 7 and absf(r["exp_berry_helps"] - 3.0) < 1e-9, "いつのまに育成の7回は除いて、きのみ3回 (full %d, exp %.2f)" % [r["full_helps"], r["exp_berry_helps"]])


func _pmf_sum(pmf: PackedFloat64Array) -> float:
	var t := 0.0
	for v in pmf:
		t += v
	return t


func _test_distributions() -> void:
	print("回数の確率分布（(i) のグラフ）")
	var b := Dist.binomial(4, 0.5)
	check(b.size() == 5 and absf(b[0] - 0.0625) < 1e-12 and absf(b[2] - 0.375) < 1e-12, "B(4, 0.5) = 1/16, 4/16, 6/16, 4/16, 1/16")
	var big := Dist.binomial(5000, 0.2)
	check(absf(_pmf_sum(big) - 1.0) < 1e-9 and absf(Sim.pmf_mean(big) - 1000.0) < 1e-6, "k=5000 でもあふれず合計1、平均 k×q")
	check(Dist.binomial(3, 0.0)[0] == 1.0 and Dist.binomial(3, 1.0)[3] == 1.0, "確率0・1の端")

	var sp := Sim.skill_pmf(30, 0.039, 1000000, 2, 0, 0)
	check(sp.size() == 3 and absf(sp[0] - pow(0.961, 30)) < 1e-9 and absf(_pmf_sum(sp) - 1.0) < 1e-9, "スキル30回・上限2：0回の確率は 0.961^30")
	sp = Sim.skill_pmf(30, 0.039, 65, 2, 36, 0)
	check(sp[0] == 0.0, "不発36から30回なら天井で0回はない")
	check(Sim.skill_pmf(5, 0.5, 65, 2, 0, 2).size() == 1, "ストックが上限なら0回だけ")
	var mr := Sim.miss_run_pmf(0.039, 65)
	check(mr.size() == 66 and absf(_pmf_sum(mr) - 1.0) < 1e-12, "連続不発の理論上の分布：0〜65回で合計1")
	check(absf(mr[0] - 0.039) < 1e-12 and absf(mr[65] - pow(0.961, 65)) < 1e-12, "0回は p、上限65回は 0.961^65")
	check(absf(Sim.pmf_mean(mr) - Sim.miss_run_mean(0.039, 65)) < 1e-9, "分布の平均は理論上の平均と同じ")
	check(Sim.miss_run_pmf(0.5, 0).size() == 1 and Sim.miss_run_pmf(1.0, 65)[0] == 1.0, "上限0・確率1なら必ず0回")
	check(absf(Sim.miss_run_mean(0.039, 65) - 0.961 * (1.0 - pow(0.961, 65)) / 0.039) < 1e-9, "連続不発の理論上の平均は (1−p)(1−(1−p)^65)/p")
	check(Sim.miss_run_mean(0.0, 5) == 5.0 and Sim.miss_run_mean(1.0, 65) == 0.0 and Sim.miss_run_mean(0.5, 0) == 0.0, "確率0なら上限、確率1・上限0なら0")


	var d := Dist.new()
	d.add(Dist.binomial(2, 0.5))
	d.add(Dist.binomial(2, 0.5))
	check(absf(d.mass(2) - 0.375) < 1e-12 and absf(d.mean() - 2.0) < 1e-12, "たたみ込み：B(2,½)+B(2,½) = B(4,½)")
	check(absf(d.at_most(1) - 0.3125) < 1e-12 and absf(d.at_least(3) - 0.3125) < 1e-12, "1回以下・3回以上は 5/16")
	check(Main.percentile_text(d, 1) == "下位 31.2%（1回以下になる確率）", "少ない側は下位 (got %s)" % Main.percentile_text(d, 1))
	check(Main.percentile_text(d, 4) == "上位 6.2%（4回以上になる確率）", "多い側は上位 (got %s)" % Main.percentile_text(d, 4))
	check(Main.percentile_text(d, 2).begins_with("下位 68.8%"), "真ん中は小さいほう（同じなら下位）")
	# B(4,½)：0回 1/16、1回 4/16。下位15%%は1回の棒（0.5〜1.5）の (0.15−0.0625)/0.25 = 0.35 の位置
	check(absf(d.quantile(0.15) - 0.85) < 1e-9 and absf(d.quantile(0.85) - 3.15) < 1e-9, "B(4,½) の期待値まわり70%%は0.85〜3.15回 (got %s)" % d.central(0.7))
	check(absf(d.quantile(0.5) - 2.0) < 1e-9, "真ん中は2回の棒の中央")
	var wide := Dist.new()
	wide.add(Dist.binomial(1000, 0.2))
	var band := wide.central(0.7)
	check(band.x < 200 and band.y > 200 and absf((band.y - band.x) - 2.0 * 1.0364 * sqrt(160.0)) < 1.0, "B(1000,0.2) の70%%範囲 %s は正規近似の ±1.036σ とほぼ同じ" % band)

	# シミュレーターの累計の分布は、期待値と平均が合い、合計が1
	var p := Params.new()
	p.max_carry = 100000000
	var s := Sim.new(p)
	s.rng.seed = 3
	for i in 20:
		s.advance(8 * 3600.0)
		if i % 3 == 0:
			s.drop()
	var t := s.totals
	check(absf(_pmf_sum(s.ingredient_dist.p) - 1.0) < 1e-6 and absf(s.ingredient_dist.mean() - t["exp_ingredient_helps"]) < 1e-6, "食材の分布：合計1・平均＝期待値 %.2f" % t["exp_ingredient_helps"])
	check(absf(_pmf_sum(s.skill_dist.p) - 1.0) < 1e-6 and absf(s.skill_dist.mean() - t["exp_skills"]) < 1e-6, "スキルの分布：合計1・平均＝期待値 %.2f" % t["exp_skills"])
	check(s.ingredient_dist.mass(t["ingredient_helps"]) > 0.0 and s.skill_dist.mass(t["skills"]) > 0.0, "実際の回数は分布の範囲内")
	s.reset()
	check(s.ingredient_dist.p.size() == 1 and s.skill_dist.mean() == 0.0, "リセットで0回だけの分布に戻る")
