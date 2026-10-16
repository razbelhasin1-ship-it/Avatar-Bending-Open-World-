# NPCs, dialogue, quests, trainers, merchants, wildlife (`quests_npcs`)

The living layer of the four nations and the game loop on top of it: townsfolk with daily
routines spawned from the settlement anchors, named characters with data-driven dialogue, the
quest system (autoload `Quests`), bending masters who teach techniques through challenges,
merchants with a trade panel, and ambient wildlife.

| Piece | Files |
| --- | --- |
| Quest system | `src/quests/quest_system.gd` (`QuestSystem`, **autoload `Quests`**), `quest_defs.gd` (`QuestDefs`), `quest_conditions.gd` (`QuestConditions`), `quest_actions.gd` (`QuestActions`), `quest_rewards.gd` (`QuestRewards`), `quest_targets.gd` (`QuestTargets`), `quest_props.gd` (`QuestProps`) + `quest_prop_meshes.gd` + `quest_glint.gdshader`, `bending_challenge.gd` (`BendingChallenge`), `challenge_hud.gd` (`ChallengeHud`), `world_hook.gd` |
| NPCs | `src/npc/npc_director.gd` (`NpcDirector`), `npc_provider.gd` (`NpcProvider`), `npc_crowd.gd` (`NpcCrowd`), `npc_character.gd` (`NpcCharacter`), `npc_brain.gd` (`NpcBrain`), `npc_steering.gd` (`NpcSteering`), `npc_routines.gd` (`NpcRoutines`), `npc_looks.gd` (`NpcLooks`), `npc_barks.gd` (`NpcBarks`), `npc_marker.gd` (`NpcMarker`), `npc_registry.gd` (`NpcRegistry`), `world_hook.gd` |
| Dialogue | `src/npc/dialogue/dialogue_tree.gd` (`DialogueTree`), `dialogue_runner.gd` (`DialogueRunner`) |
| Trainers | `src/npc/trainer/trainer_lessons.gd` (`TrainerLessons`) |
| Merchants | `src/npc/shop/trade_goods.gd` (`TradeGoods`, the item catalog), `merchant_stock.gd` (`MerchantStock`), `shop_panel.gd` (`ShopPanel`), `item_icon.gd` (`ItemIcon`) |
| Wildlife | `src/wildlife/wildlife_director.gd` (`WildlifeDirector`), `wildlife_provider.gd` (`WildlifeProvider`), `wildlife_animal.gd` (`WildlifeAnimal`) |
| Data | `data/quests/quests_{water,earth,fire,air,travel}.gd` (`const QUESTS`), `data/dialogue/npcs_{water,earth,fire,air,travel}.gd` (`const NPCS`, `const TREES`), `data/dialogue/ambient.gd` (`BARKS`, `SMALL_TALK`) |
| Tests | `tests/unit/test_quests_npcs.gd`, `tests/integration/test_quests_npcs_world.gd`; playtests `quests_npcs_city`, `quests_npcs_water_chain`, `quests_npcs_mobile` |

DOCS_BODY
