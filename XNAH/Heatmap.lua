-- [[ K.Heatmap(parent, w, h, opts) ]] a grid of coloured squares: rows (the weekdays) x columns (times of the day).
-- Each square is coloured by how far its number is from the middle: for prices green = cheaper, red = dearer; for
-- supply orange = fewer listed (scarce), blue = more listed. Grey: nothing seen then. Hovering a square tells its numbers.
--   local hm = X.K.Heatmap(parent, w, h, {rows = {"Mon", ...}, cols = {"0-4", ...}, labelW = 30 (room for the row
--     names), headH = 14 (room for the column names), gap = 2, small = true (no text inside the squares),
--     onClick = fn(row, col)})
--   hm:SetData({cells = {[row] = {[col] = {v = -1..1 (minus: cheaper / fewer, plus: dearer / more; nil = no number,
--     dark), text = "short text in the square", title = "tooltip title", lines = {"a line", {"left", "right"}, ...},
--     faint = true (seen only a few times: paler)}}}, scheme = "price" or "supply", empty = "text over the grid when
--     there is nothing"})
--   hm.cells[row][col] = the squares (buttons); hm.GetInfo() -> {scheme, shown (squares with a colour), empty}.
--   K.HeatColor(v, scheme) -> r, g, b of a square.
local ADDON, X = ...
local K = X.K

local BASE = {0.16, 0.16, 0.19}                            -- a square at the middle
local NONE = {0.08, 0.08, 0.09}                            -- nothing seen
local SCHEMES = {
	price = {low = {0.29, 0.87, 0.5}, high = {0.97, 0.44, 0.44}},  -- cheaper / dearer
	supply = {low = {1, 0.6, 0.2}, high = {0.4, 0.62, 1}},          -- fewer listed / more listed
}
K.HEAT_SCHEMES = SCHEMES

function K.HeatColor(v, scheme)
	if v == nil then return NONE[1], NONE[2], NONE[3] end
	local s = SCHEMES[scheme] or SCHEMES.price
	local to = v < 0 and s.low or s.high
	local a = math.min(1, math.abs(v))
	a = 0.15 + 0.85 * a -- even a small difference shows a little
	if v == 0 then a = 0 end
	return BASE[1] + (to[1] - BASE[1]) * a, BASE[2] + (to[2] - BASE[2]) * a, BASE[3] + (to[3] - BASE[3]) * a
end

local function tip(self)
	local d = self.data
	if not d or not d.title then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(d.title)
	for _, l in ipairs(d.lines or {}) do
		if type(l) == "table" then
			GameTooltip:AddDoubleLine(l[1], l[2], 0.6, 0.6, 0.6, 1, 1, 1)
		else
			GameTooltip:AddLine(l, 1, 1, 1, true)
		end
	end
	GameTooltip:Show()
end

function K.Heatmap(parent, w, h, opts)
	opts = opts or {}
	local rows, cols = opts.rows or {}, opts.cols or {}
	local labelW, headH, gap = opts.labelW or 30, opts.headH or 14, opts.gap or 2
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	local cw = (w - labelW - gap * #cols) / math.max(1, #cols)
	local ch = (h - headH - gap * #rows) / math.max(1, #rows)
	local font = opts.small and "GameFontDisableSmall" or "GameFontHighlightSmall"
	for c, name in ipairs(cols) do
		local fs = K.Label(f, name, "GameFontDisableSmall", "CENTER")
		fs:SetPoint("TOPLEFT", labelW + gap + (c - 1) * (cw + gap), 0)
		fs:SetWidth(cw)
		fs:SetWordWrap(false)
	end
	f.cells = {}
	for r, name in ipairs(rows) do
		local y = -(headH + (r - 1) * (ch + gap))
		local fs = K.Label(f, name, "GameFontDisableSmall", "RIGHT")
		fs:SetPoint("TOPLEFT", 0, y - math.floor((ch - 10) / 2))
		fs:SetWidth(labelW - 2)
		fs:SetWordWrap(false)
		f.cells[r] = {}
		for c = 1, #cols do
			local b = CreateFrame("Button", nil, f)
			b:SetSize(cw, ch)
			b:SetPoint("TOPLEFT", labelW + gap + (c - 1) * (cw + gap), y)
			b.bg = b:CreateTexture(nil, "BACKGROUND")
			b.bg:SetAllPoints()
			b.bg:SetColorTexture(NONE[1], NONE[2], NONE[3], 1)
			b.hi = b:CreateTexture(nil, "HIGHLIGHT")
			b.hi:SetAllPoints()
			b.hi:SetColorTexture(1, 1, 1, 0.12)
			if not opts.small then
				b.fs = K.Label(b, "", font, "CENTER")
				b.fs:SetPoint("CENTER", 0, 0)
				b.fs:SetWidth(cw - 2)
				b.fs:SetWordWrap(false)
			end
			b:SetScript("OnEnter", tip)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			if opts.onClick then
				local row, col = r, c
				b:SetScript("OnClick", function() opts.onClick(row, col) end)
			end
			f.cells[r][c] = b
		end
	end
	f.empty = K.Label(f, "", "GameFontDisable", "CENTER")
	f.empty:SetPoint("CENTER", f, "TOPLEFT", labelW + (w - labelW) / 2, -(headH + (h - headH) / 2))
	f.empty:SetWidth(w - labelW - 16)
	f.empty:Hide()

	local info = {shown = 0}
	function f:SetData(data)
		data = data or {}
		local scheme = data.scheme or "price"
		local shown = 0
		for r = 1, #rows do
			for c = 1, #cols do
				local b = self.cells[r][c]
				local d = data.cells and data.cells[r] and data.cells[r][c]
				b.data = d
				local cr, cg, cb = K.HeatColor(d and d.v, scheme)
				b.bg:SetColorTexture(cr, cg, cb, (d and d.faint) and 0.55 or 1)
				if d and d.v ~= nil then shown = shown + 1 end
				if b.fs then b.fs:SetText(d and d.text or "") end
			end
		end
		self.empty:SetText(data.empty or "")
		self.empty:SetShown(shown == 0 and (data.empty or "") ~= "")
		info = {scheme = scheme, shown = shown, empty = shown == 0 and data.empty or nil}
	end
	function f.GetInfo() return info end
	return f
end
