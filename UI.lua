--[[-----------------------------------------------------------------------------
GuildInfo - UI
AceGUI-Fenster: Mitgliederliste mit Filtern und Sortierung, Detail-/Bearbeitungs-
panel sowie Main/Twink-Baum.
-------------------------------------------------------------------------------]]
local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = _G.GuildInfoNS end
local L = LibStub("AceLocale-3.0"):GetLocale("GuildInfo")
local AceGUI = LibStub("AceGUI-3.0")
local GuildInfo = ns.Addon
local C = ns.Const
local Roster = ns.Roster

local UI = {}
GuildInfo.UI = UI
ns.UI = UI

local pairs, ipairs, tinsert, tsort, format, date, max = pairs, ipairs, table.insert, table.sort, string.format, date, math.max

local TAB_MEMBERS = "members"
local TAB_TWINKS  = "twinks"
local TAB_OPTIONS = "options"
local NONE        = ""          -- Dropdown-Wert für "kein Eintrag"
local UNASSIGNED  = "__unassigned"

local ARROW_UP   = "|TInterface\\Buttons\\Arrow-Up-Up:12:12:0:-2|t"
local ARROW_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:12:12:0:-2|t"

local GOLD = { 1, 0.82, 0 }

local DETAIL_WIDTH = 320    -- Breite des Detailpanels (Mitglieder-Tab)
local SPLIT_GAP    = 6      -- Abstand zwischen Liste und Detailpanel

-------------------------------------------------------------------------------
-- Layout "GuildInfoSplit": children[1] = Liste (links), children[2] = Details
-- (rechts). Das rechte Panel wird nur angezeigt, wenn UI.detailVisible gesetzt
-- ist; sonst bekommt die Liste die volle Breite.
-------------------------------------------------------------------------------
AceGUI:RegisterLayout("GuildInfoSplit", function(content, children)
	local left, right = children[1], children[2]
	if not left then return end
	local width  = content.width or content:GetWidth() or 0
	local height = content.height or content:GetHeight() or 0
	local showRight = right and UI.detailVisible

	left.frame:ClearAllPoints()
	left.frame:SetPoint("TOPLEFT", content, "TOPLEFT")
	left.frame:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT")
	left:SetWidth(showRight and max(100, width - DETAIL_WIDTH - SPLIT_GAP) or width)
	left:SetHeight(height)
	left.frame:Show()

	if right then
		right.frame:ClearAllPoints()
		if showRight then
			right.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT")
			right.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT")
			right:SetWidth(DETAIL_WIDTH)
			right:SetHeight(height)
			right.frame:Show()
		else
			right.frame:Hide()
		end
	end

	if content.obj.LayoutFinished then
		content.obj:LayoutFinished(nil, height)
	end
end)

-------------------------------------------------------------------------------
-- Spalten der Mitgliederliste
-------------------------------------------------------------------------------
local COLUMNS = {
	{ key = "name",     title = L["Name"],         width = 130 },
	{ key = "level",    title = L["Level"],        width = 40, justify = "CENTER" },
	{ key = "class",    title = L["Class"],        width = 100 },
	{ key = "rank",     title = L["Rank"],         width = 90 },
	{ key = "mainSpec", title = L["Main Spec"],    width = 125 },
	{ key = "offSpec",  title = L["Off Spec"],     width = 125 },
	{ key = "prof1",    title = L["Profession 1"], width = 110 },
	{ key = "prof2",    title = L["Profession 2"], width = 110 },
	{ key = "main",     title = L["Main / Alt"],   width = 140, flex = true },
}

-------------------------------------------------------------------------------
-- Textbausteine
-------------------------------------------------------------------------------
local function ColoredName(name, classFile)
	return C.ColorText(name, C.GetClassColor(classFile))
end

local function SpecText(specId, withRole)
	local spec = C.GetSpec(specId)
	if not spec then return "" end
	local text = C.IconText(spec.icon, 14) .. " " .. spec.name
	if withRole then
		local role = C.ROLE_BY_ID[spec.role]
		if role then
			text = text .. " " .. C.ColorText("(" .. role.short .. ")", 0.55, 0.55, 0.55)
		end
	end
	return text
end

local function ProfText(profId)
	local prof = C.GetProfession(profId)
	if not prof then return "" end
	return C.IconText(prof.icon, 14) .. " " .. prof.name
end

local function MainAltText(name, m)
	if m.isMain then
		return C.ColorText(L["Main"], GOLD[1], GOLD[2], GOLD[3])
	elseif m.mainOf then
		local main = GuildInfo:GetMember(m.mainOf)
		local mainName = main and ColoredName(m.mainOf, main.classFile) or m.mainOf
		return format(L["Alt of %s"], mainName)
	end
	return ""
end

local function LastSeenText(m)
	if m.online then return C.ColorText(L["Online"], 0.2, 1, 0.2) end
	if (m.lastSeen or 0) > 0 then
		return format(L["Last seen: %s"], date("%d.%m.%Y %H:%M", m.lastSeen))
	end
	return C.ColorText(L["Offline"], 0.6, 0.6, 0.6)
end

-------------------------------------------------------------------------------
-- Fensterzustand
-------------------------------------------------------------------------------
function UI:IsOpen()
	return self.frame ~= nil
end

function UI:GetFilterOptions()
	local p = GuildInfo.db.profile
	self.filter = self.filter or { search = "", classFile = "", role = "" }
	return {
		search      = self.filter.search,
		classFile   = self.filter.classFile,
		role        = self.filter.role,
		onlineOnly  = p.onlineOnly,
		showFormer  = p.showFormer,
		groupTwinks = p.groupTwinks,
		sortKey     = p.sortKey,
		sortAsc     = p.sortAsc,
	}
end

function UI:Open()
	if self.frame then return end
	local db = GuildInfo.db.profile

	GuildInfo:RequestRoster()

	local frame = AceGUI:Create("Frame")
	self.frame = frame
	frame:SetStatusTable(db.window)
	frame:SetLayout("Fill")
	frame:SetCallback("OnClose", function(widget)
		UI:OnFrameClosed()
		AceGUI:Release(widget)
	end)

	-- ESC schließt das Fenster: Der Proxy-Frame wird über UISpecialFrames
	-- geschlossen und schließt per OnHide das eigentliche Fenster.
	-- ACHTUNG: Nicht "GuildInfoFrame" als Namen verwenden - das ist ein
	-- Blizzard-Frame (Gildeninfo-Popup in FriendsFrame.xml)!
	self:GetEscapeProxy():Show()

	local tabs = AceGUI:Create("TabGroup")
	self.tabs = tabs
	tabs:SetTabs({
		{ text = L["Members"],      value = TAB_MEMBERS },
		{ text = L["Mains & Alts"], value = TAB_TWINKS },
		{ text = L["Options"],      value = TAB_OPTIONS },
	})
	tabs:SetCallback("OnGroupSelected", function(container, event, value)
		UI:OnTabSelected(container, value)
	end)
	frame:AddChild(tabs)

	self.selected = nil
	self.edit = nil
	tabs:SelectTab(db.lastTab or TAB_MEMBERS)

	self:UpdateTitle()
	GuildInfo:StartRosterTicker()
end

function UI:Close()
	if self.frame then
		self.frame:Hide()   -- löst OnClose aus
	end
end

-- Unsichtbarer Proxy-Frame mit eindeutigem Namen für UISpecialFrames (ESC).
-- Ein eigener Frame ist nötig, weil AceGUI-Frames gepoolt und wiederverwendet
-- werden und daher nicht dauerhaft unter einem globalen Namen stehen dürfen.
function UI:GetEscapeProxy()
	if self.escapeProxy then return self.escapeProxy end
	local proxy = CreateFrame("Frame", "GuildInfoEscapeProxyFrame", UIParent)
	proxy:SetWidth(1)
	proxy:SetHeight(1)
	proxy:SetPoint("CENTER")
	proxy:EnableMouse(false)
	proxy:Hide()
	proxy:SetScript("OnHide", function()
		if UI.frame then
			UI:Close()
		end
	end)
	tinsert(UISpecialFrames, "GuildInfoEscapeProxyFrame")
	self.escapeProxy = proxy
	return proxy
end

function UI:OnFrameClosed()
	GuildInfo:StopRosterTicker()
	GameTooltip:Hide()
	self.frame = nil
	if self.escapeProxy then
		self.escapeProxy:Hide()
	end
	self.tabs = nil
	self.body = nil
	self.scroll = nil
	self.table = nil
	self.header = nil
	self.detail = nil
	self.tree = nil
	self.rows = nil
	self.options = nil
end

function UI:UpdateTitle(displayed)
	if not self.frame then return end
	local _, guildName = GuildInfo:GetGuildData()
	self.frame:SetTitle(L["GuildInfo"] .. (guildName and (" - " .. guildName) or ""))
	local total, online = Roster:GetCounts()
	if displayed == nil then
		displayed = #Roster:GetFilteredList(self:GetFilterOptions())
	end
	self.frame:SetStatusText(format(L["%d members (%d shown), %d online"], total, displayed, online) .. "   |cff808080v" .. GuildInfo.version .. "|r")
end

function UI:Refresh()
	if not self.frame then return end
	self:UpdateTitle()
	if self.currentTab == TAB_MEMBERS then
		self:RefreshList()
	elseif self.currentTab == TAB_TWINKS then
		self:RefreshTree()
	elseif self.currentTab == TAB_OPTIONS then
		self:RefreshOptions()
		return -- kein Detailpanel
	end
	self:UpdateDetail()
end

-------------------------------------------------------------------------------
-- Tabs
-------------------------------------------------------------------------------
function UI:OnTabSelected(container, value)
	container:ReleaseChildren()
	self.body, self.scroll, self.table, self.header, self.detail, self.tree, self.rows, self.options = nil, nil, nil, nil, nil, nil, nil, nil
	self.currentTab = value
	GuildInfo.db.profile.lastTab = value

	if value == TAB_MEMBERS then
		self:BuildMembersTab(container)
	elseif value == TAB_OPTIONS then
		self:BuildOptionsTab(container)
	else
		self:BuildTwinksTab(container)
	end
end

-------------------------------------------------------------------------------
-- Tab: Mitglieder
-------------------------------------------------------------------------------
function UI:BuildMembersTab(container)
	container:SetLayout("Flow")
	local db = GuildInfo.db.profile
	self.filter = self.filter or { search = "", classFile = "", role = "" }

	-- Filterzeile ----------------------------------------------------------
	local filterGroup = AceGUI:Create("SimpleGroup")
	filterGroup:SetFullWidth(true)
	filterGroup:SetLayout("Flow")
	container:AddChild(filterGroup)

	local search = AceGUI:Create("EditBox")
	search:SetLabel(nil)
	search:SetWidth(150)
	search:SetText(self.filter.search or "")
	search:DisableButton(true)
	search:SetCallback("OnTextChanged", function(widget, event, text)
		UI.filter.search = text or ""
		UI:RefreshList()
	end)
	search:SetCallback("OnEnterPressed", function(widget, event, text)
		UI.filter.search = text or ""
		UI:RefreshList()
	end)
	filterGroup:AddChild(search)

	local classDD = AceGUI:Create("Dropdown")
	classDD:SetLabel(nil)
	classDD:SetWidth(140)
	classDD:SetList({})
	classDD:AddItem("", L["All classes"])
	for _, classFile in ipairs(C.CLASS_ORDER) do
		classDD:AddItem(classFile, C.ClassIconText(classFile, 14) .. " " .. ColoredName(C.GetClassName(classFile), classFile))
	end
	classDD:SetValue(self.filter.classFile or "")
	classDD:SetCallback("OnValueChanged", function(widget, event, value)
		UI.filter.classFile = value or ""
		UI:RefreshList()
	end)
	filterGroup:AddChild(classDD)

	local roleDD = AceGUI:Create("Dropdown")
	roleDD:SetLabel(nil)
	roleDD:SetWidth(120)
	roleDD:SetList({})
	roleDD:AddItem("", L["All roles"])
	for _, role in ipairs(C.ROLES) do
		roleDD:AddItem(role.id, C.IconText(role.icon, 14) .. " " .. role.name)
	end
	roleDD:SetValue(self.filter.role or "")
	roleDD:SetCallback("OnValueChanged", function(widget, event, value)
		UI.filter.role = value or ""
		UI:RefreshList()
	end)
	filterGroup:AddChild(roleDD)

	local onlineCB = AceGUI:Create("CheckBox")
	onlineCB:SetLabel(L["Online only"])
	onlineCB:SetWidth(100)
	onlineCB:SetValue(db.onlineOnly)
	onlineCB:SetCallback("OnValueChanged", function(widget, event, value)
		db.onlineOnly = value and true or false
		UI:RefreshList()
	end)
	filterGroup:AddChild(onlineCB)

	local formerCB = AceGUI:Create("CheckBox")
	formerCB:SetLabel(L["Show former members"])
	formerCB:SetWidth(150)
	formerCB:SetValue(db.showFormer)
	formerCB:SetCallback("OnValueChanged", function(widget, event, value)
		db.showFormer = value and true or false
		UI:RefreshList()
	end)
	filterGroup:AddChild(formerCB)

	local groupCB = AceGUI:Create("CheckBox")
	groupCB:SetLabel(L["Group alts under main"])
	groupCB:SetWidth(190)
	groupCB:SetValue(db.groupTwinks)
	groupCB:SetCallback("OnValueChanged", function(widget, event, value)
		db.groupTwinks = value and true or false
		UI:RefreshList()
	end)
	filterGroup:AddChild(groupCB)

	local refreshBtn = AceGUI:Create("Button")
	refreshBtn:SetText(L["Refresh"])
	refreshBtn:SetWidth(110)
	refreshBtn:SetCallback("OnClick", function()
		GuildInfo:RequestRoster()
		Roster:Scan()
		UI:Refresh()
	end)
	filterGroup:AddChild(refreshBtn)

	-- Body: Liste links, Detailpanel rechts (nur bei Auswahl sichtbar) -------
	local body = AceGUI:Create("SimpleGroup")
	body:SetFullWidth(true)
	body:SetFullHeight(true)
	body:SetAutoAdjustHeight(false)
	body:SetLayout("GuildInfoSplit")
	container:AddChild(body)
	self.body = body
	self.detailVisible = (self.selected ~= nil and GuildInfo:GetMember(self.selected) ~= nil)

	-- Linke Seite: Tabelle mit fester Kopfzeile und horizontalem Scrollen ------
	local tbl = AceGUI:Create("GuildInfoTable")
	tbl:SetAutoAdjustHeight(false)
	tbl:SetLayout("List")
	tbl:SetColumns(COLUMNS)
	self.scrollStatus = self.scrollStatus or {}
	tbl:SetStatusTable(self.scrollStatus)
	body:AddChild(tbl)
	self.table = tbl
	self.scroll = tbl

	local header = tbl:GetHeader()
	header:SetCallback("OnColumnClick", function(widget, event, col)
		local column = COLUMNS[col]
		if not column then return end
		local p = GuildInfo.db.profile
		if p.sortKey == column.key then
			p.sortAsc = not p.sortAsc
		else
			p.sortKey = column.key
			p.sortAsc = true
		end
		UI:RefreshList()
	end)
	header:SetCallback("OnEnter", function(widget)
		local p = GuildInfo.db.profile
		local title
		for _, col in ipairs(COLUMNS) do
			if col.key == p.sortKey then title = col.title end
		end
		GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
		GameTooltip:SetText(format(L["Sort by %s"], title or ""), 1, 0.82, 0)
		GameTooltip:Show()
	end)
	header:SetCallback("OnLeave", function() GameTooltip:Hide() end)
	self.header = header

	-- Rechte Seite: Detailpanel (ein-/ausblendbar) ---------------------------
	local right = AceGUI:Create("SimpleGroup")
	right:SetAutoAdjustHeight(false)
	right:SetLayout("Fill")
	body:AddChild(right)

	local detailScroll = AceGUI:Create("ScrollFrame")
	detailScroll:SetLayout("Flow")
	right:AddChild(detailScroll)

	self:BuildDetailPanel(detailScroll, true)

	self:RefreshList()
	self:UpdateDetail()
end

-- Blendet das Detailpanel im Mitglieder-Tab ein oder aus.
function UI:SetDetailVisible(visible)
	visible = visible and true or false
	if self.detailVisible == visible then return end
	self.detailVisible = visible
	if self.body then
		self.body:DoLayout()
	end
end

-- X-Button im Detailpanel: Auswahl aufheben und Panel ausblenden.
function UI:CloseDetail()
	GameTooltip:Hide()
	if self.selected and self.rows and self.rows[self.selected] then
		self.rows[self.selected]:SetSelected(false)
	end
	self.selected = nil
	self.edit = nil
	self:SetDetailVisible(false)
	self:UpdateDetail()
end

-- Einmalig erzeugter Schließen-Button, der beim Aufbau des Detailpanels an das
-- jeweilige (gepoolte) AceGUI-Frame gehängt und beim Release wieder gelöst wird.
function UI:GetDetailCloseButton()
	if self.detailCloseBtn then return self.detailCloseBtn end
	local btn = CreateFrame("Button", nil, UIParent, "UIPanelCloseButton")
	btn:SetWidth(26)
	btn:SetHeight(26)
	btn:SetScript("OnClick", function() UI:CloseDetail() end)
	btn:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetText(CLOSE)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	btn:Hide()
	self.detailCloseBtn = btn
	return btn
end

function UI:UpdateHeader()
	if not self.header then return end
	local p = GuildInfo.db.profile
	for i, col in ipairs(COLUMNS) do
		local title = col.title
		if p.sortKey == col.key then
			title = title .. " " .. (p.sortAsc and ARROW_UP or ARROW_DOWN)
		end
		self.header:SetCell(i, title, GOLD[1], GOLD[2], GOLD[3])
	end
end

local function FillRow(row, name, m, indent)
	local r, g, b = C.GetClassColor(m.classFile)
	local me = (name == UnitName("player"))

	row:SetIndent(indent or 0)
	row:SetOnlineDot(m.online and true or false)

	local nameText = C.ClassIconText(m.classFile, 14) .. " " .. ColoredName(name, m.classFile)
	if me then nameText = nameText .. " |cffffd100*|r" end
	if not m.inGuild then nameText = nameText .. C.ColorText(" (" .. L["Former member"] .. ")", 0.5, 0.5, 0.5) end
	row:SetCell(1, nameText)
	row:SetCell(2, tostring(m.level or 0), 1, 1, 1)
	row:SetCell(3, C.GetClassName(m.classFile), r, g, b)
	row:SetCell(4, m.rank or "", 0.85, 0.85, 0.85)
	row:SetCell(5, SpecText(m.mainSpec, true))
	row:SetCell(6, SpecText(m.offSpec, true))
	row:SetCell(7, ProfText(m.prof1))
	row:SetCell(8, ProfText(m.prof2))
	row:SetCell(9, MainAltText(name, m))

	if not m.inGuild then
		row:SetAlpha(0.5)
	elseif not m.online then
		row:SetAlpha(0.75)
	else
		row:SetAlpha(1)
	end
end

function UI:RefreshList()
	if not self.table then return end
	self:UpdateHeader()

	local scroll = self.table
	scroll:ReleaseChildren()
	scroll:PauseLayout()

	local list = Roster:GetFilteredList(self:GetFilterOptions())
	self:UpdateTitle(#list)
	self.rows = {}

	for i, entry in ipairs(list) do
		local row = AceGUI:Create("GuildInfoRow")
		row:SetColumns(COLUMNS)
		row:SetStripe(i % 2 == 0)
		FillRow(row, entry.name, entry.data, entry.indent)
		row:SetSelected(self.selected == entry.name)
		row:SetUserData("name", entry.name)
		row:SetCallback("OnClick", function(widget, event, button)
			UI:SelectMember(widget:GetUserData("name"))
		end)
		row:SetCallback("OnEnter", function(widget)
			UI:ShowMemberTooltip(widget.frame, widget:GetUserData("name"))
		end)
		row:SetCallback("OnLeave", function() GameTooltip:Hide() end)
		scroll:AddChild(row)
		self.rows[entry.name] = row
	end

	scroll:ResumeLayout()
	scroll:DoLayout()
end

-------------------------------------------------------------------------------
-- Tooltip
-------------------------------------------------------------------------------
function UI:ShowMemberTooltip(anchor, name)
	local m = GuildInfo:GetMember(name)
	if not m then return end
	local r, g, b = C.GetClassColor(m.classFile)

	GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	GameTooltip:AddLine(C.ClassIconText(m.classFile, 16) .. " " .. name, r, g, b)
	GameTooltip:AddLine(format("%s %d %s", L["Level"], m.level or 0, C.GetClassName(m.classFile)) ..
		((m.rank and m.rank ~= "") and (" - " .. m.rank) or ""), 1, 1, 1)
	GameTooltip:AddLine(LastSeenText(m), 0.8, 0.8, 0.8)
	if m.online and m.zone and m.zone ~= "" then
		GameTooltip:AddLine(format(L["Zone: %s"], m.zone), 0.8, 0.8, 0.8)
	end
	if not m.inGuild then
		GameTooltip:AddLine(L["Former member"], 1, 0.3, 0.3)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Main Spec"], (m.mainSpec and SpecText(m.mainSpec, true)) or "-", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Off Spec"], (m.offSpec and SpecText(m.offSpec, true)) or "-", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Profession 1"], (m.prof1 and ProfText(m.prof1)) or "-", 1, 0.82, 0, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Profession 2"], (m.prof2 and ProfText(m.prof2)) or "-", 1, 0.82, 0, 1, 1, 1)

	local mainAlt = MainAltText(name, m)
	if mainAlt ~= "" then
		GameTooltip:AddDoubleLine(L["Main / Alt"], mainAlt, 1, 0.82, 0, 1, 1, 1)
	end
	if m.isMain then
		local twinks = Roster:GetTwinks(name, true)
		if #twinks > 0 then
			local parts = {}
			for _, t in ipairs(twinks) do
				local tm = GuildInfo:GetMember(t)
				tinsert(parts, ColoredName(t, tm and tm.classFile))
			end
			GameTooltip:AddDoubleLine(L["Alts"], table.concat(parts, ", "), 1, 0.82, 0, 1, 1, 1)
		end
	end

	if m.note and m.note ~= "" then
		GameTooltip:AddLine(format(L["Guild note: %s"], m.note), 0.7, 0.9, 1, true)
	end
	if m.officerNote and m.officerNote ~= "" then
		GameTooltip:AddLine(format(L["Officer note: %s"], m.officerNote), 1, 0.9, 0.6, true)
	end
	if m.userNote and m.userNote ~= "" then
		GameTooltip:AddLine(L["Note"] .. ": " .. m.userNote, 1, 1, 0.6, true)
	end
	if m.modifiedBy and (m.modified or 0) > 0 then
		GameTooltip:AddLine(format(L["Last edited by %s on %s"], m.modifiedBy, date("%d.%m.%Y %H:%M", m.modified)), 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Click to edit"], 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

-------------------------------------------------------------------------------
-- Auswahl
-------------------------------------------------------------------------------
function UI:SelectMember(name)
	if self.selected and self.rows and self.rows[self.selected] then
		self.rows[self.selected]:SetSelected(false)
	end
	self.selected = name
	self.edit = nil
	if name and self.rows and self.rows[name] then
		self.rows[name]:SetSelected(true)
	end
	self:SetDetailVisible(name ~= nil)
	self:UpdateDetail()
end

local function LoadEdit(name)
	local m = GuildInfo:GetMember(name)
	if not m then return nil end
	return {
		mainSpec = m.mainSpec or NONE,
		offSpec  = m.offSpec or NONE,
		prof1    = m.prof1 or NONE,
		prof2    = m.prof2 or NONE,
		isMain   = m.isMain and true or false,
		mainOf   = m.mainOf or NONE,
		note     = m.userNote or "",
	}
end

-------------------------------------------------------------------------------
-- Detailpanel
-------------------------------------------------------------------------------
local function FillDropdown(dd, items, noneText)
	dd:SetList({})
	dd:AddItem(NONE, noneText or L["- none -"])
	for _, item in ipairs(items) do
		dd:AddItem(item.value, item.text)
	end
end

-- closable = true: X-Button oben rechts, der das Panel ausblendet (Mitglieder-Tab)
function UI:BuildDetailPanel(container, closable)
	local d = { container = container }
	self.detail = d

	local group = AceGUI:Create("InlineGroup")
	group:SetTitle(L["Details"])
	group:SetFullWidth(true)
	group:SetLayout("Flow")
	container:AddChild(group)
	d.group = group

	if closable then
		local btn = self:GetDetailCloseButton()
		btn:SetParent(group.frame)
		btn:ClearAllPoints()
		btn:SetPoint("TOPRIGHT", group.frame, "TOPRIGHT", 2, 6)
		btn:SetFrameLevel(group.frame:GetFrameLevel() + 5)
		btn:Show()
		-- Das InlineGroup-Frame ist gepoolt: Button vor Wiederverwendung lösen.
		group:SetCallback("OnRelease", function()
			btn:Hide()
			btn:ClearAllPoints()
			btn:SetParent(UIParent)
		end)
	end

	d.nameLabel = AceGUI:Create("Label")
	d.nameLabel:SetFullWidth(true)
	d.nameLabel:SetFontObject(GameFontNormalLarge)
	group:AddChild(d.nameLabel)

	d.infoLabel = AceGUI:Create("Label")
	d.infoLabel:SetFullWidth(true)
	d.infoLabel:SetFontObject(GameFontHighlightSmall)
	group:AddChild(d.infoLabel)

	d.heading = AceGUI:Create("Heading")
	d.heading:SetFullWidth(true)
	d.heading:SetText("")
	group:AddChild(d.heading)

	d.mainSpec = AceGUI:Create("Dropdown")
	d.mainSpec:SetLabel(L["Main Spec"])
	d.mainSpec:SetFullWidth(true)
	d.mainSpec:SetCallback("OnValueChanged", function(widget, event, value)
		if UI.edit then UI.edit.mainSpec = value end
	end)
	group:AddChild(d.mainSpec)

	d.offSpec = AceGUI:Create("Dropdown")
	d.offSpec:SetLabel(L["Off Spec"])
	d.offSpec:SetFullWidth(true)
	d.offSpec:SetCallback("OnValueChanged", function(widget, event, value)
		if UI.edit then UI.edit.offSpec = value end
	end)
	group:AddChild(d.offSpec)

	d.prof1 = AceGUI:Create("Dropdown")
	d.prof1:SetLabel(L["Profession 1"])
	d.prof1:SetFullWidth(true)
	d.prof1:SetCallback("OnValueChanged", function(widget, event, value)
		if UI.edit then UI.edit.prof1 = value end
	end)
	group:AddChild(d.prof1)

	d.prof2 = AceGUI:Create("Dropdown")
	d.prof2:SetLabel(L["Profession 2"])
	d.prof2:SetFullWidth(true)
	d.prof2:SetCallback("OnValueChanged", function(widget, event, value)
		if UI.edit then UI.edit.prof2 = value end
	end)
	group:AddChild(d.prof2)

	d.isMain = AceGUI:Create("CheckBox")
	d.isMain:SetLabel(L["Is main character"])
	d.isMain:SetFullWidth(true)
	d.isMain:SetCallback("OnValueChanged", function(widget, event, value)
		if not UI.edit then return end
		UI.edit.isMain = value and true or false
		if UI.edit.isMain then
			UI.edit.mainOf = NONE
			d.mainOf:SetValue(NONE)
		end
		d.mainOf:SetDisabled(UI.edit.isMain)
	end)
	group:AddChild(d.isMain)

	d.mainOf = AceGUI:Create("Dropdown")
	d.mainOf:SetLabel(L["Alt of"])
	d.mainOf:SetFullWidth(true)
	d.mainOf:SetCallback("OnValueChanged", function(widget, event, value)
		if not UI.edit then return end
		UI.edit.mainOf = value or NONE
		if UI.edit.mainOf ~= NONE then
			UI.edit.isMain = false
			d.isMain:SetValue(false)
		end
	end)
	group:AddChild(d.mainOf)

	d.note = AceGUI:Create("EditBox")
	d.note:SetLabel(L["Note"])
	d.note:SetFullWidth(true)
	d.note:SetMaxLetters(120)
	d.note:DisableButton(true)
	d.note:SetCallback("OnTextChanged", function(widget, event, text)
		if UI.edit then UI.edit.note = text or "" end
	end)
	d.note:SetCallback("OnEnterPressed", function(widget, event, text)
		if UI.edit then UI.edit.note = text or "" end
		UI:SaveEdit()
	end)
	group:AddChild(d.note)

	d.save = AceGUI:Create("Button")
	d.save:SetText(L["Save"])
	d.save:SetRelativeWidth(0.5)
	d.save:SetCallback("OnClick", function() UI:SaveEdit() end)
	group:AddChild(d.save)

	d.reset = AceGUI:Create("Button")
	d.reset:SetText(L["Reset"])
	d.reset:SetRelativeWidth(0.5)
	d.reset:SetCallback("OnClick", function()
		UI.edit = nil
		UI:UpdateDetail()
	end)
	group:AddChild(d.reset)

	d.hint = AceGUI:Create("Label")
	d.hint:SetFullWidth(true)
	d.hint:SetText("")
	d.hint:SetColor(0.6, 0.6, 0.6)
	container:AddChild(d.hint)
end

function UI:SetDetailEnabled(enabled)
	local d = self.detail
	if not d then return end
	local disabled = not enabled
	d.mainSpec:SetDisabled(disabled)
	d.offSpec:SetDisabled(disabled)
	d.prof1:SetDisabled(disabled)
	d.prof2:SetDisabled(disabled)
	d.isMain:SetDisabled(disabled)
	d.mainOf:SetDisabled(disabled)
	d.note:SetDisabled(disabled)
	d.save:SetDisabled(disabled)
	d.reset:SetDisabled(disabled)
end

function UI:UpdateDetail()
	local d = self.detail
	if not d then return end

	local name = self.selected
	local m = name and GuildInfo:GetMember(name)
	if not m then
		d.nameLabel:SetText(L["Details"])
		d.nameLabel:SetColor(1, 0.82, 0)
		d.infoLabel:SetText(L["Select a member from the list."])
		d.heading:SetText("")
		FillDropdown(d.mainSpec, {})
		FillDropdown(d.offSpec, {})
		FillDropdown(d.prof1, {})
		FillDropdown(d.prof2, {})
		FillDropdown(d.mainOf, {})
		d.mainSpec:SetValue(NONE)
		d.offSpec:SetValue(NONE)
		d.prof1:SetValue(NONE)
		d.prof2:SetValue(NONE)
		d.mainOf:SetValue(NONE)
		d.isMain:SetValue(false)
		d.note:SetText("")
		d.hint:SetText("")
		self:SetDetailEnabled(false)
		d.group:DoLayout()
		d.container:DoLayout()
		-- Im Mitglieder-Tab ohne (gültige) Auswahl kein Panel anzeigen
		if self.currentTab == TAB_MEMBERS then
			self:SetDetailVisible(false)
		end
		return
	end

	if not self.edit then
		self.edit = LoadEdit(name)
	end
	local e = self.edit
	local r, g, b = C.GetClassColor(m.classFile)

	d.nameLabel:SetText(C.ClassIconText(m.classFile, 18) .. " " .. name)
	d.nameLabel:SetColor(r, g, b)

	local info = format("%s %d %s", L["Level"], m.level or 0, C.GetClassName(m.classFile))
	if m.rank and m.rank ~= "" then info = info .. "  |cffaaaaaa-|r  " .. m.rank end
	info = info .. "\n" .. LastSeenText(m)
	if m.online and m.zone and m.zone ~= "" then info = info .. "  |cffaaaaaa-|r  " .. m.zone end
	if m.note and m.note ~= "" then info = info .. "\n" .. C.ColorText(format(L["Guild note: %s"], m.note), 0.7, 0.9, 1) end
	if not m.inGuild then info = info .. "\n" .. C.ColorText(L["Former member"], 1, 0.3, 0.3) end
	d.infoLabel:SetText(info)
	d.heading:SetText(MainAltText(name, m))

	-- Specs je Klasse
	local specItems = {}
	for _, spec in ipairs(C.GetSpecsForClass(m.classFile) or {}) do
		tinsert(specItems, { value = spec.id, text = SpecText(spec.id, true) })
	end
	FillDropdown(d.mainSpec, specItems)
	FillDropdown(d.offSpec, specItems)
	d.mainSpec:SetValue(e.mainSpec)
	d.offSpec:SetValue(e.offSpec)

	-- Berufe
	local profItems = {}
	for _, prof in ipairs(C.PROFESSIONS) do
		tinsert(profItems, { value = prof.id, text = ProfText(prof.id) })
	end
	FillDropdown(d.prof1, profItems)
	FillDropdown(d.prof2, profItems)
	d.prof1:SetValue(e.prof1)
	d.prof2:SetValue(e.prof2)

	-- Main / Twink
	d.isMain:SetValue(e.isMain)
	local mainItems = {}
	for _, mainName in ipairs(Roster:GetMains(true)) do
		if mainName ~= name then
			local mm = GuildInfo:GetMember(mainName)
			tinsert(mainItems, { value = mainName, text = C.ClassIconText(mm.classFile, 14) .. " " .. ColoredName(mainName, mm.classFile) })
		end
	end
	FillDropdown(d.mainOf, mainItems)
	d.mainOf:SetValue(e.mainOf)

	d.note:SetText(e.note or "")

	self:SetDetailEnabled(true)
	d.mainOf:SetDisabled(e.isMain)

	if name == UnitName("player") and GuildInfo.db.profile.autoDetect then
		d.hint:SetText(L["Auto-detect my own specs and professions"])
	else
		d.hint:SetText("")
	end

	d.group:DoLayout()
	d.container:DoLayout()
end

function UI:SaveEdit()
	local name, e = self.selected, self.edit
	if not name or not e then return end
	local m = GuildInfo:GetMember(name)
	if not m then return end

	m.mainSpec = (e.mainSpec ~= NONE) and e.mainSpec or nil
	m.offSpec  = (e.offSpec ~= NONE) and e.offSpec or nil
	m.prof1    = (e.prof1 ~= NONE) and e.prof1 or nil
	m.prof2    = (e.prof2 ~= NONE) and e.prof2 or nil
	m.userNote = e.note or ""

	if e.isMain then
		Roster:SetMain(name, true)
	else
		if m.isMain then
			Roster:SetMain(name, false)
		end
		Roster:SetMainOf(name, (e.mainOf ~= NONE) and e.mainOf or nil)
	end

	-- Bearbeitungsstempel setzen und an berechtigte Mitglieder senden
	m.modified = time()
	m.modifiedBy = UnitName("player")
	if GuildInfo.Sync then
		GuildInfo.Sync:SendEdit(name)
		if name == UnitName("player") then
			GuildInfo.Sync:QueueSelf()
		end
	end

	self.edit = nil
	GuildInfo:Print(format(L["Saved: %s"], ColoredName(name, m.classFile)))
	self:Refresh()
end

-------------------------------------------------------------------------------
-- Tab: Mains & Twinks (TreeGroup)
-------------------------------------------------------------------------------
local function TreeNodeFor(name)
	local m = GuildInfo:GetMember(name)
	local tc = m and m.classFile and C.CLASS_ICON_TCOORDS[m.classFile]
	local text = m and ColoredName(name, m.classFile) or name
	if m and not m.inGuild then
		text = text .. C.ColorText(" (" .. L["Former member"] .. ")", 0.5, 0.5, 0.5)
	elseif m and not m.online then
		text = text .. C.ColorText(" - " .. L["Offline"], 0.5, 0.5, 0.5)
	end
	return {
		value = name,
		text = text,
		icon = tc and C.CLASS_ICON_TEXTURE or nil,
		iconCoords = tc,
	}
end

function UI:BuildTree()
	local guild = GuildInfo:GetGuildData()
	local tree = {}
	if not guild then return tree end
	local showFormer = GuildInfo.db.profile.showFormer

	local assigned = {}
	for _, mainName in ipairs(Roster:GetMains(showFormer)) do
		local node = TreeNodeFor(mainName)
		assigned[mainName] = true
		local twinks = Roster:GetTwinks(mainName, showFormer)
		if #twinks > 0 then
			node.children = {}
			for _, t in ipairs(twinks) do
				tinsert(node.children, TreeNodeFor(t))
				assigned[t] = true
			end
			node.text = node.text .. C.ColorText(format("  [%d]", #twinks), 0.6, 0.6, 0.6)
		end
		tinsert(tree, node)
	end

	local rest = {}
	for name, m in pairs(guild.members) do
		if not assigned[name] and (showFormer or m.inGuild) then
			tinsert(rest, name)
		end
	end
	tsort(rest)
	if #rest > 0 then
		local node = { value = UNASSIGNED, text = L["Unassigned"] .. C.ColorText(format("  [%d]", #rest), 0.6, 0.6, 0.6), children = {} }
		for _, name in ipairs(rest) do
			tinsert(node.children, TreeNodeFor(name))
		end
		tinsert(tree, node)
	end
	return tree
end

function UI:BuildTwinksTab(container)
	container:SetLayout("Fill")

	local tree = AceGUI:Create("TreeGroup")
	tree:SetFullWidth(true)
	tree:SetFullHeight(true)
	tree:SetTreeWidth(280, true)
	tree:SetLayout("Fill")
	tree:EnableButtonTooltips(false)
	self.treeStatus = self.treeStatus or { groups = {} }
	tree:SetStatusTable(self.treeStatus)
	tree:SetCallback("OnGroupSelected", function(widget, event, uniquevalue)
		local path = { ("\001"):split(uniquevalue) }
		local name = path[#path]
		if name == UNASSIGNED then name = nil end
		UI.selected = name
		UI.edit = nil
		UI:UpdateDetail()
	end)
	tree:SetCallback("OnButtonEnter", function(widget, event, uniquevalue, button)
		local path = { ("\001"):split(uniquevalue) }
		local name = path[#path]
		if name and name ~= UNASSIGNED then
			UI:ShowMemberTooltip(button, name)
		end
	end)
	tree:SetCallback("OnButtonLeave", function() GameTooltip:Hide() end)
	container:AddChild(tree)
	self.tree = tree

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	scroll:SetLayout("Flow")
	tree:AddChild(scroll)

	self:BuildDetailPanel(scroll)
	self:RefreshTree()

	-- Vorherige Auswahl wiederherstellen
	if self.selected then
		local m = GuildInfo:GetMember(self.selected)
		if m then
			if m.mainOf then
				tree:SelectByPath(m.mainOf, self.selected)
			elseif m.isMain then
				tree:SelectByPath(self.selected)
			else
				tree:SelectByPath(UNASSIGNED, self.selected)
			end
		end
	end
	self:UpdateDetail()
end

function UI:RefreshTree()
	if not self.tree then return end
	self.tree:SetTree(self:BuildTree())
end

-------------------------------------------------------------------------------
-- Tab: Optionen
-------------------------------------------------------------------------------
function UI:BuildOptionsTab(container)
	container:SetLayout("Fill")
	local p = GuildInfo.db.profile
	local Sync = GuildInfo.Sync

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetFullWidth(true)
	scroll:SetFullHeight(true)
	scroll:SetLayout("Flow")
	container:AddChild(scroll)

	local o = { scroll = scroll }
	self.options = o

	-- Allgemein ---------------------------------------------------------------
	local general = AceGUI:Create("InlineGroup")
	general:SetTitle(L["General"])
	general:SetFullWidth(true)
	general:SetLayout("Flow")
	scroll:AddChild(general)

	local autoCB = AceGUI:Create("CheckBox")
	autoCB:SetLabel(L["Auto-detect my own specs and professions"])
	autoCB:SetFullWidth(true)
	autoCB:SetValue(p.autoDetect)
	autoCB:SetCallback("OnValueChanged", function(widget, event, value)
		p.autoDetect = value and true or false
		if value then
			Roster:UpdateSelf()
		end
	end)
	general:AddChild(autoCB)

	-- Synchronisation ----------------------------------------------------------
	local syncGroup = AceGUI:Create("InlineGroup")
	syncGroup:SetTitle(L["Synchronization"])
	syncGroup:SetFullWidth(true)
	syncGroup:SetLayout("Flow")
	scroll:AddChild(syncGroup)

	local shareCB = AceGUI:Create("CheckBox")
	shareCB:SetLabel(L["Share my own specs and professions with the whole guild"])
	shareCB:SetFullWidth(true)
	shareCB:SetValue(p.sync.shareSelf)
	shareCB:SetCallback("OnValueChanged", function(widget, event, value)
		p.sync.shareSelf = value and true or false
		if value and Sync then Sync:SendHello() end
	end)
	syncGroup:AddChild(shareCB)
	o.shareCB = shareCB

	local shareHint = AceGUI:Create("Label")
	shareHint:SetFullWidth(true)
	shareHint:SetColor(0.6, 0.6, 0.6)
	shareHint:SetText(L["Your specs and professions are sent to every guild member using GuildInfo. This does not use the rank limit."])
	syncGroup:AddChild(shareHint)

	local enabledCB = AceGUI:Create("CheckBox")
	enabledCB:SetLabel(L["Exchange edits with selected ranks"])
	enabledCB:SetFullWidth(true)
	enabledCB:SetValue(p.sync.enabled)
	enabledCB:SetCallback("OnValueChanged", function(widget, event, value)
		p.sync.enabled = value and true or false
		UI:UpdateOptionsState()
		if value and Sync then Sync:SyncNow() end
	end)
	syncGroup:AddChild(enabledCB)
	o.enabledCB = enabledCB

	local rankDD = AceGUI:Create("Dropdown")
	rankDD:SetLabel(L["Share edits with ranks up to and including"])
	rankDD:SetWidth(300)
	rankDD:SetList({})
	local ranks = Sync and Sync:GetRankList() or {}
	for _, r in ipairs(ranks) do
		rankDD:AddItem(r.index, format("%s (%d)", r.name, r.index + 1))
	end
	rankDD:SetValue(p.sync.maxRank)
	rankDD:SetCallback("OnValueChanged", function(widget, event, value)
		p.sync.maxRank = tonumber(value) or 0
		UI:RefreshOptions()
	end)
	syncGroup:AddChild(rankDD)
	o.rankDD = rankDD

	local syncBtn = AceGUI:Create("Button")
	syncBtn:SetText(L["Sync now"])
	syncBtn:SetWidth(160)
	syncBtn:SetCallback("OnClick", function()
		if Sync then
			Sync:SyncNow()
			GuildInfo:Print(L["Sync requested."])
		end
	end)
	syncGroup:AddChild(syncBtn)
	o.syncBtn = syncBtn

	local rankHint = AceGUI:Create("Label")
	rankHint:SetFullWidth(true)
	rankHint:SetColor(0.6, 0.6, 0.6)
	rankHint:SetText(L["Edits (main/alt assignment, notes, entries of other members) are only exchanged with online members whose rank is within this limit. All participants should use the same rank limit."])
	syncGroup:AddChild(rankHint)
	o.rankHint = rankHint

	-- Sync-Status --------------------------------------------------------------
	local status = AceGUI:Create("InlineGroup")
	status:SetTitle(L["Sync status"])
	status:SetFullWidth(true)
	status:SetLayout("Flow")
	scroll:AddChild(status)
	o.status = status

	self:UpdateOptionsState()
	self:RefreshOptions()
end

function UI:UpdateOptionsState()
	local o = self.options
	if not o then return end
	local edits = GuildInfo.db.profile.sync.enabled
	o.rankDD:SetDisabled(not edits)
	o.syncBtn:SetDisabled(not edits)
	if o.rankHint then
		if edits then
			o.rankHint:SetColor(0.6, 0.6, 0.6)
		else
			o.rankHint:SetColor(0.4, 0.4, 0.4)
		end
	end
end

local function AddStatusLine(group, text, r, g, b)
	local label = AceGUI:Create("Label")
	label:SetFullWidth(true)
	label:SetText(text)
	if r then label:SetColor(r, g, b) end
	group:AddChild(label)
end

function UI:RefreshOptions()
	local o = self.options
	if not o or not o.status then return end
	local Sync = GuildInfo.Sync
	local status = o.status
	status:ReleaseChildren()

	if not Sync then
		AddStatusLine(status, "-")
	else
		local syncSettings = GuildInfo.db.profile.sync
		if syncSettings.shareSelf then
			AddStatusLine(status, L["Your specs and professions are shared with the guild."], 0.2, 1, 0.2)
		else
			AddStatusLine(status, L["You are not sharing your specs and professions."], 0.6, 0.6, 0.6)
		end

		if syncSettings.enabled then
			local me = UnitName("player")
			local myMember = GuildInfo:GetMember(me)
			local myRank = myMember and myMember.rank or ""
			if Sync:IsSelfAuthorized() then
				AddStatusLine(status, format(L["Your rank (%s) is authorized to exchange edits."], myRank), 0.2, 1, 0.2)
			else
				AddStatusLine(status, format(L["Your rank (%s) is not authorized to exchange edits."], myRank), 1, 0.5, 0.3)
			end

			local last = Sync.lastSync
			if last then
				AddStatusLine(status, format(L["Last sync: %d entries from %s at %s"], last.count, last.from,
					date("%d.%m.%Y %H:%M", last.time)), 0.8, 0.8, 0.8)
			end
		end

		local peers = Sync:GetPeerList()
		AddStatusLine(status, format(L["Known members with GuildInfo: %d"], #peers), 1, 0.82, 0)
		for _, peer in ipairs(peers) do
			local line = { C.ClassIconText(peer.classFile, 14) .. " " .. ColoredName(peer.name, peer.classFile) }
			if peer.rank ~= "" then tinsert(line, C.ColorText(peer.rank, 0.85, 0.85, 0.85)) end
			tinsert(line, C.ColorText("v" .. tostring(peer.version or "?"), 0.6, 0.6, 0.6))
			tinsert(line, peer.online and C.ColorText(L["Online"], 0.2, 1, 0.2) or C.ColorText(L["Offline"], 0.6, 0.6, 0.6))
			if syncSettings.enabled then
				tinsert(line, peer.authorized and C.ColorText(L["authorized"], 0.2, 1, 0.2) or C.ColorText(L["not authorized"], 0.6, 0.6, 0.6))
				if not peer.enabled then tinsert(line, C.ColorText(L["edits off"], 1, 0.5, 0.3)) end
			end
			AddStatusLine(status, table.concat(line, "  |cff555555|||r  "))
		end
	end

	status:DoLayout()
	o.scroll:DoLayout()
end
