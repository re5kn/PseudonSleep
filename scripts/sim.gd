extends RefCounted
## おてつだいの試行シミュレーション。
##
## 期待値ではなく、1回ごとに乱数で結果を決める。
## - おてつだいの間隔 = おてつだい時間 × げんき補正（そのおてつだいを始めた時点のげんき）
##   おてつだい時間 = 基準時間 × レベル・せいかく・サブスキル・おやすみリボン補正 を小数点以下切り捨て（Params.help_sec）
## - 1回のおてつだいで、確率 p で食材（解放済みの枠から等確率）、1−p できのみ
## - それとは独立に、確率 q でメインスキルが発動してストックに入る
##   ストックが上限のあいだは抽選しない。抽選に 天井 回続けて外れると次は必ず発動する
## - 所持数（パチモンが持っている分＋フィールドに残っている分）が最大所持数に達していると
##   「いつのまに育成」になり、きのみはカビゴンへ自動で渡され、食材もスキルも出ない
## - 途中まで進んだおてつだいは次の「すすめる」に持ち越す

const Params = preload("res://scripts/params.gd")
const Dist = preload("res://scripts/dist.gd")

enum GenkiMode { ALWAYS_HIGH, DECAY }

const BERRY_BOX_MAX := 99999
const INGREDIENT_BOX_MAX := 800
const GENKI_START := 100
const GENKI_DECAY_SEC := 600.0
## メインスキルで回復できるげんきの上限
const GENKI_MAX := 150
## 睡眠で回復するげんきの上限と、それだけ回復する睡眠時間（8時間30分）
const SLEEP_GENKI_MAX := 100
const SLEEP_FULL_MIN := 510

var params: Params
var rng := RandomNumberGenerator.new()
var genki_mode: int = GenkiMode.ALWAYS_HIGH
## DECAY モードで減り始めた時刻と、そのときのげんき（メインスキルで増減すると、減る間隔はそのままこの値を足し引きする）
var genki_origin_sec := 0.0
var genki_base := GENKI_START
## DECAY モードで減り始めるときのげんき（画面下部で設定する初期値）
var genki_start := GENKI_START

var elapsed_sec := 0.0
## 進行中のおてつだいが終わる時刻
var next_help_at := 0.0
## まだタップしていない（パチモンが持っている）分
var pending := {}
## タップ済みでフィールドに残っている分
var on_field := {}
var berry_box := {}
var ingredient_box := {}
var skill_stock := 0
## メインスキルの抽選に続けて外れた回数（天井用）
var skill_miss := 0
## スキルが発動するまでに続けて外れた回数の集計（リセットまで）。要素 k が「k 回続けて不発のあと発動した」回数。
## 発動しないまま途切れた分（ストックがあるタップや、妖精のおてつだいの始め直し）は数えない
var miss_runs := PackedInt32Array()
## ストックのうち天井で発動した分
var ceiling_stock := 0
var totals := {}
## おてつだい1回ごとの記録（リセットまで）。要素は
## {"t": 終わった時刻(秒), "id": 獲得したもの（いつのまに育成なら ""）, "amount": 獲得数, "skill": Skill}
## パチモンをタップした時点の行も時刻順に混ざる。タップの行は
## {"t": タップした時刻(秒), "tap": true, "amount": フィールドへ出した数, "stock": 使ったスキルのストック, "ceiling": うち天井の分}
var help_log: Array[Dictionary] = []
## リセットからの食材回数・スキル回数の確率分布（期待値と同じく「すすめる」ごとに、その時点の状態から求めてたたみ込む）
var ingredient_dist := Dist.new()
var skill_dist := Dist.new()

enum Skill { NONE, HIT, CEILING }


func _init(p: Params = null) -> void:
	params = p if p != null else Params.new()
	rng.randomize()
	reset()


func reset() -> void:
	elapsed_sec = 0.0
	genki_origin_sec = 0.0
	genki_base = genki_start
	pending.clear()
	on_field.clear()
	berry_box.clear()
	ingredient_box.clear()
	skill_stock = 0
	skill_miss = 0
	ceiling_stock = 0
	totals = new_stats()
	miss_runs = PackedInt32Array()
	help_log.clear()
	ingredient_dist.reset()
	skill_dist.reset()
	next_help_at = help_interval_at(0.0)


func new_stats() -> Dictionary:
	return {
		"seconds": 0.0,
		"helps": 0,
		"berry_helps": 0,
		"ingredient_helps": 0,
		"skills": 0,
		"skill_ceiling_hits": 0,
		"full_helps": 0,
		"auto_fed": 0,
		"carry_lost": 0,
		"items": {},
		# 期待値（「すすめる」1回ごとに、そのあいだのおてつだい回数から二項分布で求めて足していく）
		"exp_berry_helps": 0.0,
		"exp_ingredient_helps": 0.0,
		"exp_skills": 0.0,
	}


func set_genki_mode(mode: int) -> void:
	genki_mode = mode
	genki_origin_sec = elapsed_sec
	genki_base = genki_start


## げんきの初期値を start にし、今のげんきもその値から減り始め直す（0〜GENKI_MAX）
func set_genki_start(start: int) -> void:
	genki_start = clampi(start, 0, GENKI_MAX)
	genki_origin_sec = elapsed_sec
	genki_base = genki_start


func genki_at(t: float) -> int:
	if genki_mode == GenkiMode.ALWAYS_HIGH:
		return GENKI_START
	return maxi(0, genki_base - _genki_decayed(t))


func _genki_decayed(t: float) -> int:
	return int(floor((t - genki_origin_sec) / GENKI_DECAY_SEC))


## 今のげんきを amount 増やす（負なら減らす。0〜GENKI_MAX）。10分ごとに減る区切りはそのまま。
## 増やすときは自分のせいかく（げんき回復）の倍率を掛けて小数点以下を切り捨てる。減らすときは掛けない。
## 「81以上で固定」のときは変わらない。
func add_genki(amount: int) -> void:
	if genki_mode == GenkiMode.ALWAYS_HIGH:
		return
	if amount > 0:
		# 5×1.2=6.0 などが浮動小数でわずかに小さくなり、1減らないように少し足してから切り捨てる
		amount = int(floor(amount * params.genki_recovery_factor() + 1e-6))
	var g := clampi(genki_at(elapsed_sec) + amount, 0, GENKI_MAX)
	genki_base = g + _genki_decayed(elapsed_sec)


## 睡眠 minutes 分で回復するげんき。補正なしでは8時間30分で100（それより長くても100）。
## それにせいかく（げんき回復）の倍率を掛けて四捨五入する（下降なら最大88、上昇なら最大120）
func sleep_recovery(minutes: int) -> int:
	var base := minf(SLEEP_GENKI_MAX, float(minutes) / SLEEP_FULL_MIN * SLEEP_GENKI_MAX)
	return int(round(base * params.genki_recovery_factor()))


## minutes 分眠る。そのあいだもおてつだいとげんきの減少は通常どおり進み、起きた時点でげんきが回復する。
## 回復しても100を超えない（もともと100以上なら変わらない）。
## help が false なら時間だけ進め、げんきは減りも回復もしない（休んでいる妖精用）。進めた間の結果を返す
func sleep(minutes: int, help := true) -> Dictionary:
	var sec := minutes * 60.0
	if not help:
		idle(sec)
		return new_stats()
	var r := advance(sec)
	if genki_mode == GenkiMode.DECAY:
		var g := genki_at(elapsed_sec)
		if g < SLEEP_GENKI_MAX:
			var after := mini(SLEEP_GENKI_MAX, g + sleep_recovery(minutes))
			genki_base = after + _genki_decayed(elapsed_sec)
	return r


static func genki_multiplier(genki: int) -> float:
	if genki >= 81:
		return 0.45
	if genki >= 61:
		return 0.52
	if genki >= 41:
		return 0.58
	if genki >= 1:
		return 0.66
	return 1.0


func help_interval_at(t: float) -> float:
	return params.help_sec() * genki_multiplier(genki_at(t))


## seconds 秒ぶんおてつだいを進め、その間の結果を返す。
func advance(seconds: float) -> Dictionary:
	var r := new_stats()
	r["seconds"] = seconds
	var end := elapsed_sec + seconds
	var miss_before := skill_miss
	var stock_before := skill_stock
	while next_help_at <= end + 1e-6:
		var t := next_help_at
		_do_help(r, t)
		next_help_at = t + help_interval_at(t)
	elapsed_sec = end
	_add_expected(r, miss_before, stock_before)
	_accumulate(r)
	return r


## 進めたあいだの期待値を r に入れ、累計の確率分布も更新する。
## いつのまに育成になったおてつだいは食材もスキルも抽選しないので数えない。
## 残りの k 回を独立な試行とみなし、食材は k×食材確率、きのみは k×(1−食材確率)（二項分布の期待値）。
## スキルは天井とストック上限があるので skill_pmf で求める。
func _add_expected(r: Dictionary, miss_before: int, stock_before: int) -> void:
	var k: int = r["helps"] - r["full_helps"]
	var q := params.ingredient_chance() if not params.active_ingredients().is_empty() else 0.0
	r["exp_ingredient_helps"] = k * q
	r["exp_berry_helps"] = k * (1.0 - q)
	ingredient_dist.add(Dist.binomial(k, q))
	var sp := skill_pmf(k, params.skill_chance(), params.skill_ceiling,
		params.max_skill_stock, miss_before, stock_before)
	r["exp_skills"] = pmf_mean(sp)
	skill_dist.add(sp)


## 不発カウント miss・ストック stock の状態から k 回抽選したときの、スキル発動回数の期待値（天井込み）。
static func skill_mean(k: int, p: float, ceiling: int, max_stock: int, miss: int, stock: int) -> float:
	return pmf_mean(skill_pmf(k, p, ceiling, max_stock, miss, stock))


static func pmf_mean(pmf: PackedFloat64Array) -> float:
	var m := 0.0
	for i in pmf.size():
		m += i * pmf[i]
	return m


## 不発カウント miss・ストック stock の状態から k 回抽選したときの、スキル発動回数の確率分布（天井込み）。
## 要素 i が「i 回発動する確率」。
## (不発カウント, ストック) の各状態にいる確率を、抽選1回ごとに追いかける。
## ストックが上限の状態では抽選しない。不発カウントが ceiling 以上なら必ず発動し、発動したら0に戻る。
## 途中でタップしないので、発動回数は最後のストック − 最初のストック。
static func skill_pmf(k: int, p: float, ceiling: int, max_stock: int, miss: int, stock: int) -> PackedFloat64Array:
	var states := {Vector2i(miss, stock): 1.0}
	for i in k:
		var next := {}
		for st: Vector2i in states:
			var pr: float = states[st]
			if st.y >= max_stock:
				next[st] = next.get(st, 0.0) + pr
				continue
			var hit := 1.0 if st.x >= ceiling else clampf(p, 0.0, 1.0)
			if hit > 0.0:
				var fired := Vector2i(0, st.y + 1)
				next[fired] = next.get(fired, 0.0) + pr * hit
			if hit < 1.0:
				var missed := Vector2i(st.x + 1, st.y)
				next[missed] = next.get(missed, 0.0) + pr * (1.0 - hit)
		states = next
	var pmf := PackedFloat64Array()
	pmf.resize(maxi(0, max_stock - stock) + 1)
	for st: Vector2i in states:
		pmf[maxi(0, st.y - stock)] += states[st]
	return pmf


## 連続不発の回数（予約されるまでに続けて不発になる回数）の理論上の平均。
## k 回以上続く確率は (1−p)^k（上限 ceiling より先は続かない）なので、平均はその k = 1〜ceiling の和
static func miss_run_mean(p: float, ceiling: int) -> float:
	var q := 1.0 - clampf(p, 0.0, 1.0)
	var m := 0.0
	var r := 1.0
	for k in maxi(0, ceiling):
		r *= q
		m += r
	return m


## おてつだいをせずに時間だけ進める（おてつだいを休んでいる妖精用）。休んでいるあいだはげんきも減らない
func idle(seconds: float) -> void:
	elapsed_sec += seconds
	genki_origin_sec += seconds


## 今からおてつだいを始め直す。持っている分とスキルのストック・不発カウントは捨てる（げんきはそのまま）
func restart_help() -> void:
	pending.clear()
	skill_stock = 0
	skill_miss = 0
	ceiling_stock = 0
	next_help_at = elapsed_sec + help_interval_at(elapsed_sec)


func _do_help(r: Dictionary, t: float) -> void:
	r["helps"] += 1
	var held := held_count()
	var limit := params.carry_limit()
	if held >= limit:
		r["full_helps"] += 1
		r["auto_fed"] += params.berry_amount()
		help_log.append({"t": t, "id": "", "amount": 0, "skill": Skill.NONE})
		return
	var room := limit - held
	var slots := params.active_ingredients()
	var id: String
	var got: int
	if not slots.is_empty() and rng.randf() < params.ingredient_chance():
		var ing: Dictionary = slots[rng.randi_range(0, slots.size() - 1)]
		r["ingredient_helps"] += 1
		id = ing["id"]
		var amount := params.ingredient_amount(ing)
		if params.has_extra_ingredient() and rng.randf() < params.ex_extra_ingredient_prob:
			amount += params.ex_extra_ingredient
		got = _gain(r, id, amount, room)
	else:
		r["berry_helps"] += 1
		id = params.berry["id"]
		got = _gain(r, id, params.berry_amount(), room)
	var skill := _skill_lottery(r)
	help_log.append({"t": t, "id": id, "amount": got, "skill": skill})


func _skill_lottery(r: Dictionary) -> Skill:
	if skill_stock >= params.max_skill_stock:
		return Skill.NONE
	var by_ceiling := skill_miss >= params.skill_ceiling
	if rng.randf() < params.skill_chance() or by_ceiling:
		r["skills"] += 1
		if by_ceiling:
			r["skill_ceiling_hits"] += 1
			ceiling_stock += 1
		skill_stock += 1
		if miss_runs.size() <= skill_miss:
			miss_runs.resize(skill_miss + 1)
		miss_runs[skill_miss] += 1
		skill_miss = 0
		return Skill.CEILING if by_ceiling else Skill.HIT
	skill_miss += 1
	return Skill.NONE


func _gain(r: Dictionary, id: String, amount: int, room: int) -> int:
	var got := mini(amount, room)
	pending[id] = int(pending.get(id, 0)) + got
	var items: Dictionary = r["items"]
	items[id] = int(items.get(id, 0)) + got
	r["carry_lost"] += amount - got
	return got


func _accumulate(r: Dictionary) -> void:
	for key in r:
		if key == "items":
			var items: Dictionary = totals["items"]
			for id in r["items"]:
				items[id] = int(items.get(id, 0)) + int(r["items"][id])
		else:
			totals[key] += r[key]


static func sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


## 現在の所持数。フィールドに残したままの分も含む。
func held_count() -> int:
	return sum(pending) + sum(on_field)


## 記録のうちタップの行か
static func is_tap(e: Dictionary) -> bool:
	return e.get("tap", false)


func pending_count() -> int:
	return sum(pending)


func is_full() -> bool:
	return held_count() >= params.carry_limit()


## パチモンの上にアイコンを出すかどうか。
func has_icon() -> bool:
	return pending_count() > 0 or skill_stock > 0


## タップしたときの処理。持っている分をフィールドへ出し、スキルのストックを消費する。
## to_field が false なら持っている分はフィールドへ出さずに消す（妖精用）
func drop(to_field := true) -> Dictionary:
	var result := {"items": pending.duplicate(), "stock": skill_stock, "ceiling": ceiling_stock}
	var dropped := pending_count()
	if dropped > 0 or skill_stock > 0:
		help_log.append({"t": elapsed_sec, "tap": true, "amount": dropped, "stock": skill_stock, "ceiling": ceiling_stock})
	if to_field:
		for id in pending:
			on_field[id] = int(on_field.get(id, 0)) + int(pending[id])
	pending.clear()
	# メインスキルのストックがあったタップでは、不発カウントも0から数え直す
	if skill_stock > 0:
		skill_miss = 0
	skill_stock = 0
	ceiling_stock = 0
	return result


## ストック上限を下げたとき、あふれた分を捨てる（天井で出た分は後から捨てる）
func clamp_stock() -> void:
	skill_stock = mini(skill_stock, params.max_skill_stock)
	ceiling_stock = mini(ceiling_stock, skill_stock)


func box_for(id: String) -> Dictionary:
	return berry_box if params.is_berry(id) else ingredient_box


func box_max_for(id: String) -> int:
	return BERRY_BOX_MAX if params.is_berry(id) else INGREDIENT_BOX_MAX


## フィールド上の id を収容箱へ入れる。入った数を返す（箱に入りきらない分はフィールドに残る）。
func collect(id: String) -> int:
	var n := int(on_field.get(id, 0))
	if n <= 0:
		return 0
	var box := box_for(id)
	var take := mini(n, box_max_for(id) - sum(box))
	if take <= 0:
		return 0
	box[id] = int(box.get(id, 0)) + take
	if n - take > 0:
		on_field[id] = n - take
	else:
		on_field.erase(id)
	return take
