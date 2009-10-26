--[[
LibMovable-1.0 - Movable frame library
(c) 2009 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local MAJOR, MINOR = 'LibMovable-1.0', 1
local lib, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
oldMinor = oldMinor or 0

-- Frame layout helpers

local function GetFrameLayout(frame)
	local scale, pointFrom, refFrame, pointTo, xOffset, yOffset = frame:GetScale(), frame:GetPoint()
	if refFrame == frame:GetParent() then
		refFrame = nil
	elseif refFrame then
		refFrame = refFrame:GetName()
		if not refFrame then
			error("Cannot handle a frame positioned relative to an anonymous frame ("..frame:GetName()..")", 3)
		end
	end
	return scale, pointFrom, refFrame, pointTo, xOffset, yOffset
end

local function __SetFrameLayout(frame, scale, pointFrom, refFrame, pointTo, xOffset, yOffset)
	refFrame = refFrame and _G[refFrame] or frame:GetParent()
	frame:ClearAllPoints()
	frame:SetScale(scale)
	frame:SetPoint(pointFrom, refFrame, pointTo, xOffset, yOffset)
end

local function ProcessPendingLayouts()
	for frame, layout in pairs(lib.pendingLayouts) do
		__SetFrameLayout(frame, unpack(layout))
	end
	wipe(lib.pendingLayouts)
end

local function SetFrameLayout(frame, ...)
	if frame:IsProtected() and InCombatLockdown() then
		if not lib.oocFrame then
			lib.pendingLayouts = {}
			lib.oocFrame = CreateFrame("Frame")
			lib.oocFrame:SetScript('OnEvent', ProcessPendingLayouts)
			lib.oocFrame:RegisterEvent('PLAYER_REGEN_ENABLED')
		end
		if not lib.pendingLayouts[frame] then
			lib.pendingLayouts[frame] = { ... }
		else
			local l = lib.pendingLayouts[frame]
			for i = 1, select('#', ...) do
				l[i] = select(i, ...)
			end
		end
	else
		return __SetFrameLayout(frame, ...)
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

function proto.UpdateDatabase(overlay)
	local db, target = overlay.db, overlay.target
	db.scale, db.pointFrom, db.refFrame, db.pointTo, db.xOffset, db.yOffset = GetFrameLayout(target)
end

function proto.ApplyLayout(overlay)
	local db, target = overlay.db, overlay.target
	overlay.dirty = not SetFrameLayout(target, db.scale, db.pointFrom, db.refFrame, db.pointTo, db.xOffset, db.yOffset)
end

function proto.StartMoving(overlay)
	if overlay.isMoving or (overlay.protected and InCombatLockdown()) then return end
	overlay.target:SetMovable(true)
	overlay.target:StartMoving()
	overlay.isMoving = true
end

function proto.StopMoving(overlay)
	if not overlay.isMoving or (overlay.protected and InCombatLockdown()) then return end
	overlay.target:StopMovingOrSizing()
	overlay.target:SetMovable(false)
	overlay.isMoving = nil
	overlay:UpdateDatabase()
end

function proto.ChangeScale(overlay, delta)
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
	GameTooltip:AddLine("Drag this using the left mouse button.", 1, 1, 1)
	GameTooltip:AddLine("Use the mousewheel to change the size.", 1, 1, 1)
	GameTooltip:AddLine("Hold Alt and right click to reset to defaults.", 1, 1, 1)
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
		overlay:StartMoving()
	end
end

function proto.OnMouseUp(overlay, button)
	if button == "LeftButton" then
		overlay:StopMoving()
	elseif button == "RightButton" and IsAltKeyDown() then
		overlay:ResetLayout()
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

	overlaysToBe[target] = function(testKey)
		if (testKey and testKey ~= key) then return end
		local overlay = setmetatable(CreateFrame("Frame", nil, UIParent), lib.meta)
		overlaysToBe[target] = nil
		overlays[target] = overlay

		overlay:SetFrameStrata("HIGH")
		overlay:SetBackdrop(overlayBackdrop)
		overlay:SetBackdropBorderColor(0,0,0,0)
		overlay:SetAllPoints(anchor or target)
		overlay:RegisterEvent("PLAYER_LOGOUT")
		overlay:SetScripts()
		overlay:Hide()

		if label then
			local text = overlay:CreateFontString(nil, "ARTWORK", "GameFontWhite")
			text:SetAllPoints(overlay)
			text:SetJustifyH("CENTER")
			text:SetJustifyV("MIDDLE")
			text:SetText(label)
		end

		overlay.label = label
		overlay.target = target
		overlay.db = db
		overlay.key = key
		overlay.protected = protected
		overlay.defaults = {
			scale = scale,
			pointFrom = pointFrom,
			refFrame = refFrame,
			pointTo = pointTo,
			xOffset = xOffset,
			yOffset = yOffset
		}

		for k, v in pairs(overlay.defaults) do
			if db[k] == nil then
				db[k] = v
			end
		end

		overlay:ApplyLayout()
	end

end

lib.__iterators = lib.__iterators or {}

setmetatable(lib.__iterators, {
	__index = function(iterators, key)
		local iterator = function(overlays, target)
			local nextTarget, nextOverlay
			repeat
				nextTarget, nextOverlay = next(overlays, target)
				if not nextTarget then
					return
				end
			until nextOverlay.key == key
			return nextTarget, nextOverlay
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

function lib.Lock(key)
	for target, overlay in lib.IterateOverlays(key) do
		overlay:Hide()
	end
end

function lib.Unlock(key)
	for target, spawnFunc in pairs(overlaysToBe) do
		spawnFunc(key)
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
	overlay:SetScripts()
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

