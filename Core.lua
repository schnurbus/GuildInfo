--[[-----------------------------------------------------------------------------
GuildInfo - Core
AddOn-Objekt, Datenbank, Slash-Befehle und Event-Registrierung
-------------------------------------------------------------------------------]]
local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = _G.GuildInfoNS end
ADDON_NAME = type(ADDON_NAME) == "string" and ADDON_NAME or "GuildInfo"
local L = LibStub("AceLocale-3.0"):GetLocale("GuildInfo")

local GuildInfo = LibStub("AceAddon-3.0"):NewAddon("GuildInfo",
	"AceEvent-3.0", "AceTimer-3.0", "AceBucket-3.0", "AceConsole-3.0",
	"AceComm-3.0", "AceSerializer-3.0")
ns.Addon = GuildInfo
_G.GuildInfo = GuildInfo

GuildInfo.version = GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-------------------------------------------------------------------------------
-- Datenbank
-------------------------------------------------------------------------------
local defaults = {
	profile = {
		window = {
			width  = 1100,
			height = 620,
		},
		onlineOnly   = false,
		showFormer   = false,
		groupTwinks  = false,
		sortKey      = "name",
		sortAsc      = true,
		autoDetect   = true,
		lastTab      = "members",
		minimapHint  = true,
		sync = {
			enabled   = true,   -- Bearbeitungen mit Rängen bis maxRank austauschen
			shareSelf = true,   -- eigene Specs/Berufe an die ganze Gilde senden (unabhängig von enabled)
			maxRank   = 1,      -- Bearbeitungen nur mit Rang-Index <= maxRank teilen (0 = Gildenmeister)
		},
	},
	factionrealm = {
		lastGuild = nil,
		guilds = {
			["*"] = {
				members = {
					["*"] = {
						class     = nil,     -- lokalisierter Klassenname
						classFile = nil,     -- z.B. "WARRIOR"
						level     = 0,
						rank      = "",
						rankIndex = 0,
						zone      = "",
						note      = "",
						officerNote = "",
						online    = false,
						lastSeen  = 0,       -- time()
						inGuild   = true,
						mainSpec  = nil,     -- Spec-ID aus Constants
						offSpec   = nil,
						prof1     = nil,     -- Berufs-ID aus Constants
						prof2     = nil,
						isMain    = false,
						mainOf    = nil,     -- Name des Main-Chars
						userNote  = "",      -- eigene Notiz (wird synchronisiert)
						modified  = 0,       -- time() der letzten manuellen Bearbeitung (Sync: Last-Writer-Wins)
						modifiedBy = nil,    -- Name des Bearbeiters
						selfStamp = 0,       -- time() der letzten Selbst-Meldung des Besitzers (Specs/Berufe)
					},
				},
			},
		},
	},
}

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
function GuildInfo:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("GuildInfoDB", defaults, true)

	self:RegisterChatCommand("gi", "HandleSlash")
	self:RegisterChatCommand("guildinfo", "HandleSlash")
end

function GuildInfo:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("PLAYER_GUILD_UPDATE")
	self:RegisterEvent("PLAYER_TALENT_UPDATE", "OnSelfChanged")
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnSelfChanged")
	self:RegisterEvent("SKILL_LINES_CHANGED", "OnSelfChanged")
	self:RegisterBucketEvent("GUILD_ROSTER_UPDATE", 0.5, "OnRosterUpdate")

	if self.Sync then
		self:RegisterComm(self.Sync.PREFIX, function(...) self.Sync:OnCommReceived(...) end)
	end

	self:ScheduleTimer("HookGuildFrame", 1)
	self:RequestRoster()

	self:Print(L["Loaded. Type /gi to open the window."])
end

function GuildInfo:OnDisable()
	self:StopRosterTicker()
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
function GuildInfo:PLAYER_ENTERING_WORLD()
	self:RequestRoster()
	if self.Sync then
		self.Sync:ScheduleHello()
	end
end

function GuildInfo:PLAYER_GUILD_UPDATE(event, unit)
	if unit and unit ~= "player" then return end
	self:RequestRoster()
end

function GuildInfo:OnRosterUpdate()
	if not self.Roster then return end
	-- Schutz vor Endlosschleife: Falls das Umschalten des Offline-Filters in
	-- Roster:Scan() selbst ein GUILD_ROSTER_UPDATE auslöst, dieses ignorieren,
	-- sofern wir nicht selbst gerade eine Aktualisierung angefordert haben.
	if not self.rosterRequested and self.Roster.lastFilterToggle
		and (GetTime() - self.Roster.lastFilterToggle) < 1 then
		return
	end
	self.rosterRequested = nil
	self.Roster:Scan()
	if self.Sync then
		self.Sync:OnRosterScanned()
	end
	if self.UI and self.UI:IsOpen() then
		self.UI:Refresh()
	end
end

function GuildInfo:OnSelfChanged()
	if not self.Roster then return end
	-- Talente/Skills sind kurz nach dem Event manchmal noch nicht aktuell
	self:ScheduleTimer(function()
		self.Roster:UpdateSelf()
		if self.UI and self.UI:IsOpen() then
			self.UI:Refresh()
		end
	end, 0.5)
end

-------------------------------------------------------------------------------
-- Roster-Anforderung
-------------------------------------------------------------------------------
function GuildInfo:RequestRoster()
	if not IsInGuild() then return end
	-- Der Offline-Filter wird NICHT hier global gesetzt (das würde die
	-- "Offline anzeigen"-Checkbox im Blizzard-Gildenfenster umschalten),
	-- sondern nur kurzzeitig in Roster:Scan() aktiviert.
	self.rosterRequested = true
	GuildRoster()
end

-- Solange das Fenster offen ist, alle 60 Sekunden aktualisieren
function GuildInfo:StartRosterTicker()
	if self.rosterTicker then return end
	self.rosterTicker = self:ScheduleRepeatingTimer("RequestRoster", 60)
end

function GuildInfo:StopRosterTicker()
	if self.rosterTicker then
		self:CancelTimer(self.rosterTicker, true)
		self.rosterTicker = nil
	end
end

-------------------------------------------------------------------------------
-- Gildendaten
-------------------------------------------------------------------------------
function GuildInfo:GetGuildName()
	if IsInGuild() then
		local name = GetGuildInfo("player")
		if name and name ~= "" then
			self.db.factionrealm.lastGuild = name
			return name
		end
	end
	return self.db.factionrealm.lastGuild
end

function GuildInfo:GetGuildData()
	local name = self:GetGuildName()
	if not name then return nil end
	return self.db.factionrealm.guilds[name], name
end

function GuildInfo:GetMember(name)
	local guild = self:GetGuildData()
	if not guild or not name then return nil end
	return guild.members[name]
end

-------------------------------------------------------------------------------
-- Slash-Befehle
-------------------------------------------------------------------------------
function GuildInfo:HandleSlash(input)
	input = input and strtrim(input):lower() or ""
	if input == "" or input == "show" or input == "toggle" then
		self:Toggle()
	elseif input == "refresh" or input == "update" then
		self:RequestRoster()
		self:Print(L["Roster refresh requested."])
	elseif input == "reset" then
		self.db.profile.window = { width = 1100, height = 620 }
		if self.UI and self.UI:IsOpen() then
			self.UI:Close()
		end
		self:Toggle()
	elseif input == "detect" or input == "autodetect" then
		self:AutoDetect()
	elseif input == "sync" then
		if self.Sync then
			self.Sync:SyncNow()
			self:Print(L["Sync requested."])
		end
	else
		self:Print("/gi  - " .. L["Opens the GuildInfo window"])
		self:Print("/gi refresh  - " .. L["Refresh"])
		self:Print("/gi reset  - " .. L["Reset"])
		self:Print("/gi detect  - " .. L["Auto-detect mains and alts from ranks and notes"])
		self:Print("/gi sync  - " .. L["Sync now"])
	end
end

-- Main/Twink-Status aller Mitglieder anhand von Rang und Notizen ermitteln
function GuildInfo:AutoDetect()
	if not IsInGuild() or not self.Roster then
		self:Print(L["Not in a guild"])
		return
	end
	local stats = self.Roster:AutoDetectMainsAndTwinks()
	self:Print(L["Auto-detect: %d mains, %d alts assigned, %d alts unresolved (%d changes)."]:format(
		stats.mains, stats.twinks, #stats.unresolved, stats.changes))
	if #stats.unresolved > 0 then
		self:Print(L["Alts without identifiable main: %s"]:format(table.concat(stats.unresolved, ", ")))
	end
	-- Geänderte Einträge stempeln und an berechtigte Mitglieder senden
	if self.Sync and stats.changed and #stats.changed > 0 then
		self.Sync:StampMembers(stats.changed)
		self.Sync:SendEdits(stats.changed)
	end
	if self.UI and self.UI:IsOpen() then
		self.UI:Refresh()
	end
end

function GuildInfo:Toggle()
	if not self.UI then return end
	if self.UI:IsOpen() then
		self.UI:Close()
	else
		if not IsInGuild() and not self.db.factionrealm.lastGuild then
			self:Print(L["Not in a guild"])
			return
		end
		self.UI:Open()
	end
end

-------------------------------------------------------------------------------
-- Button im Blizzard-Gildenfenster (FriendsFrame -> GuildFrame in 3.3.5a)
-------------------------------------------------------------------------------
function GuildInfo:HookGuildFrame()
	if self.guildFrameButton then return end
	local parent = _G["GuildFrame"]
	if not parent then return end

	-- Kleiner Icon-Button links oben (rechts sitzt die "Offline anzeigen"-Checkbox)
	local btn = CreateFrame("Button", "GuildInfoGuildFrameButton", parent)
	btn:SetWidth(22)
	btn:SetHeight(22)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 80, -38)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(btn)
	icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	border:SetWidth(40)
	border:SetHeight(40)
	border:SetPoint("CENTER", btn, "CENTER", 0, -1)
	btn.border = border

	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	btn:SetScript("OnClick", function() GuildInfo:Toggle() end)
	btn:SetScript("OnEnter", function(this)
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(L["GuildInfo"], 1, 0.82, 0)
		GameTooltip:AddLine(L["Opens the GuildInfo window"], 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	self.guildFrameButton = btn
end
