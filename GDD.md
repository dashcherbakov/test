🌊 GDD — "Deep Scrub" (working title)
Mechanics faithfully mirrored from Sludgineers (Snickerdoodle Games). Only the context/fiction is different: countryside pollution cleanup → underwater ocean salvage.

1. One-pager / Core fantasy
You pilot a lone salvage sub through a dying ocean. Suck up plastic goo, drill coral-encrusted wrecks, filter toxic blooms, seal leaking vents — every drop of grime you remove restores the reef beneath. Haul raw debris back to your floating salvage rig, where it's slowly refined into valuable materials. Spend those materials on a tech tree to build a faster sub, better tools, and auto-cleaning drones. Cleaner ocean → bigger contracts → deeper, more dangerous zones — all the way down to the Deep Trench, where something enormous is tangled in plastic.

An active incremental: 2D side-scrolling cleanup missions you drive by hand, fused with a passive refinery idle layer and a tech-tree progression — the exact Sludgineers loop, re-skinned.

2. Design pillars (identical to Sludgineers)
Visible restoration — contamination visibly disappears; the seabed, coral, and water clarity regenerate as you clean (the "Spilled!/PowerWash" satisfaction).
Active + idle fusion — manual cleaning on maps feeds a refinery that keeps producing in the background.
One-at-a-time onboarding — each new zone introduces exactly one new mechanic before mixing them.
Always a reason to return — tech tree, quests, and 100%-restoration goals pull you back into earlier zones.
3. Core loop (identical to Sludgineers)
text

Pilot sub → clean contamination → collect cash + raw materials
    ↓
Salvage Rig: refinery converts raw → refined (slowly, over time)
    ↓
Spend refined + cash on tech tree (tools, sub, drones, rig)
    ↓
Unlock new zones & quests → repeat; boss zone at the end
4. Systems — faithful mapping, new fiction
4.1 Two-state structure (as in reference)
Mission map: 2D side-scrolling zone you cruise in your sub; contamination + objectives here.
Salvage Rig (hub): refinery processing, tech tree, quest board, zone selection. Refining runs passively.
4.2 Contamination types → resource drops (re-skin only)



Sludgineers	Underwater equivalent	Tool used
Gunk (suck)	Plastic goo / microplastic sludge	Suction nozzle
Ore (jackhammer)	Coral-encrusted wrecks / mineral nodules	Hull cutter / drill
Gas (filter)	Toxic chemical blooms / gas vents	Filtration unit
Volcano (kill/seal)	Leaking thermal vents / ruptures	Foam sealant
(cash only)	Loose debris, litter, tangled nets	Suction
4.3 Resources & refinery (the idle layer — same gate as reference)
Raw: Plastic, Ore, Toxins (+ general Scrap).
Refinery (rig-upgradeable): converts raw → refined slowly over time — e.g. 28 of each per 60s base, faster with rig upgrades — matching Sludgineers' pacing and its role as the progression gate.
Refined: Recycled Plastic, Salvaged Metal, Purified Compounds. All meaningful tech-tree upgrades cost refined materials — exactly as in the reference.
4.4 Tech tree (~25 nodes, data-driven — same shape)
Sub upgrades: hull tiers (speed, capacity, HP), sonar range, storage.
Tool tiers: Suction nozzle I–V, Cutter I–V, Filter I–V, Sealant I–V (larger streams, faster rates, multi-target).
Drones (automation): Cleaning drone, Recycle drone, Deep-sea drone — auto-clean nearby contamination over time.
Rig upgrades: refine speed, parallel refinement, raw/refined storage.
4.5 Zones (area unlocks — new fiction, same progression)
Kelp Shallows (start)
Coral Reef
Ship Graveyard
Abandoned Chemical Rig
The Deep Trench (final — boss)
4.6 Quests
Quest board at the rig: restore zone to 100%, recycle N plastic, find lost anchors, seal N vents. Rewards = cash + raw materials (mirrors the "complete quests" loop).

4.7 Boss
Deep Trench finale: the Kelp Tyrant — a giant creature smothered in plastic; you free it by sealing its vents and burning through its sludge, then it becomes an ally/shopkeeper (mirrors Sludgineers' boss + ending gag).

4.8 Map replay & farming
Zones replayable to farm resources — the reference's core endgame loop, kept as-is (no added prestige or QoL deviations).

5. UI / Presentation
Map HUD: cash + resource counters (K/M/B auto-format), active tool, zone restoration %, mini-quest tracker.
Rig screen: refinery status (raw→refined queues + rates), tech tree panel, quest board, zone select.
Feedback: contamination shrink/dissolve, floating "+5 Plastic", water clarity brightening, sonar ping on loot.
Art: no assets exist → polished placeholder graphics (Godot primitives + generated 2D sprites), swappable later.
6. Godot Architecture (4.7.2)
text

res://
├── scenes/2d/
│   ├── main.tscn                  # bootstrap: swaps Map ↔ Rig
│   ├── map/zone_map.tscn          # 2D side-scroller zone (tiles, contamination spawns)
│   ├── map/sub.tscn               # player sub (CharacterBody2D, tool beams)
│   ├── map/contamination.tscn     # typed contamination (goo/wreck/vent/leak)
│   └── rig/rig.tscn               # refinery + tech tree + quest board UI
├── scripts/
│   ├── economy/refinery.gd        # pure math: refine rates, costs, offline calc (testable)
│   ├── economy/tech_tree.gd       # node definitions + purchase logic (Resource-driven)
│   ├── economy/resource_types.gd  # enum + formatting
│   ├── map/sub_controller.gd      # movement, tool beam vs contamination
│   ├── map/contamination.gd       # HP, required tool, drops
│   ├── rig/rig_ui.gd, tech_tree_panel.gd, quest_board.gd
│   └── quests/quest_manager.gd    # quest definitions + tracking
├── data/tech_tree.tres, zones.tres, quests.tres
├── tests/test_refinery.gd, test_tech_tree.gd   # GUT
Autoloads (extend existing): GameManager (Map↔Rig switching), EventBus (add resources_changed, zone_restored, quest_completed, tool_equipped), SaveManager (persist refinery queues, tech tree, zones, quests), AudioManager (SFX hooks).
Refinery offline math: refined += rate * elapsed_real_time, capped, test-verified.
Per AGENTS.md: typed GDScript, no get_node() in _process (cached refs), data-driven .tres.
7. Build phases (after approval)
Phase 1 — GDD file: overwrite res://GDD.md with this refined doc.
Phase 2 — Economy core: refinery.gd, tech_tree.gd, data .tres + GUT tests (refine rates, costs, offline accrual, purchase logic).
Phase 3 — Playable map loop: Zone scene, Sub controller, typed contamination, four tools, cash + raw drops.
Phase 4 — Rig & progression: refinery screen, tech tree UI, zone unlock, quest board, save/load wiring.
Phase 5 — Boss + juice: Deep Trench boss, restoration visuals, audio, achievements.
