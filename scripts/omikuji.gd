extends RefCounted
## おみくじ: パチモンのメインスキルが1回出るたびに、あたり／はずれを引く。
## はずれが連続はずれの上限まで続いたら、次は必ずあたり（スキル天井と同じ数え方）。
## あたりで連続はずれの回数は0に戻る。

const CHANCE_DEFAULT := 0.10
const LIMIT_DEFAULT := 10
const LIMIT_MAX := 99

## あたりの演出の段階。割合に応じて SMALL〜LARGE の3段階、上限であたったときは GRAND
enum Tier { SMALL = 1, MEDIUM, LARGE, GRAND }

var enabled := false
var chance := CHANCE_DEFAULT
var limit := LIMIT_DEFAULT
## 今の連続はずれ回数
var miss := 0
## あたりが出たときの連続はずれ回数の集計。要素 k が「k 回続けてはずれたあとのあたり」の件数（リセットで消える）
var miss_runs := PackedInt32Array()
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


## 連続はずれの上限に対する今のはずれ回数の割合（0〜1）。上限0のときは常に1
func ratio() -> float:
	if limit <= 0:
		return 1.0
	return clampf(float(miss) / limit, 0.0, 1.0)


## 割合から決まるあたりの演出の段階
static func tier_for(miss_count: int, miss_limit: int) -> int:
	if miss_count >= miss_limit:
		return Tier.GRAND
	var r := float(miss_count) / miss_limit
	if r < 1.0 / 3.0:
		return Tier.SMALL
	if r < 2.0 / 3.0:
		return Tier.MEDIUM
	return Tier.LARGE


## 1回引く。あたりなら引く前のはずれ回数から決めた演出の段階、はずれなら0を返す
func draw() -> int:
	if miss >= limit or rng.randf() < chance:
		var tier := tier_for(miss, limit)
		if miss_runs.size() <= miss:
			miss_runs.resize(miss + 1)
		miss_runs[miss] += 1
		miss = 0
		return tier
	miss += 1
	return 0


## スキルのストック stock 回分を続けて引く。
## 返り値: {"tier": いちばん豪華だったあたりの段階（あたりなしは0）, "hits": あたりの数}
func draw_for(stock: int) -> Dictionary:
	var result := {"tier": 0, "hits": 0}
	if not enabled:
		return result
	for i in stock:
		var tier := draw()
		if tier > 0:
			result["hits"] += 1
			result["tier"] = maxi(result["tier"], tier)
	return result


func reset() -> void:
	miss = 0
	miss_runs = PackedInt32Array()
