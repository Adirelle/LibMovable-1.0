--[[
LibMovable-1.0 - Movable frame library
(c) 2009 Adirelle (adirelle@tagada-team.net)
All rights reserved.
--]]

local MAJOR, MINOR = 'LibMovable-1.0', 28
local lib, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end
oldMinor = oldMinor or 0

-- Localization
L_MENU_ENABLED = "Enabled"
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
L_TIP_SHIFT_RIGHT_CLICK ="Shift+right-click: enable/disable."
L_DISABLED = " (disabled)"
L_IN_COMBAT_LOCKDOWN = " (locked down in combat)"

if GetLocale() == "frFR" then
	L_MENU_ENABLED = "Activé"
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
	L_TIP_SHIFT_RIGHT_CLICK ="Maj+clic droit: activer/désactiver."
	L_DISABLED = " (désactivé)"
	L_IN_COMBAT_LOCKDOWN = " (verrouilé en combat)"
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

-- Poor man's safecall

local function safecall_return(success, ...)
	if success then
		return ...
	else
		geterrorhandler()((...))
	end
end

local function safecall(func, ...)
	if type(func) == "function" then
		return safecall_return(pcall(func, ...))
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

function proto.GetDatabase(overlay)
	return overlay.db
end

function proto.UpdateDatabase(overlay)
	local db, target = overlay:GetDatabase(), overlay.target
	db.scale, db.pointFrom, db.refFrame, db.pointTo, db.xOffset, db.yOffset = GetFrameLayout(target)
	safecall(target.LM10_OnDatabaseUpdated, target)
	if overlay.UpdateDisplay then
		overlay:UpdateDisplay(InCombatLockdown())
	end
end

function proto.PostApplyLayout(overlay)
	return overlay:UpdateDisplay(InCombatLockdown())
end

function proto.ApplyLayout(overlay)
	local db, target, defaults = overlay:GetDatabase(), overlay.target, overlay.defaults
	overlay.dirty = not SetFrameLayout(
		target,
		db.scale or defaults.scale,
		db.pointFrom or defaults.pointFrom,
		db.refFrame or defaults.refFrame,
		db.pointTo or defaults.pointTo,
		db.xOffset or defaults.xOffset,
		db.yOffset or defaults.yOffset
	)
	if overlay.PostApplyLayout then
		overlay:SetScript('OnUpdate', overlay.PostApplyLayout)
	end
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
	local target = overlay.target
	target:SetMovable(true)
	target:StartMoving()
	if lock == "X" then
		overlay.lockedX = select(4, overlay.target:GetPoint())
	elseif lock == "Y" then
		overlay.lockedY = select(5, overlay.target:GetPoint())
	end
	overlay:SetScript('OnUpdate', overlay.MovingUpdater)
	overlay.isMoving = true
	overlay:OnLeave()
	overlay:UpdateDisplay()
	safecall(target.LM10_OnStartedMoving, target)
end

function proto.StopMoving(overlay)
	if not overlay.isMoving or overlay:InCombatLockdown() then return end
	local target = overlay.target
	overlay.lockedX, overlay.lockedY = nil, nil
	overlay.Text:SetText(overlay.label)
	overlay:SetScript('OnUpdate', nil)
	target:StopMovingOrSizing()
	target:SetMovable(false)
	overlay.isMoving = nil
	safecall(target.LM10_OnStoppedMoving, target)
	if overlay:IsMouseOver() then
		overlay:OnEnter()
	end
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
	local db = overlay:GetDatabase()
	for k, v in pairs(overlay.defaults) do
		db[k] = v
	end
	proto.ApplyLayout(overlay)
end

local function GetPointCoord(frame, point)
	local x, y = frame:GetCenter()
	if strmatch(point, "LEFT") then
		x = frame:GetLeft()
	elseif strmatch(point, "RIGHT") then
		x = frame:GetRight()
	end
	if strmatch(point, "TOP") then
		y = frame:GetTop()
	elseif strmatch(point, "BOTTOM") then
		y = frame:GetBottom()
	end
	return x, y
end

-- Guess the connector texture path from the current file path
local connectorTexture = string.match(debugstack(1,1,0), [[^(.+\)LibMovable%-1%.0%.lua]]) .. 'Connector-Texture'

function proto.UpdateDisplay(overlay, inCombat)
	--if not overlay:IsVisible() then return end
	local r, g, b, labelSuffix, alpha = 0, 1, 0, "", 1
	local connector, showConnector = overlay.connector, false
	if inCombat and overlay.protected then
		r, g, b, labelSuffix, alpha = 1, 0, 0, L_IN_COMBAT_LOCKDOWN, 0.4
	elseif not overlay:IsTargetEnabled() then
		r, g, b, labelSuffix = 0.5, 0.5, 0.5, L_DISABLED
	else
		local target = overlay.target
		local parent = target:GetParent()
		local from, refFrame, to = target:GetPoint()
		if refFrame and refFrame ~= parent then
			r, g, b = 0, 0.5, 0
			if not connector then
				connector = overlay:CreateTexture(nil, "OVERLAY")
				connector:SetTexture(connectorTexture)
				overlay.connector = connector
			end
			local cx, cy = overlay:GetCenter()
			local sx, sy = GetPointCoord(overlay, from)
			local ex, ey = GetPointCoord(refFrame, to)
			DrawRouteLine(connector, overlay, sx-cx, sy-cy, ex-cx, ey-cy, 32, "CENTER")
			showConnector = true
		end
	end
	if connector then
		connector:SetShown(showConnector)
	end
	overlay:SetAlpha(alpha)
	overlay:SetBackdropColor(r, g, b, 0.7)
	overlay:SetBackdropBorderColor(r, g, b, 1)
	overlay.Text:SetText(overlay.label..labelSuffix)
end

function proto.CanDisableTarget(overlay)
	return overlay.canDisableTarget
end

function proto.IsTargetEnabled(overlay)
	if overlay.canDisableTarget then
		return safecall(overlay.target.LM10_IsEnabled, overlay.target)
	end
	return true
end

function proto.ToggleTarget(overlay)
	if overlay.canDisableTarget then
		local func = overlay:IsTargetEnabled() and "LM10_Disable" or "LM10_Enable"
		safecall(overlay.target[func], overlay.target)
		overlay:UpdateDisplay(InCombatLockdown())
	end
end

function proto.EnableOverlay(overlay, inCombat)
	if inCombat and overlay.protected then
		overlay:StopMoving()
		overlay:EnableMouse(false)
		overlay:EnableMouseWheel(false)
	else
		overlay:EnableMouse(true)
		overlay:EnableMouseWheel(true)
	end
	overlay:UpdateDisplay(inCombat)
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
	{ text = false, func = function() menuOverlay:ToggleTarget() end, checked = function() return menuOverlay:IsTargetEnabled() end, isNotRadio = true },
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
	menu[2].text = menuOverlay:CanDisableTarget() and L_MENU_ENABLED or false
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
	local db, defaults = overlay:GetDatabase(), overlay.defaults
	if db then
		for k, v in pairs(defaults) do
			if db[k] == v then
				db[k] = nil
			end
		end
	end
end

-- Overlay scripts

function proto.OnEnter(overlay)
	if overlay.isMoving then return end
	GameTooltip_SetDefaultAnchor(GameTooltip, overlay)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(overlay.label)
	GameTooltip:AddLine(L_TIP_CONTROLS, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_DRAG, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_SHIFT_DRAG, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_CTRL_DRAG, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_MOUSEWHEEL, 1, 1, 1)
	GameTooltip:AddLine(L_TIP_RIGHT_CLICK, 1, 1, 1)
	if overlay:CanDisableTarget() then
		GameTooltip:AddLine(L_TIP_SHIFT_RIGHT_CLICK, 1, 1, 1)
	end
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
		if overlay:CanDisableTarget() and IsShiftKeyDown() then
			overlay:ToggleTarget()
		else
			overlay:OpenMenu()
		end
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
	bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tile = true, tileSize = 16,
	edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }
}

local stackTrace, containerAddon = debugstack(1, 1, 0), ...
local libPath = strmatch(stackTrace, '('..gsub(containerAddon, "(%W)", "%%%1")..'.-\\)[Ll]ib[Mm]ovable%-1%.0%.lua')
if libPath then
	overlayBackdrop.edgeFile = 'Interface\\AddOns\\'..libPath..'border'
else
	error("Cannot get library path from stack trace: "..stackTrace)
end

function lib.RegisterMovable(key, target, db, label, anchor)
	if overlaysToBe[target] or overlays[target] then return end

	local protected = target:IsProtected()
	local scale, pointFrom, refFrame, pointTo, xOffset, yOffset = GetFrameLayout(target)
	label = label or target:GetName()
	local GetDatabase
	if db then
		local t = db
		if type(db) == "function" then
			local func = db
			GetDatabase = function() return func(target) end
			t = db(target)
			db = nil
		end
		if t then
			SetFrameLayout(
				target,
				t.scale or scale,
				t.pointFrom or pointFrom,
				t.refFrame or refFrame,
				t.pointTo or pointTo,
				t.xOffset or xOffset,
				t.yOffset or yOffset
			)
		end
	else
		db = {}
	end

	local canDisableTarget =
			type(target.LM10_Enable) == "function"
			and type(target.LM10_Disable) == "function"
			and type(target.LM10_IsEnabled) == "function"

	overlaysToBe[target] = {
		version = MINOR,
		label = label,
		anchor = anchor or target,
		target = target,
		db = db,
		key = key,
		movable = true,
		protected = protected,
		canDisableTarget = canDisableTarget,
		GetDatabase = GetDatabase or proto.GetDatabase,
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
	if type(overlay.anchor) == "function" then
		overlay.anchor = overlay.anchor(target)
	end
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
		if (not key or data.key == key) and data.movable then
			lib.SpawnOverlay(data)
		end
	end
	for target, overlay in lib.IterateOverlays(key) do
		if overlay.movable then
			overlay:Show()
		end
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
	for target, data in pairs(overlaysToBe) do
		if type(data) == "table" and (not key or data.key == key) then
			proto.ApplyLayout(data)
		end
	end
	for target, overlay in lib.IterateOverlays(key) do
		overlay:ApplyLayout()
	end
end

function lib.ResetLayout(key)
	for target, data in pairs(overlaysToBe) do
		if type(data) == "table" and (not key or data.key == key) then
			proto.ResetLayout(data)
		end
	end
	for target, overlay in lib.IterateOverlays(key) do
		overlay:ResetLayout()
	end
end

function lib.SetMovable(key, target, flag, update)
	local overlay = overlaysToBe[target] or overlays[target]
	if overlay then
		flag = not not flag
		if overlay.movable ~= flag then
			overlay.movable = flag
			if not flag and overlay.IsShown and overlay:IsShown() then
				overlay:Hide()
			end
			if update then
				if flag then
					proto.ApplyLayout(overlay)
				else
					local defaults = overlay.defaults
					SetFrameLayout(
						target,
						defaults.scale,
						defaults.pointFrom,
						defaults.refFrame,
						defaults.pointTo,
						defaults.xOffset,
						defaults.yOffset
					)
				end
			end
		end
	end
end

function lib.IsMovable(key, target)
	local overlay = overlaysToBe[target] or overlays[target]
	return overlay and overlay.movable
end

-- Embedding

lib.embeds = lib.embeds or {}
local embeds = lib.embeds

local embeddedMethods = {
	RegisterMovable = "RegisterMovable",
	UpdateMovableLayout = "UpdateLayout",
	ResetMovableLayout = "ResetLayout",
	LockMovables = "Lock",
	UnlockMovables = "Unlock",
	AreMovablesLocked = "IsLocked",
	IterateMovableOverlays = "IterateOverlays",
	SetMovable = "SetMovable",
	IsMovable = "IsMovable",
}

function lib.Embed(target, ...)
	if target == lib then return lib.Embed(...) end
	embeds[target] = true
	for k, v in pairs(embeddedMethods) do
		target[k] = lib[v]
	end
end

function lib:OnEmbedEnable(key)
	for target, data in pairs(overlaysToBe) do
		lib.SetMovable(key, target, true, true)
	end
	for target, overlay in lib.IterateOverlays(key) do
		lib.SetMovable(key, target, true, true)
	end
end

function lib:OnEmbedDisable(key)
	for target, data in pairs(overlaysToBe) do
		lib.SetMovable(key, target, false, true)
	end
	for target, overlay in lib.IterateOverlays(key) do
		lib.SetMovable(key, target, false, true)
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
