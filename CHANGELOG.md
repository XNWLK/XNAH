# Changelog

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
