# XNAH

Auction house numbers for **WoW: Forever**: scan the auction house, keep the price history of every item, and see where
the gold is - usual prices, trends, crafting costs, your own profit. Type `/xnah`.

**XNAH shows the numbers; you buy and sell in the game's own auction house.** One exception: the **Buy cheapest now**
button on an item.

> Early version, not on CurseForge yet. Made by Xn.

## What it does

One big window. It opens by itself beside the game's auction house (setting "Open with the auction house") and makes
itself smaller to fit there; `/xnah`, the minimap button or a key binding open it anywhere. On top: the four views,
how old the last scan is, **Full scan**, **Scan tracked**, a **Find** box and the Settings gear.

- **Items**: your tracked items on the left (add any item, its price, % of its usual price, trend and a small line of
  its last 7 days - green when it went up, red when it went down; sort by it, or hide it in Settings; double-click an
  item to put its name in the game's auction house search box - then press Enter there to search),
  and everything about the item you pick on the right, on six pages:
  - **Overview**:
    - 12 numbers, each explained in plain words when you point at it: cheapest now, market value, usual price, now vs
      usual, trend, ups and downs, sells a day, listed vs normal, **fair price to buy**, **fair price to sell**, vendor
      price, crafting cost.
    - a big price graph (7 days, 30 days, 90 days, a year) with your own sales and buys as dots, and a soft band of
      its **usual range** (where the price sat in the 30 days up to each day): a red dot when the price was well over
      it, a green dot when well under it. Click "Usual range" under the graph to hide it.
    - what is listed right now, as a price ladder (every price and how many are there).
    - the best time to sell: a small weekday x time-of-day grid (green = cheaper, red = dearer), the best day and hour.
    - its crafting cost and recipes, your own trades, how many sellers, price walls, what it costs to buy up everything
      cheap, its disenchant value.
  - **Patterns**: when it is cheap or dear, scarce or plentiful - a big grid of the 7 weekdays x 6 times of the day
    (server time), learned from every scan and search and remembered for weeks (recent weeks count most); how jumpy
    its price is (the month's low and high, where today sits); about how many sell a day and how much gold that is.
  - **Compare**: the item and up to 4 more on one graph (ore against bars, a herb against its potion), as prices or as
    % change from the start, with each one's price now and its change over 7 and 30 days (the usual range band
    shows here too, for prices).
  - **Sellers**: how many sellers it has over time, how much of it the biggest seller has, how often the price gets
    cut, and who sells it right now. Seller numbers need searches of that one item (**Scan tracked**, or picking the
    item in the game's auction house): the full scan of the whole auction house gives no seller names.
  - **Crafting**: what crafting it cost on each day against what it sold for after the auction house cut, the margin
    over time, and the recipes that use it, each with its margin now.
  - **Moves with**: the items whose prices go up and down on the same days as this one (ore and its bars, a herb and
    its potion), and the few that move the opposite way, over 30 or 90 days. Moves of the whole auction house are
    taken out first, and links that could be pure chance are left out; moving together does not prove one causes the
    other. **+ Compare** puts an item on the Compare graph. It needs a few weeks of prices to be sure (a warning shows
    until then).
  - **Buy cheapest now** (above every page): one press buys one of the cheapest that is not yours, with no "are you
    sure" box - the button shows the exact price, so check it before you press. Stackable goods (ore, cloth ...) take
    two presses: the first asks the server for the exact price, the second buys; a "How many" box sets how many. After
    each buy it searches again, so you can keep pressing.

  Picking an item in the game's auction house shows it here.
- **Market**: every item ever seen on your auction house in one sortable list - lowest price, market value, trend,
  how many are listed, how many sell a day, and a small line of its last 7 days. Filters: **Rising**, **Falling**,
  **Short supply**, **Flooded**, Tracked, Listed now, Can be crafted, quality, and a search box. Sorting, filters and
  search stay smooth on a big auction house: the work is spread over several frames instead of freezing the game.
- **Your gold**: gold today and this week, profit, gold per hour at the auction house, net worth; income vs spent per
  day (a graph), profit per week, your flips (best and worst), your best sellers, every recent sale and purchase, and
  the gold and items of all your characters. Two more pages:
  - **Gold over time**: the gold of each character and of all of them together, your net worth, and profit per week.
  - **Your items**: per item what you sold and bought, average prices, total profit and profit of one, **time to sell**
    (from putting an auction up to its sale) and **sell-through** (how much of what you put up sold). These two fill in
    from this version on: XNAH learns when you put an auction up from your auctions list, so open the auction house's
    Auctions tab now and then.
- **Trends**: the whole auction house over time, on four pages:
  - **Market index**: one line that shows whether prices on the whole auction house go up or down, like a stock index
    (100 = prices at the start of the period), with extra lines for item groups (cloth, herbs, armor ...).
  - **Item groups**: every group of items - how much is listed, how its prices and supply moved; click a group for its
    line and the items of it that rose and fell the most.
  - **Auction house size**: how much gold, how many auctions, items and units are listed over time, and on which
    weekdays and hours the auction house is fullest.
  - **What changed**: since your last visit, the last day or the last 7 days - biggest risers and fallers, sold out,
    flooded, new and back on the market.

Also:

- **Full scan** of the whole auction house in seconds (the server allows one about every 15 minutes), plus everything
  you look at while using the auction house normally, plus a quick **scan of your tracked items** any time.
- **Price history** for every item: every scan for 7 days, a summary per day for 60 days, then one per week for a year.
  **Silly prices are left out** (a price far off the item's typical price never makes a normal price look like a
  bargain). Right-click any item to track it, search it on the auction house, or never have it suggested again.
  Lists explain a column when you point at its title.
- **Your notes on the graphs**: right-click any graph over time to add a few words to a day ("patch day", "new raid");
  every graph shows them as a thin line, and pointing at it shows the note. Right-click near a note to change or
  remove it. Up to 200 notes, one per day, kept per realm.
- **Your data** (the "Your data ..." button in Settings, or `/xnah data`): how big and how old your saved data is,
  what takes the room, **Slim down** (removes items not seen for a long time - never your tracked items, items in
  Compare, items in your sales and buys, or items your characters own), and **exports** you can paste into a
  spreadsheet: the price history of one item, your sales and buys (with profit), the gold of each character, and your
  tracked items now.
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
| `/xnah data` | your data: its size, slim it down, export it to a spreadsheet |
| `/xnah raw 5` | print the first auctions of the last full scan as the game gives them |
| `/xnah perf` | how much memory and time XNAH uses |
| `/xnah size 120` | window size in % (or drag its bottom right corner) |
| `/xnah debug` | more messages in chat |
| `/xnah forget` | delete this realm's price data (asks first) |
| `/xnah help` | all commands |

## Several WoW accounts

Each WoW account keeps its own saved data. To see the characters of all your accounts in Your gold, Characters (and share
their sales, the newest prices and your graph notes), double-click `Sync accounts.cmd` in the XNAH project folder on your PC (from GitHub, not the AddOns folder; needs Node.js). It
waits until every game window is closed, backs up the files and joins them. Run it again whenever you want the other
accounts to be up to date. Optional names for the accounts: `private/sync-accounts.json`
`{"labels": {"ACCOUNTFOLDER": "main"}}`.

## Install

Unzip `XNAH-x.y.z.zip` from the [releases](https://github.com/XNWLK/XNAH/releases) into
`World of Warcraft\_forever_\Interface\AddOns`, restart the game, type `/xnah`.

## Xn's other projects

[XNRT](https://github.com/XNWLK/XNRT) (raid leading), [XNDR](https://github.com/XNWLK/XNDR) (diminishing returns),
[XNShards](https://github.com/XNWLK/XNShards) (soul shards), [Xn's Warlock Sim](https://github.com/XNWLK/WarlockSIMAddon).
