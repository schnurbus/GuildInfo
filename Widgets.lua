--[[-----------------------------------------------------------------------------
GuildInfo - Widgets
AceGUI-Widget "GuildInfoRow": eine Tabellenzeile mit mehreren Spalten
(FontStrings), Hover-Highlight, Auswahlmarkierung, Online-Indikator.
Wird sowohl für die Kopfzeile als auch für die Datenzeilen verwendet.
-------------------------------------------------------------------------------]]
local Type, Version = "GuildInfoRow", 1
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI or (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local pairs, ipairs, max = pairs, ipairs, math.max
local CreateFrame, UIParent, GetCursorPosition = CreateFrame, UIParent, GetCursorPosition

local ROW_HEIGHT   = 18
local CELL_PADDING = 4
local INDENT_WIDTH = 16

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

-------------------------------------------------------------------------------
-- Layout-Berechnung
-------------------------------------------------------------------------------
local function Relayout(self)
	local columns = self.columns
	if not columns then return end
	local frame = self.frame
	local total = frame.width or frame:GetWidth() or 0
	local indent = (self.indent or 0) * INDENT_WIDTH
	local dotWidth = self.showDot and 12 or 0
	local available = total - indent - dotWidth

	-- Fixe Breiten summieren, Rest an die Flex-Spalte(n)
	local fixed, flexCount = 0, 0
	for _, c in ipairs(columns) do
		if c.flex then flexCount = flexCount + 1 else fixed = fixed + (c.width or 80) end
	end
	local flexWidth = flexCount > 0 and max(40, (available - fixed) / flexCount) or 0

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
	frame:SetScript("OnEnter", Row_OnEnter)
	frame:SetScript("OnLeave", Row_OnLeave)
	frame:SetScript("OnClick", Row_OnClick)

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
