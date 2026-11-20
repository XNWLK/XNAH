# XNAH

Auction house prices for **WoW: Forever**: scan the auction house, keep the price history of every item, and find the
gold in it - deals, vendor flips, crafting profits, rising and falling markets. Type `/xnah`.

> Early version, not on CurseForge yet. Made by Xn.

## What it does

- **The simple window** (`/xnah`): your gold on top, a list on the left, and on the right the item's price graph, one
  sentence what to do, one sentence why, and one big button that does it. Five pages: **To do** (the best things to do
  now), **Buy**, **Sell**, **Trends** and **Wealth**. XNAH's strategies run by themselves and fill the lists. **More**
  opens the full window with every page below.
- **Home**: what to do today - your gold and sales today and this week, and a to-do list (expired and undercut
  auctions, deals, strategy finds, watched items under your price, crafting queue) with one button per job.
- **Full scan** of the whole auction house in seconds (the server allows one about every 15 minutes), plus everything
  you look at while using the auction house normally, plus a quick **watch list scan** of starred items any time.
- **Silly prices left out**: a price far off the item's typical price (a few silly listings, a scan that saw only
  those) never makes a normal price look like a bargain. Right-click any item: Never suggest buying this.
- **Price history** for every item: lowest price, market value (the average of the cheapest part of the market, so one
  silly listing does not move it), how many are listed and by how many sellers. Every scan is kept for 7 days, a summary
  per day for 60 days, then one per week for a year.
- **Graphs** of price and supply over 1 day, 7, 30, 90 days or all time, with the values under the mouse, your own
  sales and buys as dots, a second item to compare, and the best weekday and hour to sell.
- **In the game's auction house window**: a panel beside it with XNAH's numbers and graph for the item you pick, and
  extra columns (% of the usual price, sells a day) in its lists.
- **Trends**: 3 / 7 / 30-day averages, trend in % per week, day-to-day spread, supply against its 7-day average.
- **Deals**: items listed far under their usual price, items listed under what a vendor pays for them, and vendor items
  that sell for more on the auction house.
- **Crafting**: every recipe of the game is built in (open your profession windows so XNAH knows which ones your
  characters have); the cost to make every item (each reagent at its cheapest: vendor, auction house or crafted), what it sells for after the auction house cut,
  profit and margin, and which of your characters know the recipe.
- **Vendor prices**: what a vendor pays for an item, and what vendors sell (recorded when you visit them).
- **Tooltips**: lowest price, market value, averages and trend, vendor prices and crafting cost on every item, times the
  stack size in your bags.

- **Sales speed**: how many of an item sell per day (estimated from full scans and your own sales) and the best hours
  to post.
- **Sell**: suggested prices by your rules (undercut, floor, ceiling), one post per click, a cancel scan for your
  undercut auctions, and a **one-key routine**: each press of one key cancels an undercut auction or posts the next
  item of your sell list.
- **Buy**: shopping lists with max prices, and a sniper that tells you when a watched item is listed under your price.
- **Ledger**: your sales, purchases, expired auctions and profit, read from the auction house mails.
- **Wealth**: net worth of all your characters with a graph, and what in your bags to sell where.
- **Strategies**: ready-made ways to make gold (vendor floor, buy the dip, undercut gaps, resets, momentum, scarcity,
  crafting, disenchanting, time-of-day and weekday cycles, recipes worth learning, cooldown crafts, what to farm,
  stocking up at a low and more) with the items each one finds right now.
- **Quick search**: a Find box for any item or recipe, and Alt-click on any item (bags, chat, loot) opens its page.
  Lists remember their sorting and can be copied as text.
- **Disenchant value** of gear, **market shape** (walls, reset chances, sellers), a **crafting queue**, and **guild
  price sharing**.

## Commands

| | |
|---|---|
| `/xnah` | open or close the window (also a key binding and the minimap button) |
| `/xnah scan` | full scan (auction house open) |
| `/xnah watch` | scan the watch list |
| `/xnah <item name or link>` | show that item |
| `/xnah raw 5` | print the first auctions of the last full scan as the game gives them |
| `/xnah guide` | the guide to every page |
| `/xnah perf` | how much memory and time XNAH uses |
| `/xnah size 120` | window size in % (or drag its bottom right corner) |
| `/xnah help` | all commands |

## Several WoW accounts

Each WoW account keeps its own saved data. To see the characters of all your accounts on the Wealth page (and share
their sales and the newest prices), double-click `Sync accounts.cmd` in the XNAH project folder on your PC (from GitHub, not the AddOns folder; needs Node.js). It
waits until every game window is closed, backs up the files and joins them. Run it again whenever you want the other
accounts to be up to date. Optional names for the accounts: `private/sync-accounts.json`
`{"labels": {"ACCOUNTFOLDER": "main"}}`.

## Hourly prices without visiting the auction house (optional)

`Hourly prices.cmd` (in the XNAH project folder on your PC; needs Node.js) fetches your auction house about once an
hour from the game's official web API (the Battle.net developer API) and hands it to XNAH through a small extra addon
folder, `XNAH_Data`, which it writes into your AddOns folder. XNAH reads it at login: new hours arrive with `/reload`
or a relog (the first time, restart the game). Settings shows how fresh it is.

1. On the official Battle.net developer site, open API Access and create a client. Copy its Client ID and Client
   Secret - your own, never share them; XNAH never contains a key.
2. Make the file `private/api.json` in the project folder:
   `{"clientId": "...", "clientSecret": "...", "region": "eu", "houseId": 111}`.
3. Find your auction house: note in the game how many of a common item are listed and the price of one rare listing,
   then run `node tools/api-fetch.js --find-house 2592*1534 13468=33g33s33c` (item ID * count listed, item ID = price
   of one). It tells you which `houseId` to use.
4. Double-click `Hourly prices.cmd` and leave its window open.

Data source: Blizzard Entertainment, through the game's official web API. What is kept: on your PC, a few numbers per
item for each hourly snapshot (lowest price, market value, quantity, auctions) for at most 7 days, then deleted; the
raw listings are not kept. `XNAH_Data` holds the last 24 hours. XNAH records these as price points in its own history,
like a full scan. The Forever part of the web API is not officially documented, so it may change or stop without
notice.

## Install

Unzip `XNAH-x.y.z.zip` from the [releases](https://github.com/XNWLK/XNAH/releases) into
`World of Warcraft\_forever_\Interface\AddOns`, restart the game, type `/xnah`.

## Xn's other projects

[XNRT](https://github.com/XNWLK/XNRT) (raid leading), [XNDR](https://github.com/XNWLK/XNDR) (diminishing returns),
[XNShards](https://github.com/XNWLK/XNShards) (soul shards), [Xn's Warlock Sim](https://github.com/XNWLK/WarlockSIMAddon).
