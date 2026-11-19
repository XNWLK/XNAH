# Changelog

## v0.5.0

- New Home page (the first tab): your gold and sales today and this week, net worth, the last scan, and what to do
  today - expired and undercut auctions, deals, strategy finds, watched items under your price, the crafting queue -
  with one button per job. Opens first each session (can be turned off).
- In the game's auction house window: a panel beside it with XNAH's numbers and a 30-day graph for the item you pick
  (or pick to post), with watch list and max price buttons; extra columns "% usual" and "a day" in its lists.
- One-key routine (Sell page): each press of one key (or of Next step) does the next step - cancel an undercut
  auction, then post the items of your sell list at the suggested price. Set the key under AddOns, XNAH.
- Item graph: your own sales and buys as dots, Compare (a second item on the same graph), and Best time (price by
  weekday and hour of the day, and when your sales did best).
- Quick search: a Find box in the title bar for any item or recipe; Alt-click an item in your bags, chat or loot to
  open its page.
- Window: drag the corner (or /xnah size 120) to make it bigger or smaller; lists remember their sorting, the Market
  page its search and filters; right-click a column title to copy the list as text.
- Four new strategies: Recipes worth learning, Cooldown crafts, What to farm, Stock up at a low.

## v0.4.0

- Every crafting recipe of WoW Forever is built in (2,245 recipes, 13 professions with Rogue poisons), also ones none
  of your characters has. Crafting costs, the Crafting page, the queue and the "Can be crafted" filter use them all;
  "Only recipes my characters know" narrows the lists to yours. The posting floor still uses only recipes from your
  profession windows.
- Item page, Used in: every recipe the item goes into, in a list that scrolls. Hover one to see the whole recipe:
  profession and skill-up levels, who knows it, each reagent with its price, the cost, what it sells for and the profit.
  Click it to open what it makes.
- Item names show even for items the game has not loaded yet.

## v0.3.3

- "Search on the auction house" (item page and the right-click menu) also shows the item in the game's own auction
  house window: the Buy tab, the item's name in its search box and the item's listings, ready to buy.
- The message about joined server shards now comes a few seconds after login, so it is not lost among the others.

## v0.3.2

- Smoother game, especially with several game windows open: the listings of the last full scan (kept for sales speed
  and strategies) are packed small a few seconds after the scan, and item names and rarity are checked with the game
  once per item instead of at every login.
- New /xnah perf: how much memory XNAH uses, what it is doing, and how much time it took in the last minute.

## v0.3.1

- Fixed: on WoW Forever the game reports the server shard you landed on as the realm name, and it changes between
  logins - prices were kept apart per shard. XNAH now uses the realm number, and at your next login it joins the data
  of every shard into one realm (newest price of each item; characters, sales and scans along with them).
- Sync accounts: keeps the last 10 backups; a watcher (tools/sync-watch.js) can sync by itself after the game closes,
  for those who want that.

## v0.3.0

- New Strategies page: ready-made ways to make gold, each with its own numbers to adjust, the items it finds right now
  (what to do, target price, profit, risk and why), and buttons to search them, put them on a shopping list or snipe
  them. Items a strategy finds can be marked on their tooltips.
- A guide to every page: opens by itself the first time, and any time with the Guide button or /xnah guide.
- Fixed: rare and epic items could show with a white name (the full scan gave the wrong quality for items the game had
  not loaded yet). XNAH now asks the game for each item's quality.
- Scroll bars on every list (drag them, click above or below, or use the mouse wheel).
- All your WoW accounts in one place: "Sync accounts" (in the XNAH folder, run on your PC with the game closed) joins
  the characters, sales and newest prices of every account on the PC, so the Wealth page shows all your characters.

## v0.2.0

New pages: Sell, Buy, Ledger, Wealth. All ten tabs now fit the window.

- Fixed: item names were missing after a full scan (most items are not loaded by the game yet). Names now come from the
  item links and the rest load in the background.
- Price check: XNAH finds out by itself whether the full scan gives the price of a whole stack or of one item (from the
  first stackable item you search), switches if needed and tells you.
- Sales ledger: reads your auction house mails (sold, bought, expired, cancelled) - income, spending, the auction house
  cut, profit per item, sell-through, a graph per day.
- Net worth: gold, bags, bank, mail and auctions of every character, valued at market prices, with a graph; for your
  bags: sell it on the auction house or to a vendor.
- Sell page: suggested prices by rules (undercut, never under a floor such as the crafting cost, never over a ceiling),
  per-item rules, deposits, one post per click; a cancel scan that finds your undercut auctions.
- Buy page: shopping lists with a max price each (buys the cheapest offers up to the number you need, a click per
  purchase) and the sniper (watches the items you gave a max price, sound and flash when one is listed under it).
- Sales speed: how many of an item sell per day, estimated from two full scans in a row (and your own sales); the best
  hours to post.
- Disenchant value of green, blue and purple gear, and a Deals view of gear listed under it.
- Market shape: walls of listings, reset chances (buy the cheap ones, relist), how many sellers an item has.
- Crafting queue: keep N in stock or craft N times; materials still to buy (to a shopping list); a Craft next button.
- Guild price sharing: XNAH users in your guild share their newest scan; export of prices as text.
- Market page: sold per day column. Item page: sells per day, disenchant value, your trades, market shape, max price
  and shopping list buttons. Tooltip: sells per day, your trades, disenchant value.

## v0.1.0

First version.

- Full scan of the auction house, read in small slices so the game never stalls; items that were not seen count as
  sold out. Prices are also recorded from everything the auction house shows you, and the watch list can be scanned
  any time.
- Price history per item (every scan for 7 days, a day summary for 60 days, then one per week for a year), market value, 3 / 7 / 30-day averages,
  trend, day-to-day spread, supply against its average.
- Window with Market, Item (numbers, graph, ways to make gold with it, crafting), Deals, Crafting, Trends and
  Scan & settings pages.
- Vendor prices: what vendors pay (from the game) and what they sell (recorded when you visit them).
- Crafting costs and profits from every profession window you open.
- Tooltip lines on every item; minimap button; a small bar on the auction house window; key binding.
