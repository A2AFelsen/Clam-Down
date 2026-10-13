# Clam Down and Gamble (WoW: Forever)

Version 0.2.0 — starter prototype for WoW: Forever's modern addon API.

## Features
- `/clam start` creates a party/raid game using the general pool of eligible Clam items, rather than specifying one item.
- `/clam bag` scans your own bags for every item whose name contains `Clam`, shows vendor sell price per item and per stack, and totals the eligible inventory value. All eligible Clam items may be used; the game is no longer tied to one named clam. Vendor sell price is the value basis (copper converted to gold/silver/copper for display).
- `/clam ready` / `/clam unready` lets participants signal readiness.
- `/clam go` starts a 3-second countdown after the host sees everyone marked ready.
- Rolls from `/roll 100` are collected while the round is active; `/clam result` resolves the high roll and handles ties by allowing tied players to roll again.
- `/clam leaderboard` displays locally saved wins.
- `/clam deposit PLAYER ITEM_NAME COUNT` records an escrow deposit for a player without the addon.
- `/clam ledger` lists deposits; `/clam paid NUMBER returned|awarded` updates a deposit's status.

## Install
1. Extract the `ClamDownAndGamble` folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`.
2. Restart the game or use `/reload`.
3. Enable **Clam Down and Gamble** in the AddOns list.
4. Type `/clam help`.

## Important limitations in this prototype
- **All participants should install the addon for the most reliable shared state.** The prototype uses addon messages, and does not yet have a robust versioned state-sync protocol or host migration.
- The leaderboard is saved locally per player, not globally shared across the raid.
- Bag scanning only inspects the local player's bags and checks item names. It cannot inspect other players' bags or prove ownership.
- WoW's secure/trade UI rules mean this addon does **not** automatically take items, perform trades, or distribute winnings. For a player without the addon, the host must verify the trade in-game and then use `/clam deposit ...` to record it. This manual ledger is a record, not proof of custody.
- Item names may not be immediately available to the client cache. If a clam does not appear, hover it in your bags and try `/clam bag` again.
- The addon observes the standard `/roll 100` system message format. Client localization or a changed message format may require adjustment.
- This is an initial source prototype and has not been tested in a live WoW: Forever client. Verify roll capture, addon-message behavior, and item APIs in the current build before using it for valuable items.

## Suggested safe workflow
1. Each participant joins the party/raid and installs the addon.
2. Host runs `/clam bag`, then `/clam start Giant Clam 1`.
3. Participants run `/clam ready`; host runs `/clam go` after all participants are ready.
4. Everyone uses `/roll 100`. Host runs `/clam result`. Tied players reroll `/roll 100`; host resolves again with `/clam result`.
5. If anyone without the addon contributes items, host records them with `/clam deposit PLAYER ITEM_NAME COUNT` only after manually confirming the trade.
6. After the game, host manually distributes items and updates the ledger with `/clam paid NUMBER awarded` or `returned`.

## Rules assumption
This prototype treats any item whose displayed name contains the text “Clam” (case-insensitive) as eligible. Each item’s value is its vendor sell price multiplied by its quantity. Items whose price data is not cached may temporarily show as 0c; hover the item and retry `/clam bag`. The host should verify the actual contributed items and quantities manually. The current prototype reports the value of items in each installed player’s own bags; it does not yet automatically aggregate every participant’s wager into a shared pot.
