class_name PointAllocator
extends RefCounted

signal points_changed
signal points_reset

const STAT_MIN := 1
const STAT_MAX := 20

var total_points: int = GameData.FREE_POINTS
var base_stats: Dictionary = {}
var spent: Dictionary = {
	"leadership": 0,
	"charisma": 0,
	"strategy": 0,
	"combat": 0,
	"defense": 0,
}
var _has_been_setup: bool = false

func setup(personality: int, alignment: int, fighter_type: int) -> void:
	var was_already_setup := _has_been_setup
	base_stats = GameData.get_base_stats(personality, alignment, fighter_type)
	total_points = GameData.FREE_POINTS
	for key in spent.keys():
		spent[key] = 0
	_has_been_setup = true
	points_changed.emit()
	if was_already_setup:
		points_reset.emit()

func points_spent() -> int:
	var sum := 0
	for v in spent.values():
		sum += v
	return sum

func points_remaining() -> int:
	return total_points - points_spent()

func current_value(stat: String) -> int:
	return base_stats.get(stat, 5) + spent.get(stat, 0)

func can_increase(stat: String) -> bool:
	return points_remaining() > 0 and current_value(stat) < STAT_MAX

func can_decrease(stat: String) -> bool:
	return spent.get(stat, 0) > 0 and current_value(stat) > STAT_MIN

func increase(stat: String) -> void:
	if can_increase(stat):
		spent[stat] += 1
		points_changed.emit()

func decrease(stat: String) -> void:
	if can_decrease(stat):
		spent[stat] -= 1
		points_changed.emit()

func apply_to_character(c: Character) -> void:
	c.leadership = current_value("leadership")
	c.charisma = current_value("charisma")
	c.strategy = current_value("strategy")
	c.combat = current_value("combat")
	c.defense = current_value("defense")
