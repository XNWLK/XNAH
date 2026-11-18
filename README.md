# XNAH

Auction house prices for **WoW: Forever**: scan the auction house, keep the price history of every item, and find the
gold in it - deals, vendor flips, crafting profits, rising and falling markets. Type `/xnah`.

> Early version, not on CurseForge yet. Made by Xn.

## What it does

- **Full scan** of the whole auction house in seconds (the server allows one about every 15 minutes), plus everything
  you look at while using the auction house normally, plus a quick **watch list scan** of starred items any time.
- **Price history** for every item: lowest price, market value (the average of the cheapest part of the market, so one
  silly listing does not move it), how many are listed and by how many sellers. Every scan is kept for 7 days, a summary
  per day for 60 days, then one per week for a year.
- **Graphs** of price and supply over 1 day, 7, 30, 90 days or all time, with the values under the mouse.
- **Trends**: 3 / 7 / 30-day averages, trend in % per week, day-to-day spread, supply against its 7-day average.
- **Deals**: items listed far under their usual price, items listed under what a vendor pays for them, and vendor items
  that sell for more on the auction house.
- **Crafting**: recipes are learned when you open a profession window (yours or a linked one); the cost to make every
  item (each reagent at its cheapest: vendor, auction house or crafted), what it sells for after the auction house cut,
  profit and margin, and which of your characters know the recipe.
- **Vendor prices**: what a vendor pays for an item, and what vendors sell (recorded when you visit them).
- **Tooltips**: lowest price, market value, averages and trend, vendor prices and crafting cost on every item, times the
  stack size in your bags.

## Commands

| | |
|---|---|
| `/xnah` | open or close the window (also a key binding and the minimap button) |
| `/xnah scan` | full scan (auction house open) |
| `/xnah watch` | scan the watch list |
| `/xnah <item name or link>` | show that item |
| `/xnah raw 5` | print the first auctions of the last full scan as the game gives them |
| `/xnah help` | all commands |

## Install

Unzip `XNAH-x.y.z.zip` from the [releases](https://github.com/XNWLK/XNAH/releases) into
`World of Warcraft\_forever_\Interface\AddOns`, restart the game, type `/xnah`.

## Xn's other projects

[XNRT](https://github.com/XNWLK/XNRT) (raid leading), [XNDR](https://github.com/XNWLK/XNDR) (diminishing returns),
[XNShards](https://github.com/XNWLK/XNShards) (soul shards), [Xn's Warlock Sim](https://github.com/XNWLK/WarlockSIMAddon).
