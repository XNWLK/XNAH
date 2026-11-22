# Changelog

## v0.8.0

- Deals and Buy are one tab: 8 tabs became 7 (Home, Market, Item, Buy, Sell, Crafting, Gold). Best buys shows
  everything worth buying in one list - your shopping lists, your crafting queue's materials and watched items under
  your price first, then what the ideas found - with why, profit, sales speed, risk and a Buy button in each row.
  Sell ideas moved to the Sell tab, Make ideas to the Crafting tab, Adjust ideas to the Buy tab.
- One key for everything: the Next step key (key bindings, AddOns, XNAH) does whatever comes next where you are, one
  step per press - craft the next recipe of your queue at the profession window, take the next auction house mail at
  a mailbox, and at the auction house finish a purchase, cancel an undercut auction, post the next ticked item, then
  buy your shopping lists, queue materials and the best buys. The bar on the auction house window does the same.
  Mail is still only taken when you press.
- Home is a Today checklist: scan, take your mail, cancel undercut auctions, post, buy, craft - a green tick for each
  step done, the next one lit, and one big Next step button.
- Shopping lists: Keep in stock - keep N of an item, counting what all your characters own (and what you bought that
  is still in the mail), and only buy the rest.
- Price alerts: right-click an item (or the button on its Item page) and type the most you would pay. Any scan or
  search that finds it at or under that price gives a chat line and a sound, and puts it in the sniper's hits to buy
  with a click. Works with the sniper off; never buys by itself.
- Welcome back: at login after a while, a chat line with how many of your auctions ran out and the gold waiting in
  your mailboxes; at the mailbox, what sold, came back or was bought since you were last there. (Settings: Welcome
  back lines.)
- Best day to sell: the day of the week an item usually sells for most, from its daily prices (needs 3 weeks; a
  rising or falling price does not count as a good day). On the Item page, in tooltips and on the Sell tab.
- Crafting queue: its materials show up as buys at a price that keeps the recipe profitable, and what the queue still
  needs is not posted.

## v0.7.3

- Fixed: prices seemed wiped after an update. Right at login the game sometimes does not know the realm yet, and XNAH
  filed new scans under a blank realm name, so the history looked empty. It never uses a blank name now (the realm of
  last time, else the one with the newest scan), asks the game again a moment later, and joins the data filed under
  blank names back in at your next login.
- When two sets of prices are joined, both histories of every item are kept (before, only the copy with the newest
  price was kept).
- New setting "All my characters are on one realm" (on): one set of prices whatever realm number the game gives (it
  is not always the same); prices kept under other realm numbers are joined in.
- Installing with tools/install.ps1 first backs up XNAH's saved data of every account (private/backups, the last 15).

## v0.7.2

- One auction house for both factions: on Forever, Alliance and Horde share the auction house, so XNAH now keeps one
  set of prices per realm. At your next login it joins the data it kept per faction (prices, sales, scans, characters,
  daily gold, auction house time); the Gold page and Home count the characters of both factions.

## v0.7.1

- Fixed: the Open all auction mail bar stayed on screen after walking away from the mailbox. It now belongs to the
  game's mail window and closes with it. (Mail is still only taken when you press the button - never by itself.)

## v0.7.0

- The simple window is gone again: the full window is the one window, made simpler. 12 tabs became 8 - Home, Market,
  Item, Deals, Buy, Sell, Crafting, Gold - and Settings opens from a button in the title bar.
- Market takes in Trends: Rising / Falling filters, a small 7-day price line in each row, Sells a day.
- Deals takes in Strategies: one list of everything worth buying, best first, with the idea that found it, why, and a
  Buy button in each row; Sell ideas, Make ideas, and Adjust ideas for the numbers.
- Buying: one Buy button everywhere (check the price, buy, confirm for stackable things), Best buys on the Buy tab, and
  a Next buy key that steps through them.
- Selling: the Sell tab opens on Worth posting - undercut auctions first, then everything worth posting, ticked (untick
  to keep; remembered); Post next (or the one-key routine key) does one step per press. Your auctions are checked by
  themselves when the auction house opens. The separate sell list is gone.
- Item page: ten plain numbers instead of nineteen, with a fair price to buy and a fair price to sell (also drawn on the
  graph); Buy, Search and one Watch list menu; More numbers shows the rest.
- Gold (Ledger and Wealth joined): profit per week, your best and worst flips, gold per hour of auction house time.
- Mailbox: Open all auction mail.
- Removed: guild price sharing, the price export, the market shape rows.
- Silly prices are judged per day (a day with many scans no longer outweighs the others).

## v0.6.0

- New simple window (what /xnah opens now): your gold on top, a list on the left, the picked line on the right with
  the item's price graph, one sentence what to do, one sentence why and one big button that does it (+ Skip).
  Pages: To do (the best things to do now: buys, sells, mail, expired items, cooldown crafts, the crafting queue, a
  scan), Buy (check the price, buy, confirm), Sell (cancel undercut auctions, post, vendor, junk), Trends (prices going
  up or down) and Wealth (all your gold over time, each character, best sellers). More opens the full window, which
  has a Simple view button back; a tick box on its Scan page chooses which window /xnah opens.
- Silly prices are left out: a price more than 4 times above or below an item's typical price no longer goes into
  its history, averages and graph (three scans in a row: a real change). This also cleans prices saved before.
- Right-click any item: Never suggest buying this (the Scan page lists them to allow them again). Grey items are never
  suggested as buys to sell again.
- Item names in the simple window's lists are in their rarity colour.

## v0.5.1

- Fixed: crafts with a waiting time (transmutes, Mooncloth) counted as a way to get their materials. The elemental
  transmutes go round in a circle, so every essence looked as cheap as the cheapest one and Cooldown crafts showed
  false profits (Water to Undeath). Materials are now never counted as made by such a craft.
- Fixed: in the game's list of stackable goods, "% usual" covered the quantity; it now sits right after the price.

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
