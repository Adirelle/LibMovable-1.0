--[[
LibMovable-1.0 - Movable frame library
(c) 2009 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local MAJOR, MINOR = 'LibMovable-1.0', 8
local lib, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
oldMinor = oldMinor or 0

-- Localization
L_MENU_CENTER_X = "Center horizontally"
L_MENU_CENTER_Y = "Center vertically"
L_MENU_RESET = "Reset to default position"
L_MENU_HIDE_THIS = "Hide this moving handle"
L_MENU_HIDE_ALL = "Hide all moving handles"
L_TIP_CONTROLS = "Controls:"
L_TIP_DRAG ="Drag: move."
L_TIP_SHIFT_DRAG = "Shift+drag: move vertically."
L_TIP_CTRL_DRAG = "Control+drag: move horizontally."
L_TIP_MOUSEWHEEL = "Mousewheel: change scale."
L_TIP_RIGHT_CLICK = "Right-click: open menu."

if GetLocale() == "frFR" then
	L_MENU_CENTER_X = "Centrer horizontalement"
	L_MENU_CENTER_Y = "Centrer verticalement"
	L_MENU_RESET = "Réinitialiser la position"
	L_MENU_HIDE_THIS = "Cacher"
	L_MENU_HIDE_ALL = "Tout cacher"
	L_TIP_CONTROLS = "Contrôles :"
	L_TIP_DRAG ="Tirer : déplacer."
	L_TIP_SHIFT_DRAG = "Tirer en pressant Maj : déplacer verticalement."
	L_TIP_CTRL_DRAG = "Tirer en pressant Ctrl : déplacer horizontalement."
	L_TIP_MOUSEWHEEL = "Molette de la souris : changer l'échelle d'affichage."
	L_TIP_RIGHT_CLICK = "Clic droit : ouvrir le menu."
end
		
-- Frame layout helpers

local function GetFrameLayout(frame)
	local scale, pointFrom, refFrame, pointTo, xOffset, yOffset = frame:GetScale(), frame:GetPoint()
	if refFrame == frame:GetParent() or refFrame == nil then
		refFrame = frame:GetParent():GetName() or "__parent"
	elseif refFrame then
		refFrame = refFrame:GetName()
		if not refFrame then
			error("Cannot handle a frame positioned relative to an anonymous frame ("..frame:GetName()..")", 3)
		end
	end
	return scale, pointFrom, refFrame, pointTo, xOffset, yOffset
end

local function __SetFrameLayout(frame, scale, pointFrom, refFrame, pointTo, xOffset, yOffset)
	if refFrame == "__parent" or not refFrame then
		refFrame = frame:GetParent()
	else
		refFrame = _G[refFrame]
	end
	frame:ClearAllPoints()
	frame:SetScale(scale)
	frame:SetPoint(pointFrom, refFrame, pointTo, xOffset, yOffset)
end

function lib.ProcessPendingLayouts()
	for frame, t in pairs(lib.pendingLayouts) do
		if frame:CanChangeProtectedState() then
			__SetFrameLayout(frame, t.scale, t.pointFrom, t.refFrame, t.pointTo, t.xOffset, t.yOffset)
			lib.pendingLayouts[frame] = nil
		end
	end
end

local function SetFrameLayout(frame, scale, pointFrom, refFrame, pointTo, xOffset, yOffset)
	if not frame:CanChangeProtectedState() then
		if not lib.oocFrame then
			local frame = CreateFrame("Frame")
			frame:SetScript('OnEvent', function() return lib.ProcessPendingLayouts() end)
			frame:RegisterEvent('PLAYER_REGEN_ENABLED')
			lib.pendingLayouts = {}
			lib.oocFrame = frame
		end
		local t = lib.pendingLayouts[frame] or {}
		t.scale, t.pointFrom, t.refFrame, t.pointTo, t.xOffset, t.yOffset = scale, pointFrom, refFrame, pointTo, xOffset, yOffset
		lib.pendingLayouts[frame] = t
	else
		return __SetFrameLayout(frame, scale, pointFrom, refFrame, pointTo, xOffset, yOffset)
	end
end

-- Metatable stuff

lib.frameMeta = lib.frameMeta or { __index = CreateFrame("Frame") }
lib.proto = lib.proto or {}
lib.meta = lib.meta or {}

lib.proto = setmetatable(lib.proto, lib.frameMeta)
lib.meta.__index = lib.proto

-- Overlay methods

local proto = lib.proto
wipe(proto)

function proto.InCombatLockdown(overlay)
	return not overlay.target:CanChangeProtectedState()
end

function proto.UpgradeOverlay(overlay)
	if (overlay.version or 0) >= MINOR then return end
	overlay:SetScripts()
	overlay.version = MINOR
end

function proto.UpdateDatabase(overlay)
	local db, target = overlay.db, overlay.target
	db.scale, db.pointFrom, db.refFrame, db.pointTo, db.xOffset, db.yOffset = GetFrameLayout(target)
end

function proto.ApplyLayout(overlay)
	local db, target = overlay.db, overlay.target
	overlay.dirty = not SetFrameLayout(target, db.scale, db.pointFrom, db.refFrame, db.pointTo, db.xOffset, db.yOffset)
end

function proto.MovingUpdater(overlay)
	local lockedX, lockedY = overlay.lockedX, overlay.lockedY
	if lockedX or lockedY then
		local from, ref, to, x, y = overlay.target:GetPoint()
		overlay.target:SetPoint(from, ref, to, lockedX or x, lockedY or y)
	end
	overlay.Text:SetFormattedText("%s (X:%d, Y:%d)", overlay.label, overlay.target:GetCenter())
end

function proto.StartMoving(overlay, lock)
	if overlay.isMoving or overlay:InCombatLockdown() then return end
	overlay.target:SetMovable(true)
	overlay.target:StartMoving()
	if lock == "X" then
		overlay.lockedX = select(4, overlay.target:GetPoint())
	elseif lock == "Y" then
		overlay.lockedY = select(5, overlay.target:GetPoint())
	end
	overlay:SetScript('OnUpdate', overlay.MovingUpdater)
	overlay.isMoving = true
end

function proto.StopMoving(overlay)
	if not overlay.isMoving or overlay:InCombatLockdown() then return end
	overlay.lockedX, overlay.lockedY = nil, nil
	overlay.Text:SetText(overlay.label)
	overlay:SetScript('OnUpdate', nil)
	overlay.target:StopMovingOrSizing()
	overlay.target:SetMovable(false)
	overlay.isMoving = nil
	overlay:UpdateDatabase()
end

function proto.ChangeScale(overlay, delta)
	if overlay:InCombatLockdown() then return end
	local target = overlay.target
	local oldScale, from, frame, to, oldX, oldY = target:GetScale(), target:GetPoint()
	local newScale = math.max(math.min(oldScale + 0.1 * delta, 3.0), 0.2)
	if oldScale ~= newScale then
		local newX, newY = oldX / newScale * oldScale, oldY / newScale * oldScale
		target:SetScale(newScale)
		target:SetPoint(from, frame, to, newX, newY)
		overlay:UpdateDatabase()
	end
end

function proto.MoveToCenter(overlay, centerX, centerY)
	if overlay:InCombatLockdown() then return end
	local target = overlay.target
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local scale, cx, cy = target:GetEffectiveScale() / UIParent:GetEffectiveScale(), target:GetCenter()
	cx, cy = cx * scale, cy * scale
	if centerX then cx = screenWidth / 2 end
	if centerY then cy = screenHeight / 2 end
	local point = ""
	if cy < screenHeight / 3 then
		point, cy = "BOTTOM", cy - target:GetHeight() / 2
	elseif cy > screenHeight * 2 / 3 then
		point, cy = "TOP", cy + target:GetHeight() / 2 - screenHeight
	else
		cy = cy - screenHeight / 2 
	end
	if cx < screenWidth / 3 then
		point, cx = point .. "LEFT", cx - target:GetWidth() / 2
	elseif cy > screenWidth * 2 / 3 then
		point, cx = point .. "RIGHT", cx + target:GetWidth() / 2 - screenWidth
	else
		cx = cx - screenWidth / 2
	end
	if point == "" then point = "CENTER" end
	target:ClearAllPoints()
	target:SetPoint(point, UIParent, point, cx / scale, cy / scale)
	overlay:UpdateDatabase()
end

function proto.ResetLayout(overlay)
	for k, v in pairs(overlay.defaults) do
		overlay.db[k] = v
	end
	overlay:ApplyLayout()
end

function proto.EnableOverlay(overlay, inCombat)
	if inCombat and overlay.protected then
		overlay:StopMoving()
		overlay:SetBackdropColor(1, 0, 0, 0.4)
		overlay:EnableMouse(false)
		overlay:EnableMouseWheel(false)
	else
		overlay:SetBackdropColor(0, 1, 0, 1)
		overlay:EnableMouse(true)
		overlay:EnableMouseWheel(true)
	end
end

function proto.SetScripts(overlay)
	for name, handler in pairs(proto) do
		if name:match('^On') then
			overlay:SetScript(name, handler)
		end
	end
end

-- Menu definition and method

local menuOverlay
local menu = {
	{ isTitle = true, notCheckable = true },
	{ text = L_MENU_CENTER_X, func = function() menuOverlay:MoveToCenter(true, false) end, notCheckable = true },
	{ text = L_MENU_CENTER_Y, func = function() menuOverlay:MoveToCenter(false, true) end, notCheckable = true },
	{	text = L_MENU_RESET, func = function() menuOverlay:ResetLayout() end, notCheckable = true },
	{ text = L_MENU_HIDE_THIS, func = function() menuOverlay:Hide() end, notCheckable = true },
	{ text = L_MENU_HIDE_ALL, func = function() lib.Lock() end, notCheckable = true },
	{ text = CANCEL, notCheckable = true }
}

function proto.OpenMenu(overlay)
	lib.menuFrame = lib.menuFrame or CreateFrame("Frame", "LibMovable10MenuDropDown", UIParent, "UIDropDownMenuTemplate")
	menuOverlay = overlay
	menu[1].text = menuOverlay.label
	EasyMenu(menu, lib.menuFrame, "cursor", 0, 0, "MENU")
end

-- Overlay event handlers

function proto.PLAYER_REGEN_ENABLED(overlay)
	overlay:EnableOverlay(false)
	if overlay.dirty then
		overlay:ApplyLayout()
	end
end

function proto.PLAYER_REGEN_DISABLED(overlay)
	overlay:EnableOverlay(true)
end

function proto.PLAYER_LOGOUT(overlay)
	local db, defaults = overlay.db, overlay.defaults
	for k, v in pairs(defaults) do
		if db[k] == v then
			db[k] = nil
		end
	end
end

-- Overlay scripts

function proto.OnEnter(overlay)
	GameTooltip_SetDefaultAnchor(GameTooltip, overlay)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(overlay.label)
	GameTooltip:AddLine(L_TIP_CONTROLS, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_DRAG, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_SHIFT_DRAG, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_CTRL_DRAG, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_MOUSEWHEEL, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_RIGHT_CLICK, 1, 1, 1)
	GameTooltip:Show()
end

function proto.OnLeave(overlay)
	if GameTooltip:GetOwner() == overlay then
		GameTooltip:Hide()
	end
end

function proto.OnShow(overlay)
	if overlay.protected then
		overlay:RegisterEvent("PLAYER_REGEN_DISABLED")
		overlay:RegisterEvent("PLAYER_REGEN_ENABLED")
	end
	overlay:EnableOverlay(InCombatLockdown())
end

function proto.OnHide(overlay)
	overlay:StopMoving()
	if overlay.protected then
		overlay:UnregisterEvent("PLAYER_REGEN_DISABLED")
		overlay:UnregisterEvent("PLAYER_REGEN_ENABLED")
	end
end

function proto.OnEvent(overlay, event, ...)
	return overlay[event](overlay, event, ...)
end

function proto.OnMouseDown(overlay, button)
	if button == "LeftButton" then
		overlay:StartMoving((IsShiftKeyDown() and "X") or (IsControlKeyDown() and "Y"))
	end
end

function proto.OnMouseUp(overlay, button)
	if button == "LeftButton" then
		overlay:StopMoving()
	elseif button == "RightButton" then
		overlay:StopMoving()
		overlay:OpenMenu()
	end
end

function proto.OnMouseWheel(overlay, delta)
	overlay:ChangeScale(delta)
end

-- Public API

lib.overlays = lib.overlays or {}
lib.overlaysToBe = lib.overlaysToBe or {}
local overlays = lib.overlays
local overlaysToBe = lib.overlaysToBe

local overlayBackdrop = {
	bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 16
}

function lib.RegisterMovable(key, target, db, label, anchor)
	if overlaysToBe[target] or overlays[target] then return end

	local protected = target:IsProtected()
	local scale, pointFrom, refFrame, pointTo, xOffset, yOffset = GetFrameLayout(target)
	label = label or target:GetName()
	if db then
		SetFrameLayout(
			target,
			db.scale or scale,
			db.pointFrom or pointFrom,
			db.refFrame or refFrame,
			db.pointTo or pointTo,
			db.xOffset or xOffset,
			db.yOffset or yOffset
		)
	else
		db = {}
	end

	overlaysToBe[target] = {
		version = MINOR,
		label = label,
		anchor = anchor or target,
		target = target,
		db = db,
		key = key,
		protected = protected,
		defaults = {
			scale = scale,
			pointFrom = pointFrom,
			refFrame = refFrame,
			pointTo = pointTo,
			xOffset = xOffset,
			yOffset = yOffset
		}
	}
end

function lib.SpawnOverlay(data)
	local target = data.target

	local overlay = setmetatable(CreateFrame("Frame", nil, UIParent), lib.meta)	
	for k, v in pairs(data) do
		overlay[k] = v
	end	
	overlaysToBe[target] = nil
	overlays[target] = overlay

	overlay:SetFrameStrata("DIALOG")
	overlay:SetBackdrop(overlayBackdrop)
	overlay:SetBackdropBorderColor(0,0,0,0)
	overlay:SetAllPoints(overlay.anchor)
	overlay:RegisterEvent("PLAYER_LOGOUT")
	overlay:SetScripts()
	overlay:Hide()

	local text = overlay:CreateFontString(nil, "ARTWORK", "GameFontWhite")
	text:SetAllPoints(overlay)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetText(overlay.label)
	text:SetShadowColor(0,0,0,1)
	text:SetShadowOffset(1, -1)
	overlay.Text = text

	for k, v in pairs(overlay.defaults) do
		if overlay.db[k] == nil then
			overlay.db[k] = v
		end
	end
	
	-- Upgrade overlay at spawn time if the data has been created with previous versions
	if overlay.version < MINOR then
		overlay:UpgradeOverlay()
	end
end

-- Overlay iterator

lib.__iterators = lib.__iterators or {}

setmetatable(lib.__iterators, {
	__index = function(iterators, key)
		local iterator = function(overlays, target)
			local overlay
			repeat
				target, overlay = next(overlays, target)
				if not target then
					return
				end
			until overlay.key == key
			return target, overlay
		end
		iterators[key] = iterator
		return iterator
	end,
})

function lib.IterateOverlays(key)
	if key then
		return lib.__iterators[key], overlays
	else
		return next, overlays
	end
end

-- (Un)locking related methods

function lib.Lock(key)
	for target, overlay in lib.IterateOverlays(key) do
		overlay:Hide()
	end
end

function lib.Unlock(key)
	for target, data in pairs(overlaysToBe) do
		if type(data) == "function" then
			data(key)
			if overlays[target] then
				overlays[target]:UpgradeOverlay()
			end
		elseif not key or data.key == key then
			lib.SpawnOverlay(data)
		end
	end
	for target, overlay in lib.IterateOverlays(key) do
		overlay:Show()
	end
end

function lib.IsLocked(key)
	for target, overlay in lib.IterateOverlays(key) do
		if overlay:IsShown() then
			return false
		end
	end
	return true
end

function lib.UpdateLayout(key)
	for target, overlay in lib.IterateOverlays(key) do
		overlay:ApplyLayout()
	end
end

-- Embedding

lib.embeds = lib.embeds or {}
local embeds = lib.embeds

local embeddedMethods = {
	RegisterMovable = "RegisterMovable",
	UpdateMovaleLayout = "UpdateLayout",
	LockMovables = "Lock",
	UnlockMovables = "Unlock",
	AreMovablesLocked = "IsLocked",
	IterateMovableOverlays = "IterateOverlays",
}

function lib.Embed(target)
	embeds[target] = true
	for k, v in pairs(embeddedMethods) do
		target[k] = lib[v]
	end
end

-- Upgrading embeds and overlays from previous versions

for target in pairs(embeds) do
	lib.Embed(target)
end

for target, overlay in pairs(overlays) do
	overlay:UpgradeOverlay()
end

-- ConfigMode support

CONFIGMODE_CALLBACKS = CONFIGMODE_CALLBACKS or {}
CONFIGMODE_CALLBACKS['Movable Frames'] = function(action)
	if action == "ON" then
		lib.Unlock()
	elseif action == "OFF" then
		lib.Lock()
	end
end

