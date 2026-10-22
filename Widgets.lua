--[[-----------------------------------------------------------------------------
GuildInfo - Widgets
AceGUI-Widget "GuildInfoRow": eine Tabellenzeile mit mehreren Spalten
(FontStrings), Hover-Highlight, Auswahlmarkierung, Online-Indikator.
Wird sowohl für die Kopfzeile als auch für die Datenzeilen verwendet.

AceGUI-Widget "GuildInfoTable": Mitgliederliste mit fester Kopfzeile,
vertikalem Scrollen und horizontalem Scrollbalken, wenn die Spalten
breiter sind als das Fenster.
-------------------------------------------------------------------------------]]
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI then return end

local pairs, ipairs, max, min = pairs, ipairs, math.max, math.min
local CreateFrame, UIParent, GetCursorPosition = CreateFrame, UIParent, GetCursorPosition

local ROW_HEIGHT   = 18
local CELL_PADDING = 4
local INDENT_WIDTH = 16
local DOT_WIDTH    = 12

do -- GuildInfoRow
local Type, Version = "GuildInfoRow", 2
if (AceGUI:GetWidgetVersion(Type) or 0) < Version then

-------------------------------------------------------------------------------
-- Scripts
-------------------------------------------------------------------------------
local function Row_OnEnter(frame)
	local self = frame.obj
	if not self.isHeader then
		self.highlight:Show()
	end
	self:Fire("OnEnter")
end

local function Row_OnLeave(frame)
	local self = frame.obj
	if not self.selected then
		self.highlight:Hide()
	end
	self:Fire("OnLeave")
end

local function Row_OnClick(frame, button)
	local self = frame.obj
	-- Spalte unter dem Mauszeiger ermitteln
	local x = GetCursorPosition()
	local scale = frame:GetEffectiveScale()
	local left = frame:GetLeft()
	local col
	if left and scale and scale > 0 then
		local rel = x / scale - left
		for i, c in ipairs(self.columns or {}) do
			local cx, cw = self.cellPos[i] or 0, self.cellWidth[i] or 0
			if rel >= cx and rel <= cx + cw then col = i; break end
		end
	end
	self:Fire("OnClick", button, col)
	if col then
		self:Fire("OnColumnClick", col, button)
	end
	AceGUI:ClearFocus()
end

-- Mausrad bubblet in WoW nicht: an den nächsten Scroll-Parent weiterreichen.
local function Row_OnMouseWheel(frame, delta)
	local parent = frame:GetParent()
	while parent do
		local script = parent.GetScript and parent:GetScript("OnMouseWheel")
		if script then
			script(parent, delta)
			return
		end
		parent = parent:GetParent()
	end
end

-------------------------------------------------------------------------------
-- Layout-Berechnung
-------------------------------------------------------------------------------
local function Relayout(self)
	local columns = self.columns
	if not columns then return end
	local frame = self.frame
	local total = frame.width or frame:GetWidth() or 0
	local indent = (self.indent or 0) * INDENT_WIDTH
	local dotWidth = self.showDot and DOT_WIDTH or 0
	local available = total - indent - dotWidth

	-- Fixe Breiten summieren, Rest an die Flex-Spalte(n).
	-- Flex-Spalten nutzen c.width als Mindestbreite.
	local fixed, flexCount, flexMin = 0, 0, 0
	for _, c in ipairs(columns) do
		if c.flex then
			flexCount = flexCount + 1
			flexMin = flexMin + (c.width or 40)
		else
			fixed = fixed + (c.width or 80)
		end
	end
	local flexWidth = 0
	if flexCount > 0 then
		flexWidth = max(flexMin / flexCount, (available - fixed) / flexCount)
	end

	local x = indent + dotWidth
	for i, c in ipairs(columns) do
		local w = c.flex and flexWidth or (c.width or 80)
		local fs = self.cells[i]
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", frame, "LEFT", x + CELL_PADDING, 0)
		fs:SetWidth(max(1, w - CELL_PADDING * 2))
		fs:SetJustifyH(c.justify or "LEFT")
		fs:Show()
		self.cellPos[i] = x
		self.cellWidth[i] = w
		x = x + w
	end
	for i = #columns + 1, #self.cells do
		self.cells[i]:Hide()
	end

	self.dot:ClearAllPoints()
	self.dot:SetPoint("LEFT", frame, "LEFT", indent + 2, 0)
end

-------------------------------------------------------------------------------
-- Methoden
-------------------------------------------------------------------------------
local methods = {
	["OnAcquire"] = function(self)
		self:SetHeight(ROW_HEIGHT)
		self:SetFullWidth(true)
		self.columns = nil
		self.indent = 0
		self.selected = false
		self.isHeader = false
		self.showDot = false
		self.highlight:Hide()
		self.stripe:Hide()
		self.dot:Hide()
		self.frame:EnableMouse(true)
		for _, fs in ipairs(self.cells) do
			fs:SetText("")
			fs:SetFontObject(GameFontHighlightSmall)
			fs:SetTextColor(1, 1, 1)
			fs:Hide()
		end
	end,

	["OnRelease"] = function(self)
		self.frame:ClearAllPoints()
		self.frame:Hide()
	end,

	["OnWidthSet"] = function(self, width)
		Relayout(self)
	end,

	-- columns = { { key="name", width=120 }, { key="rank", flex=true }, ... }
	["SetColumns"] = function(self, columns)
		self.columns = columns
		-- Fehlende FontStrings anlegen
		for i = #self.cells + 1, #columns do
			local fs = self.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetJustifyV("MIDDLE")
			fs:SetHeight(ROW_HEIGHT)
			fs:SetNonSpaceWrap(false)
			self.cells[i] = fs
		end
		Relayout(self)
	end,

	["SetCell"] = function(self, index, text, r, g, b)
		local fs = self.cells[index]
		if not fs then return end
		fs:SetText(text or "")
		if r then
			fs:SetTextColor(r, g, b)
		else
			fs:SetTextColor(1, 1, 1)
		end
	end,

	["SetCellFont"] = function(self, index, fontObject)
		local fs = self.cells[index]
		if fs then fs:SetFontObject(fontObject or GameFontHighlightSmall) end
	end,

	["SetHeader"] = function(self, isHeader)
		self.isHeader = isHeader
		if isHeader then
			self.stripe:Show()
			self.stripe:SetTexture(0.25, 0.25, 0.25, 0.6)
			for _, fs in ipairs(self.cells) do
				fs:SetFontObject(GameFontNormalSmall)
			end
			self:SetHeight(ROW_HEIGHT + 2)
		end
	end,

	["SetStripe"] = function(self, visible)
		if visible then
			self.stripe:SetTexture(1, 1, 1, 0.04)
			self.stripe:Show()
		else
			self.stripe:Hide()
		end
	end,

	["SetSelected"] = function(self, selected)
		self.selected = selected
		if selected then
			self.highlight:SetVertexColor(1, 0.82, 0, 0.35)
			self.highlight:Show()
		else
			self.highlight:SetVertexColor(1, 1, 1, 0.25)
			self.highlight:Hide()
		end
	end,

	["SetIndent"] = function(self, level)
		self.indent = level or 0
		Relayout(self)
	end,

	-- Online-Punkt: nil = ausblenden, true = grün, false = grau
	["SetOnlineDot"] = function(self, state)
		if state == nil then
			self.showDot = false
			self.dot:Hide()
		else
			self.showDot = true
			self.dot:Show()
			if state then
				self.dot:SetVertexColor(0.2, 1, 0.2, 1)
			else
				self.dot:SetVertexColor(0.5, 0.5, 0.5, 0.6)
			end
		end
		Relayout(self)
	end,

	["SetAlpha"] = function(self, alpha)
		self.frame:SetAlpha(alpha or 1)
	end,

	["SetDisabled"] = function(self, disabled)
		self.frame:EnableMouse(not disabled)
	end,
}

-------------------------------------------------------------------------------
-- Konstruktor
-------------------------------------------------------------------------------
local function Constructor()
	local frame = CreateFrame("Button", nil, UIParent)
	frame:Hide()
	frame:SetHeight(ROW_HEIGHT)
	frame:EnableMouse(true)
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	frame:EnableMouseWheel(true)
	frame:SetScript("OnEnter", Row_OnEnter)
	frame:SetScript("OnLeave", Row_OnLeave)
	frame:SetScript("OnClick", Row_OnClick)
	frame:SetScript("OnMouseWheel", Row_OnMouseWheel)

	local stripe = frame:CreateTexture(nil, "BACKGROUND")
	stripe:SetAllPoints(frame)
	stripe:SetTexture(1, 1, 1, 0.04)
	stripe:Hide()

	local highlight = frame:CreateTexture(nil, "BORDER")
	highlight:SetAllPoints(frame)
	highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	highlight:SetBlendMode("ADD")
	highlight:SetVertexColor(1, 1, 1, 0.25)
	highlight:Hide()

	local dot = frame:CreateTexture(nil, "ARTWORK")
	dot:SetWidth(8)
	dot:SetHeight(8)
	dot:SetTexture("Interface\\Buttons\\WHITE8X8")
	dot:Hide()

	local widget = {
		frame     = frame,
		stripe    = stripe,
		highlight = highlight,
		dot       = dot,
		cells     = {},
		cellPos   = {},
		cellWidth = {},
		type      = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
end -- version check
end -- GuildInfoRow

-------------------------------------------------------------------------------
-- GuildInfoTable: Kopfzeile + Zeilen, vertikal und horizontal scrollbar
-------------------------------------------------------------------------------
do -- GuildInfoTable
local Type, Version = "GuildInfoTable", 2
if (AceGUI:GetWidgetVersion(Type) or 0) < Version then

local PlaySound, IsShiftKeyDown = PlaySound, IsShiftKeyDown
local _G = _G

local VBAR_WIDTH   = 20
local HBAR_HEIGHT  = 16
local HEADER_HEIGHT = ROW_HEIGHT + 2
local WHEEL_V      = 36
local WHEEL_H      = 48

local function GetMinContentWidth(columns)
	local w = DOT_WIDTH
	if not columns then return w + 80 end
	for _, c in ipairs(columns) do
		w = w + (c.width or 80)
	end
	return w
end

local function FixScrollOnUpdate(frame)
	frame:SetScript("OnUpdate", nil)
	frame.obj:FixScroll()
end

local function RequestFixScroll(self)
	self.frame:SetScript("OnUpdate", FixScrollOnUpdate)
end

local function ApplyBarValue(bar, value)
	local vmin, vmax = bar:GetMinMaxValues()
	bar:SetValue(max(vmin, min(vmax, value)))
end

local function OnVScroll(bar, value)
	local self = bar.obj
	if not self or self.silent then return end
	self.bodyScroll:SetVerticalScroll(value)
	local status = self.status or self.localstatus
	status.voffset = value
end

local function OnHScroll(bar, value)
	local self = bar.obj
	if not self or self.silent then return end
	self.headerScroll:SetHorizontalScroll(value)
	self.bodyScroll:SetHorizontalScroll(value)
	local status = self.status or self.localstatus
	status.hoffset = value
end

local function OnMouseWheel(frame, delta)
	local self = frame.obj
	if not self then return end
	if (IsShiftKeyDown() and self.hBarShown) or (self.hBarShown and not self.vBarShown) then
		ApplyBarValue(self.hBar, self.hBar:GetValue() - delta * WHEEL_H)
	elseif self.vBarShown then
		ApplyBarValue(self.vBar, self.vBar:GetValue() - delta * WHEEL_V)
	end
end

local function EnsureHeader(self)
	if self.header then return self.header end
	local header = AceGUI:Create("GuildInfoRow")
	header:SetHeader(true)
	header:SetOnlineDot(false)
	header.dot:Hide()
	header.frame:SetParent(self.headerContent)
	header.frame:ClearAllPoints()
	header.frame:SetAllPoints(self.headerContent)
	header.frame:Show()
	if self.columns then
		header:SetColumns(self.columns)
	end
	self.header = header
	return header
end

local methods = {
	["OnAcquire"] = function(self)
		self.localstatus = { voffset = 0, hoffset = 0 }
		self.status = nil
		self.columns = nil
		self.vBarShown = false
		self.hBarShown = false
		self.vBar:Hide()
		self.hBar:Hide()
		self.headerScroll:SetHorizontalScroll(0)
		self.bodyScroll:SetHorizontalScroll(0)
		self.bodyScroll:SetVerticalScroll(0)
		self.content:SetWidth(1)
		self.content:SetHeight(1)
		self.content.width = 1
		self.content.height = 1
		self.headerContent:SetWidth(1)
		self.headerContent:SetHeight(HEADER_HEIGHT)
		EnsureHeader(self)
	end,

	["OnRelease"] = function(self)
		if self.header then
			AceGUI:Release(self.header)
			self.header = nil
		end
		self.status = nil
		self.columns = nil
		self.vBarShown = nil
		self.hBarShown = nil
		self.frame:SetScript("OnUpdate", nil)
		self.headerScroll:SetHorizontalScroll(0)
		self.bodyScroll:SetHorizontalScroll(0)
		self.bodyScroll:SetVerticalScroll(0)
		self.vBar:Hide()
		self.hBar:Hide()
	end,

	["OnWidthSet"] = function(self, width)
		width = width or 0
		local minW = GetMinContentWidth(self.columns)
		local viewW = width - (self.vBarShown and VBAR_WIDTH or 0)
		if viewW < 1 then viewW = 1 end
		self.content.width = max(minW, viewW)
		RequestFixScroll(self)
	end,

	["OnHeightSet"] = function(self)
		RequestFixScroll(self)
	end,

	["LayoutFinished"] = function(self, width, height)
		height = height or 0
		self.content:SetHeight(height)
		self.content.height = height
		if not self.updateLock then
			self:FixScroll()
		end
	end,

	["SetStatusTable"] = function(self, status)
		assert(type(status) == "table")
		self.status = status
		if not status.voffset then status.voffset = 0 end
		if not status.hoffset then status.hoffset = 0 end
	end,

	["SetColumns"] = function(self, columns)
		self.columns = columns
		EnsureHeader(self):SetColumns(columns)
		RequestFixScroll(self)
	end,

	["GetHeader"] = function(self)
		return EnsureHeader(self)
	end,

	["FixScroll"] = function(self)
		if self.updateLock then return end
		self.updateLock = true

		local frameW = self.frame:GetWidth() or 0
		local frameH = self.frame:GetHeight() or 0
		if frameW < 1 or frameH < 1 then
			self.updateLock = nil
			return
		end

		local headerH = HEADER_HEIGHT
		local minW = GetMinContentWidth(self.columns)
		local contentH = self.content.height or self.content:GetHeight() or 0

		local vShown, hShown = false, false
		for _ = 1, 3 do
			local viewW = frameW - (vShown and VBAR_WIDTH or 0)
			local viewH = frameH - headerH - (hShown and HBAR_HEIGHT or 0)
			if viewW < 1 then viewW = 1 end
			if viewH < 1 then viewH = 1 end
			local contentW = max(minW, viewW)
			local needH = contentW > viewW + 0.5
			local needV = contentH > viewH + 0.5
			if needH == hShown and needV == vShown then break end
			hShown, vShown = needH, needV
		end

		local viewW = frameW - (vShown and VBAR_WIDTH or 0)
		local viewH = frameH - headerH - (hShown and HBAR_HEIGHT or 0)
		if viewW < 1 then viewW = 1 end
		if viewH < 1 then viewH = 1 end
		local contentW = max(minW, viewW)

		self.headerScroll:ClearAllPoints()
		self.headerScroll:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
		self.headerScroll:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", vShown and -VBAR_WIDTH or 0, 0)
		self.headerScroll:SetHeight(headerH)

		self.bodyScroll:ClearAllPoints()
		self.bodyScroll:SetPoint("TOPLEFT", self.headerScroll, "BOTTOMLEFT", 0, 0)
		self.bodyScroll:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT",
			vShown and -VBAR_WIDTH or 0, hShown and HBAR_HEIGHT or 0)

		if vShown then
			self.vBar:Show()
		else
			self.vBar:Hide()
		end
		if hShown then
			self.hBar:ClearAllPoints()
			self.hBar:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
			self.hBar:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", vShown and -VBAR_WIDTH or 0, 0)
			self.hBar:Show()
		else
			self.hBar:Hide()
		end
		self.vBarShown, self.hBarShown = vShown, hShown

		local widthChanged = (self.content.width or 0) ~= contentW
		self:PauseLayout()
		self.headerContent:SetWidth(contentW)
		self.headerContent:SetHeight(headerH)
		self.content:SetWidth(contentW)
		self.content.width = contentW
		if self.header then
			self.header:SetWidth(contentW)
		end
		self:ResumeLayout()

		local maxH = max(0, contentW - viewW)
		local maxV = max(0, contentH - viewH)
		local status = self.status or self.localstatus
		local hOff = status.hoffset or 0
		local vOff = status.voffset or 0
		if hOff > maxH then hOff = maxH end
		if vOff > maxV then vOff = maxV end
		if hOff < 0 then hOff = 0 end
		if vOff < 0 then vOff = 0 end
		status.hoffset, status.voffset = hOff, vOff

		self.silent = true
		self.hBar:SetMinMaxValues(0, maxH > 0 and maxH or 1)
		self.hBar:SetValue(hOff)
		self.vBar:SetMinMaxValues(0, maxV > 0 and maxV or 1)
		self.vBar:SetValue(vOff)
		self.headerScroll:SetScrollChild(self.headerContent)
		self.bodyScroll:SetScrollChild(self.content)
		self.headerScroll:SetHorizontalScroll(hOff)
		self.bodyScroll:SetHorizontalScroll(hOff)
		self.bodyScroll:SetVerticalScroll(vOff)
		self.silent = nil

		if widthChanged then
			self:DoLayout()
		end

		self.updateLock = nil
	end,
}

local function Constructor()
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:Hide()
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", OnMouseWheel)

	local num = AceGUI:GetNextWidgetNum(Type)

	local headerScroll = CreateFrame("ScrollFrame", nil, frame)
	headerScroll:SetHeight(HEADER_HEIGHT)
	headerScroll:EnableMouseWheel(true)
	headerScroll:SetScript("OnMouseWheel", OnMouseWheel)

	local headerContent = CreateFrame("Frame", nil, headerScroll)
	headerContent:SetWidth(1)
	headerContent:SetHeight(HEADER_HEIGHT)
	headerScroll:SetScrollChild(headerContent)

	local bodyScroll = CreateFrame("ScrollFrame", nil, frame)
	bodyScroll:EnableMouseWheel(true)
	bodyScroll:SetScript("OnMouseWheel", OnMouseWheel)

	local content = CreateFrame("Frame", nil, bodyScroll)
	content:SetWidth(1)
	content:SetHeight(1)
	bodyScroll:SetScrollChild(content)

	-- Parent muss der ScrollFrame sein: Das XML-Skript von
	-- UIPanelScrollBarTemplate ruft GetParent():SetVerticalScroll() auf.
	local vBar = CreateFrame("Slider", "GuildInfoTableVScroll" .. num, bodyScroll, "UIPanelScrollBarTemplate")
	vBar:SetPoint("TOPLEFT", bodyScroll, "TOPRIGHT", 4, -16)
	vBar:SetPoint("BOTTOMLEFT", bodyScroll, "BOTTOMRIGHT", 4, 16)
	vBar:SetWidth(16)
	vBar:Hide()
	vBar:SetMinMaxValues(0, 1)
	vBar:SetValueStep(1)
	vBar:SetValue(0)
	-- Eigenes Skript erst nach SetValue, sonst feuert das XML-Skript
	-- zusätzlich. Parent ist jetzt der ScrollFrame, daher ungefährlich.
	vBar:SetScript("OnValueChanged", OnVScroll)

	local vbg = vBar:CreateTexture(nil, "BACKGROUND")
	vbg:SetAllPoints(vBar)
	vbg:SetTexture(0, 0, 0, 0.4)

	local up = _G[vBar:GetName() .. "ScrollUpButton"]
	local down = _G[vBar:GetName() .. "ScrollDownButton"]
	if up then
		up:SetScript("OnClick", function()
			ApplyBarValue(vBar, vBar:GetValue() - WHEEL_V)
			PlaySound("UChatScrollButton")
		end)
	end
	if down then
		down:SetScript("OnClick", function()
			ApplyBarValue(vBar, vBar:GetValue() + WHEEL_V)
			PlaySound("UChatScrollButton")
		end)
	end

	local hBar = CreateFrame("Slider", "GuildInfoTableHScroll" .. num, frame)
	hBar:SetOrientation("HORIZONTAL")
	hBar:SetHeight(HBAR_HEIGHT)
	hBar:SetMinMaxValues(0, 1)
	hBar:SetValueStep(1)
	hBar:SetValue(0)
	hBar:Hide()
	hBar:EnableMouseWheel(true)
	hBar:SetScript("OnValueChanged", OnHScroll)
	hBar:SetScript("OnMouseWheel", OnMouseWheel)
	hBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	local thumb = hBar:GetThumbTexture()
	if thumb then
		thumb:SetWidth(24)
		thumb:SetHeight(16)
	end

	local hbg = hBar:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints(hBar)
	hbg:SetTexture(0, 0, 0, 0.4)

	local widget = {
		localstatus   = { voffset = 0, hoffset = 0 },
		frame         = frame,
		content       = content,
		headerScroll  = headerScroll,
		headerContent = headerContent,
		bodyScroll    = bodyScroll,
		vBar          = vBar,
		hBar          = hBar,
		type          = Type,
	}
	for method, func in pairs(methods) do
		widget[method] = func
	end

	headerScroll.obj = widget
	bodyScroll.obj = widget
	vBar.obj = widget
	hBar.obj = widget
	frame.obj = widget

	return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
end -- version check
end -- GuildInfoTable
