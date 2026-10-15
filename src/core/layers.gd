class_name Layers
extends RefCounted
## Physics layer bits (must match [layer_names] in project.godot).

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const NPC := 1 << 3
const COMPANION := 1 << 4
const PROJECTILE := 1 << 5
## Solid bending constructs: earth walls, pillars, ice walls.
const CONSTRUCT := 1 << 6
const WATER := 1 << 7
const INTERACTABLE := 1 << 8
const TRIGGER := 1 << 9
const WILDLIFE := 1 << 10
const HURTBOX := 1 << 11

## Everything a walking character collides with.
const SOLID := WORLD | CONSTRUCT
## Things the player's attacks can damage.
const PLAYER_ATTACK_TARGETS := ENEMY | WILDLIFE | HURTBOX | CONSTRUCT
## Things enemy attacks can damage.
const ENEMY_ATTACK_TARGETS := PLAYER | COMPANION | HURTBOX | CONSTRUCT
## Line-of-sight / camera collision.
const CAMERA_BLOCKERS := WORLD | CONSTRUCT
