# Changelog

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
