# XNAH

Auction house prices for **WoW: Forever**: scan the auction house, keep the price history of every item, and find the
gold in it - deals, vendor flips, crafting profits, rising and falling markets. Type `/xnah`.

> Early version, not on CurseForge yet. Made by Xn.

## What it does

Seven pages (`/xnah`), plus Settings behind a button:

- **Home**: what to do today - your gold and sales today and this week, a **Today** checklist (scan, take your mail,
  cancel undercut auctions, post, buy your shopping list, craft your queue) with a tick for every step done, and one
  big **Next step** button.
- **Market**: every item ever seen on your auction house - lowest price, market value, trend, how many are listed,
  how many sell a day, and a small line of its price over the last 7 days. Filters: watch list, listed now, can be
  crafted, quality, **Rising** and **Falling**.
- **Item**: everything about one item in ten plain numbers - including a **fair price to buy** and a **fair price to
  sell** worked out from its history - a graph (your own sales and buys as dots, a second item to compare, the best
  weekday and hour to sell, the **best day to sell**), its recipe and every recipe it goes into, a **Buy** button and a
  **price alert**.
- **Buy**: **Best buys** - everything worth buying right now in one list, best first: your shopping lists, your crafting
  queue's materials and watched items under your price, then what the ideas found, each with why, profit, sales speed,
  risk and a **Buy** button (check the price, buy, confirm). Shopping lists (buy N in all, or **keep N in stock**
  counting what all your characters own), **price alerts** (a chat line and a sound when any scan finds an item at or
  under your price), a sniper, and Adjust ideas. The ideas: listed under what a vendor pays, far under the usual price,
  undercut gaps, resets, momentum, disenchanting, vendor flips, cycles of the day and the week, recipes worth learning,
  cooldown crafts, what to gather and more.
- **Sell**: **Worth posting** - your undercut auctions first, then everything in your bags worth posting, ticked; one
  **Post next** button (or key) cancels and posts one step per press at XNAH's price. XNAH checks your auctions by
  itself when the auction house opens. The best day of the week to sell each item. Posting by hand with price rules
  (undercut, floor, ceiling). Sell ideas: sell now or hold.
- **Crafting**: every recipe of the game is built in; the cost to make every item (each reagent at its cheapest:
  vendor, auction house or crafted), what it sells for after the cut, profit and margin, who knows the recipe, a
  crafting queue (the Next step key buys its materials and crafts it) and make ideas.
- **Gold**: profit per week, your best and worst flips, gold per hour of auction house time, every sale and purchase
  (read from the auction house mails), and the gold and items of all your characters.

Also:

- **One key for everything** (Next step): each press does the next step where you are - craft the next recipe of
  your queue at the profession window, take the next auction mail at a mailbox, and at the auction house finish a
  purchase, cancel an undercut auction, post the next item, buy your list and the best buys. The game allows these only
  on a click or key press, so it is one step per press.
- **Welcome back**: at login, how many of your auctions ran out and how much gold waits in your mailboxes; at the
  mailbox, what sold, came back or was bought since you were last there.
- **Full scan** of the whole auction house in seconds (the server allows one about every 15 minutes), plus everything
  you look at while using the auction house normally, plus a quick **watch list scan** of starred items any time.
- **Price history** for every item: every scan for 7 days, a summary per day for 60 days, then one per week for a year.
  **Silly prices are left out** (a price far off the item's typical price never makes a normal price look like a
  bargain). Right-click any item: Never suggest buying this.
- **In the game's auction house window**: a panel beside it with XNAH's numbers and graph for the item you pick, and
  extra columns (% of the usual price, sells a day) in its lists. A bar above it: Full scan, Watch list, Next step.
- **Mailbox**: Open all auction mail takes the gold and items of every auction house mail and logs your sales.
- **Tooltips**: lowest price, market value, averages and trend, vendor prices, crafting cost, sales speed and your
  own trades on every item.
- **Quick search**: a Find box for any item or recipe; Alt-click any item (bags, chat, loot) to open its page. Lists
  remember their sorting and can be copied as text. Drag the window's corner to make it bigger or smaller.

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

## Install

Unzip `XNAH-x.y.z.zip` from the [releases](https://github.com/XNWLK/XNAH/releases) into
`World of Warcraft\_forever_\Interface\AddOns`, restart the game, type `/xnah`.

## Xn's other projects

[XNRT](https://github.com/XNWLK/XNRT) (raid leading), [XNDR](https://github.com/XNWLK/XNDR) (diminishing returns),
[XNShards](https://github.com/XNWLK/XNShards) (soul shards), [Xn's Warlock Sim](https://github.com/XNWLK/WarlockSIMAddon).
