class_name HealthComponent
extends Node
## Reusable health + poise pool for the player, enemies, companions and wildlife.

signal damaged(amount: float, hit: HitInfo)
signal healed(amount: float)
signal died(hit: HitInfo)
signal poise_broken(hit: HitInfo)
signal changed(current: float, maximum: float)

@export var max_health: float = 100.0
## Poise absorbs `HitInfo.poise_damage`; when it breaks the owner should stagger.
@export var max_poise: float = 30.0
@export var poise_regen_per_sec: float = 15.0
## Seconds after taking damage before poise starts regenerating.
@export var poise_regen_delay: float = 1.2
@export var invulnerable: bool = false

var health: float = 100.0
var poise: float = 30.0
var _since_hit: float = 999.0
var _dead: bool = false


func _ready() -> void:
	health = max_health
	poise = max_poise


func _process(delta: float) -> void:
	_since_hit += delta
	if _since_hit > poise_regen_delay and poise < max_poise:
		poise = minf(max_poise, poise + poise_regen_per_sec * delta)


func is_dead() -> bool:
	return _dead


func ratio() -> float:
	return clampf(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0


## Applies damage. Returns true if this hit broke poise (caller should stagger).
func apply_damage(amount: float, hit: HitInfo = null) -> bool:
	if _dead or invulnerable:
		return false
	amount = maxf(0.0, amount)
	health = maxf(0.0, health - amount)
	_since_hit = 0.0
	var broke := false
	if hit != null and hit.poise_damage > 0.0 and max_poise > 0.0:
		poise -= hit.poise_damage
		if poise <= 0.0:
			poise = max_poise
			broke = true
			poise_broken.emit(hit)
	damaged.emit(amount, hit)
	changed.emit(health, max_health)
	if health <= 0.0:
		_dead = true
		died.emit(hit)
	return broke


func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	var before := health
	health = minf(max_health, health + amount)
	if health > before:
		healed.emit(health - before)
		changed.emit(health, max_health)


func revive(fraction: float = 1.0) -> void:
	_dead = false
	health = max_health * clampf(fraction, 0.01, 1.0)
	poise = max_poise
	changed.emit(health, max_health)


func set_max_health(value: float, refill: bool = false) -> void:
	max_health = maxf(1.0, value)
	health = max_health if refill else minf(health, max_health)
	changed.emit(health, max_health)
