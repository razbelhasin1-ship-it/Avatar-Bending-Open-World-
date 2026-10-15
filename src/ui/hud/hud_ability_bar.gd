class_name HudAbilityBar
extends HBoxContainer
## Bottom-centre row: four technique slots (ability_1..4) and the larger signature slot.

var slots: Array[HudAbilitySlot] = []
var signature: HudAbilitySlot


func _ready() -> void:
	add_theme_constant_override(&"separation", 16)
	alignment = BoxContainer.ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		var s := HudAbilitySlot.new(i)
		s.name = "Slot%d" % (i + 1)
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		add_child(s)
		slots.append(s)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	add_child(gap)
	signature = HudAbilitySlot.new(4, true)
	signature.name = "Signature"
	signature.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(signature)


## Slot by index 0..3, or 4 for the signature.
func slot(i: int) -> HudAbilitySlot:
	return signature if i == 4 else slots[i]


## Slot showing ability `id`, or null.
func find_slot(id: StringName) -> HudAbilitySlot:
	for s in slots:
		if StringName(s.info.get("id", &"")) == id:
			return s
	if StringName(signature.info.get("id", &"")) == id:
		return signature
	return null
