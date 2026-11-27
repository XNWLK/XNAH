-- The stand-in's mouse buttons (tests-44: dragging rows of the tracked list). As the game does it: a press goes to the
-- frame under the mouse (OnMouseDown); letting go goes to that SAME frame wherever the mouse is now (OnMouseUp), then
-- a click (OnClick) only when the mouse is still over it. IsMouseButtonDown tells which buttons are held.
--   W.mouseDown(frame, x, y, button)   press on a frame with the mouse at x, y (screen pixels, as GetCursorPosition)
--   W.mouseMove(x, y, over)            the mouse moves (held or not); over = the frame under it now (optional)
--   W.mouseUp(button)                  let go
W.onReset[#W.onReset + 1] = function() W.held, W.pressed = {}, nil end
W.onEnv[#W.onEnv + 1] = function(env)
	env.IsMouseButtonDown = function(button)
		if button == nil then return next(W.held or {}) ~= nil end
		return (W.held or {})[button] == true
	end
end
function W.mouseDown(f, x, y, button)
	button = button or "LeftButton"
	W.held = W.held or {}
	W.held[button] = true
	W.cursor = {x or W.cursor[1], y or W.cursor[2]}
	W.mouseFocus = f
	W.pressed = f
	local s = f.scripts.OnMouseDown
	if s then W.step(s, f, button) end
end
function W.mouseMove(x, y, over)
	W.cursor = {x, y}
	if over ~= nil then W.mouseFocus = over end
end
function W.mouseUp(button)
	button = button or "LeftButton"
	if W.held then W.held[button] = nil end
	local f = W.pressed
	W.pressed = nil
	if not f then return end
	local s = f.scripts.OnMouseUp
	if s then W.step(s, f, button) end
	if W.mouseFocus == f then f:Click(button) end
end
