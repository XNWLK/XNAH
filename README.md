# XNAH

Auction house numbers for **WoW: Forever**: scan the auction house, keep the price history of every item, and see where
the gold is - usual prices, trends, cheap listings, vendor flips, crafting costs, your own profit. Type `/xnah`.

**XNAH shows the numbers; you buy and sell in the game's own auction house.** One exception: the **Buy cheapest now**
button on an item.

> Early version, not on CurseForge yet. Made by Xn.

## What it does

One big window. It opens by itself beside the game's auction house (setting "Open with the auction house") and makes
itself smaller to fit there; `/xnah`, the minimap button or a key binding open it anywhere. On top: the four views,
how old the last scan is, **Full scan**, **Scan tracked**, a **Find** box and the Settings gear.

- **Items**: your tracked items on the left (add any item, its price, % of its usual price, trend and a 7-day line),
  and everything about the item you pick on the right:
  - 12 numbers, each explained in plain words when you point at it: cheapest now, market value, usual price, now vs
    usual, trend, ups and downs, sells a day, listed vs normal, **fair price to buy**, **fair price to sell**, vendor
    price, crafting cost.
  - a big price graph (7 days, 30 days, 90 days, a year) with your own sales and buys as dots.
  - what is listed right now, as a price ladder (every price and how many are there).
  - the best day and hour to sell.
  - its crafting cost and recipes, your own trades, how many sellers, price walls, what it costs to buy up everything
    cheap, its disenchant value.
  - **Buy cheapest now**: one press buys the cheapest auction that is not yours, with no "are you sure" box - the
    button shows the exact price, so check it before you press. Stackable goods (ore, cloth ...) take two presses: the
    first asks the server for the exact price, the second buys; a "How many" box sets how many. After each buy it
    searches again, so you can keep pressing.

  Picking an item in the game's auction house shows it here.
- **Market**: every item ever seen on your auction house in one sortable list - lowest price, market value, trend,
  how many are listed, how many sell a day, and a small line of its last 7 days. Filters: **Rising**, **Falling**,
  **Short supply**, **Flooded**, Tracked, Listed now, Can be crafted, quality, and a search box.
- **Your gold**: gold today and this week, profit, gold per hour at the auction house, net worth; income vs spent per
  day (a graph), profit per week, your flips (best and worst), your best sellers, every recent sale and purchase, and
  the gold and items of all your characters.
- **Opportunities**: one list of chances, best first - **far under the usual price**, **vendor flips**, **under what
  a vendor pays**, **under disenchant value**, **price resets** (what it costs to buy up everything cheap) and **few
  sellers** - each with why, buy at, sells for, profit, how many sell a day and the risk. Read-only: you buy in the
  game's auction house.

Also:

- **Full scan** of the whole auction house in seconds (the server allows one about every 15 minutes), plus everything
  you look at while using the auction house normally, plus a quick **scan of your tracked items** any time.
- **Price history** for every item: every scan for 7 days, a summary per day for 60 days, then one per week for a year.
  **Silly prices are left out** (a price far off the item's typical price never makes a normal price look like a
  bargain). Right-click any item to track it, search it on the auction house, or never have it suggested again.
- **In the game's auction house window**: extra columns (% of the usual price, sells a day) in its lists.
- **Your sales** are read from the auction house mails when you open your mailbox.
- **Welcome back**: at login, how many of your auctions ran out and how much gold waits in your mailboxes; at the
  mailbox, what sold, came back or was bought since you were last there.
- **Tooltips**: lowest price, market value, averages and trend, vendor prices, crafting cost, sales speed, disenchant
  value and your own trades on every item.
- **Quick search**: the Find box for any item or recipe; Alt-click any item (bags, chat, loot) to show it in XNAH.
  Lists remember their sorting and can be copied as text. Drag the window's corner to make it bigger or smaller.

## Commands

| | |
|---|---|
| `/xnah` | open or close the window (also a key binding and the minimap button) |
| `/xnah scan` | full scan (auction house open) |
| `/xnah tracked` | search your tracked items (auction house open) |
| `/xnah <item name or link>` | show that item |
| `/xnah settings` | the settings |
| `/xnah raw 5` | print the first auctions of the last full scan as the game gives them |
| `/xnah perf` | how much memory and time XNAH uses |
| `/xnah size 120` | window size in % (or drag its bottom right corner) |
| `/xnah debug` | more messages in chat |
| `/xnah forget` | delete this realm's price data (asks first) |
| `/xnah help` | all commands |

## Several WoW accounts

Each WoW account keeps its own saved data. To see the characters of all your accounts in Your gold, Characters (and share
their sales and the newest prices), double-click `Sync accounts.cmd` in the XNAH project folder on your PC (from GitHub, not the AddOns folder; needs Node.js). It
waits until every game window is closed, backs up the files and joins them. Run it again whenever you want the other
accounts to be up to date. Optional names for the accounts: `private/sync-accounts.json`
`{"labels": {"ACCOUNTFOLDER": "main"}}`.

## Install

Unzip `XNAH-x.y.z.zip` from the [releases](https://github.com/XNWLK/XNAH/releases) into
`World of Warcraft\_forever_\Interface\AddOns`, restart the game, type `/xnah`.

## Xn's other projects

[XNRT](https://github.com/XNWLK/XNRT) (raid leading), [XNDR](https://github.com/XNWLK/XNDR) (diminishing returns),
[XNShards](https://github.com/XNWLK/XNShards) (soul shards), [Xn's Warlock Sim](https://github.com/XNWLK/WarlockSIMAddon).
