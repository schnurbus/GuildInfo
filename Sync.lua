--[[-----------------------------------------------------------------------------
GuildInfo - Sync
Austausch der nicht aus dem Gildenroster stammenden Daten per Addon-Nachrichten.

  * HELLO  (GUILD)   Anwesenheit/Version melden; Empfänger antworten per WHISPER
  * SELF   (GUILD)   eigene Specs/Berufe an alle (Besitzer ist autoritativ)
  * EDIT   (WHISPER) manuelle Bearbeitungen (Main/Twink, Notiz, Fremd-Einträge)
                     nur an berechtigte Online-Mitglieder (Rang <= maxRank)
  * REQ    (WHISPER) Vollabgleich anfordern
  * FULL   (WHISPER) Antwort auf REQ: alle Einträge mit Bearbeitungsstempel

Der 3.3.5a-Client kennt keinen OFFICER-Kanal für Addon-Nachrichten, daher
werden rangbeschränkte Daten per WHISPER verteilt und zusätzlich beim Empfang
auf den Rang des Absenders geprüft.
-------------------------------------------------------------------------------]]
local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = _G.GuildInfoNS end
local L = LibStub("AceLocale-3.0"):GetLocale("GuildInfo")
local GuildInfo = ns.Addon
local Roster = ns.Roster

local Sync = {}
GuildInfo.Sync = Sync
ns.Sync = Sync

local time, pairs, ipairs, tinsert, tsort = time, pairs, ipairs, table.insert, table.sort

Sync.PREFIX   = "GuildInfo"
Sync.PROTOCOL = 1

local HELLO_DELAY   = 5     -- Sekunden nach dem Einloggen bis zum HELLO
local REQUEST_DELAY = 3     -- Sekunden nach dem HELLO bis zur Vollabgleich-Anfrage
local SELF_DEBOUNCE = 5     -- Sekunden Verzögerung für SELF nach Änderungen
local MAX_FUTURE    = 600   -- Zeitstempel weiter in der Zukunft werden gekappt
local BATCH_SIZE    = 25    -- Einträge pro EDIT/FULL-Nachricht

Sync.peers = {}      -- [name] = { version=, seen=, enabled=, maxRank= }
Sync.queue = {}      -- vor dem ersten Roster-Scan empfangene Nachrichten
Sync.lastSync = nil  -- { from=, time=, count= }

-------------------------------------------------------------------------------
-- Hilfsfunktionen
-------------------------------------------------------------------------------
local function Settings()
	return GuildInfo.db.profile.sync
end

local function MyName()
	return UnitName("player")
end

function Sync:IsEnabled()
	return Settings().enabled and IsInGuild() and true or false
end

-- Darf dieses Mitglied rangbeschränkte Daten senden/empfangen?
function Sync:IsAuthorized(name)
	if not name then return false end
	local guild = GuildInfo:GetGuildData()
	if not guild then return false end
	local m = rawget(guild.members, name)
	if not m or not m.inGuild then return false end
	return (m.rankIndex or 99) <= (Settings().maxRank or 0)
end

function Sync:IsSelfAuthorized()
	return self:IsAuthorized(MyName())
end

-- Rangliste der Gilde: { { index = 0, name = "Gildenmeister" }, ... }
function Sync:GetRankList()
	local list = {}
	local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
	if num and num > 0 and GuildControlGetRankName then
		for i = 1, num do
			tinsert(list, { index = i - 1, name = GuildControlGetRankName(i) or tostring(i) })
		end
		return list
	end
	-- Fallback: Ränge aus den bekannten Mitgliedern ableiten
	local guild = GuildInfo:GetGuildData()
	if not guild then return list end
	local byIndex = {}
	for _, m in pairs(guild.members) do
		if m.inGuild and m.rank and m.rank ~= "" then
			byIndex[m.rankIndex or 0] = m.rank
		end
	end
	for index, name in pairs(byIndex) do
		tinsert(list, { index = index, name = name })
	end
	tsort(list, function(a, b) return a.index < b.index end)
	return list
end

-- Berechtigte Online-Mitglieder mit Addon (ohne uns selbst)
function Sync:GetAuthorizedOnlinePeers()
	local result = {}
	local guild = GuildInfo:GetGuildData()
	if not guild then return result end
	local me = MyName()
	for name, peer in pairs(self.peers) do
		if name ~= me and peer.enabled then
			local m = rawget(guild.members, name)
			if m and m.online and self:IsAuthorized(name) then
				tinsert(result, name)
			end
		end
	end
	tsort(result)
	return result
end

-- Sortierte Peer-Liste für die Anzeige
function Sync:GetPeerList()
	local list = {}
	local guild = GuildInfo:GetGuildData()
	for name, peer in pairs(self.peers) do
		local m = guild and rawget(guild.members, name)
		tinsert(list, {
			name       = name,
			version    = peer.version,
			seen       = peer.seen,
			enabled    = peer.enabled,
			maxRank    = peer.maxRank,
			online     = m and m.online or false,
			rank       = m and m.rank or "",
			classFile  = m and m.classFile,
			authorized = self:IsAuthorized(name),
		})
	end
	tsort(list, function(a, b)
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	return list
end

function Sync:NotifyUI()
	if self.uiTimer then return end
	self.uiTimer = GuildInfo:ScheduleTimer(function()
		Sync.uiTimer = nil
		if GuildInfo.UI and GuildInfo.UI:IsOpen() then
			GuildInfo.UI:Refresh()
		end
	end, 0.5)
end

-------------------------------------------------------------------------------
-- Senden
-------------------------------------------------------------------------------
function Sync:Send(msg, distribution, target, prio)
	if not IsInGuild() then return end
	msg.v = self.PROTOCOL
	local text = GuildInfo:Serialize(msg)
	GuildInfo:SendCommMessage(self.PREFIX, text, distribution, target, prio or "NORMAL")
end

function Sync:SendHello(replyTo)
	if not self:IsEnabled() then return end
	local s = Settings()
	local msg = { t = "HELLO", ver = GuildInfo.version, en = s.enabled, mr = s.maxRank, r = replyTo and true or nil }
	if replyTo then
		self:Send(msg, "WHISPER", replyTo)
		self:SendSelf(replyTo)
	else
		self:Send(msg, "GUILD")
		self:SendSelf()
	end
end

function Sync:BuildSelfMessage()
	local m = GuildInfo:GetMember(MyName())
	if not m then return nil end
	return { t = "SELF", ms = m.mainSpec, os = m.offSpec, p1 = m.prof1, p2 = m.prof2 }
end

function Sync:SendSelf(target)
	if not self:IsEnabled() or not Settings().shareSelf then return end
	local msg = self:BuildSelfMessage()
	if not msg then return end
	if self.selfTimer then
		GuildInfo:CancelTimer(self.selfTimer, true)
		self.selfTimer = nil
	end
	if target then
		self:Send(msg, "WHISPER", target)
	else
		self:Send(msg, "GUILD")
	end
end

-- Eigene Daten verzögert senden (mehrere Änderungen kurz hintereinander bündeln)
function Sync:QueueSelf()
	if not self:IsEnabled() or not Settings().shareSelf then return end
	if self.helloTimer then return end -- HELLO sendet SELF ohnehin mit
	if self.selfTimer then
		GuildInfo:CancelTimer(self.selfTimer, true)
	end
	self.selfTimer = GuildInfo:ScheduleTimer(function()
		Sync.selfTimer = nil
		Sync:SendSelf()
	end, SELF_DEBOUNCE)
end

function Sync:ScheduleHello()
	if self.helloTimer then
		GuildInfo:CancelTimer(self.helloTimer, true)
	end
	self.helloTimer = GuildInfo:ScheduleTimer(function()
		Sync.helloTimer = nil
		Sync:SendHello()
		GuildInfo:ScheduleTimer(function() Sync:RequestFull() end, REQUEST_DELAY)
	end, HELLO_DELAY)
end

-- HELLO + Vollabgleich manuell anstoßen
function Sync:SyncNow()
	if self.helloTimer then
		GuildInfo:CancelTimer(self.helloTimer, true)
		self.helloTimer = nil
	end
	self:SendHello()
	GuildInfo:ScheduleTimer(function() Sync:RequestFull() end, REQUEST_DELAY)
end

function Sync:BuildEntry(name)
	local guild = GuildInfo:GetGuildData()
	local m = guild and rawget(guild.members, name)
	if not m then return nil end
	return {
		n  = name,
		im = m.isMain and true or nil,
		mo = m.mainOf,
		un = (m.userNote and m.userNote ~= "") and m.userNote or nil,
		ms = m.mainSpec,
		os = m.offSpec,
		p1 = m.prof1,
		p2 = m.prof2,
		md = m.modified or 0,
		mb = m.modifiedBy,
	}
end

function Sync:StampMembers(names)
	local guild = GuildInfo:GetGuildData()
	if not guild then return end
	local now, me = time(), MyName()
	for _, name in ipairs(names) do
		local m = rawget(guild.members, name)
		if m then
			m.modified = now
			m.modifiedBy = me
		end
	end
end

-- Einträge in Paketen an alle berechtigten Online-Peers senden
local function SendEntries(self, msgType, entries, targets, prio)
	if #entries == 0 or #targets == 0 then return end
	local i = 1
	while i <= #entries do
		local batch = {}
		for j = i, math.min(i + BATCH_SIZE - 1, #entries) do
			tinsert(batch, entries[j])
		end
		for _, target in ipairs(targets) do
			self:Send({ t = msgType, e = batch }, "WHISPER", target, prio)
		end
		i = i + BATCH_SIZE
	end
end

function Sync:SendEdit(name)
	self:SendEdits({ name })
end

function Sync:SendEdits(names)
	if not self:IsEnabled() or not self:IsSelfAuthorized() then return end
	local entries = {}
	for _, name in ipairs(names) do
		local entry = self:BuildEntry(name)
		if entry then tinsert(entries, entry) end
	end
	SendEntries(self, "EDIT", entries, self:GetAuthorizedOnlinePeers(), "NORMAL")
end

function Sync:SendFull(target)
	if not self:IsEnabled() or not self:IsSelfAuthorized() then return end
	local guild = GuildInfo:GetGuildData()
	if not guild then return end
	local entries = {}
	for name, m in pairs(guild.members) do
		if (m.modified or 0) > 0 then
			local entry = self:BuildEntry(name)
			if entry then tinsert(entries, entry) end
		end
	end
	tsort(entries, function(a, b) return a.n < b.n end)
	SendEntries(self, "FULL", entries, { target }, "BULK")
end

-- Vollabgleich beim ranghöchsten berechtigten Online-Peer anfordern
function Sync:RequestFull()
	if not self:IsEnabled() or not self:IsSelfAuthorized() then return end
	local guild = GuildInfo:GetGuildData()
	if not guild then return end
	local best, bestRank
	for _, name in ipairs(self:GetAuthorizedOnlinePeers()) do
		local m = rawget(guild.members, name)
		local rank = m and m.rankIndex or 99
		if not best or rank < bestRank then
			best, bestRank = name, rank
		end
	end
	if best then
		self:Send({ t = "REQ" }, "WHISPER", best)
	end
end

-------------------------------------------------------------------------------
-- Empfangen
-------------------------------------------------------------------------------
function Sync:OnCommReceived(prefix, message, distribution, sender)
	if prefix ~= self.PREFIX or not sender or sender == MyName() then return end
	if not self:IsEnabled() then return end
	-- Rangprüfung braucht Rosterdaten: bis zum ersten Scan puffern
	if not Roster.scanned then
		tinsert(self.queue, { message, distribution, sender })
		return
	end
	self:HandleMessage(message, distribution, sender)
end

function Sync:OnRosterScanned()
	if #self.queue == 0 then return end
	local queue = self.queue
	self.queue = {}
	for _, item in ipairs(queue) do
		self:HandleMessage(item[1], item[2], item[3])
	end
end

function Sync:HandleMessage(message, distribution, sender)
	local ok, msg = GuildInfo:Deserialize(message)
	if not ok or type(msg) ~= "table" or msg.v ~= self.PROTOCOL then return end

	local t = msg.t
	if t == "HELLO" then
		self:OnHello(msg, sender)
	elseif t == "SELF" then
		self:OnSelf(msg, sender)
	elseif distribution ~= "WHISPER" then
		return -- EDIT/REQ/FULL nur per WHISPER akzeptieren
	elseif not self:IsAuthorized(sender) or not self:IsSelfAuthorized() then
		return -- Absender oder wir selbst nicht berechtigt
	elseif t == "EDIT" or t == "FULL" then
		self:OnEntries(msg, sender, t == "FULL")
	elseif t == "REQ" then
		self:SendFull(sender)
	end
end

function Sync:OnHello(msg, sender)
	self.peers[sender] = {
		version = msg.ver,
		seen    = time(),
		enabled = msg.en and true or false,
		maxRank = msg.mr,
	}
	if not msg.r then
		-- Broadcast: mit eigenem HELLO + SELF antworten
		self:SendHello(sender)
	end
	self:NotifyUI()
end

function Sync:OnSelf(msg, sender)
	local guild = GuildInfo:GetGuildData()
	if not guild then return end
	local m = rawget(guild.members, sender)
	if not m then return end -- unbekannt (kein Gildenmitglied laut Roster)
	m.mainSpec = msg.ms
	m.offSpec  = msg.os
	m.prof1    = msg.p1
	m.prof2    = msg.p2
	m.selfStamp = time()
	local peer = self.peers[sender]
	if peer then peer.seen = time() end
	self:NotifyUI()
end

function Sync:ApplyEntry(entry, sender)
	if type(entry) ~= "table" or type(entry.n) ~= "string" then return false end
	local guild = GuildInfo:GetGuildData()
	if not guild then return false end
	local m = rawget(guild.members, entry.n)
	if not m then return false end -- keine Phantom-Einträge anlegen

	local now = time()
	local md = tonumber(entry.md) or 0
	if md > now + MAX_FUTURE then md = now end
	if md <= (m.modified or 0) then return false end -- wir haben neuere Daten

	-- Main/Twink
	if entry.im then
		Roster:SetMain(entry.n, true)
	else
		if m.isMain then Roster:SetMain(entry.n, false) end
		if entry.mo and entry.mo ~= "" and entry.mo ~= entry.n and rawget(guild.members, entry.mo) then
			Roster:SetMainOf(entry.n, entry.mo)
		else
			m.mainOf = nil
		end
	end

	m.userNote = type(entry.un) == "string" and entry.un or ""

	-- Specs/Berufe nur übernehmen, wenn der Besitzer sie nicht selbst meldet
	local isSelf = (entry.n == MyName())
	if not isSelf and (m.selfStamp or 0) == 0 then
		m.mainSpec = entry.ms
		m.offSpec  = entry.os
		m.prof1    = entry.p1
		m.prof2    = entry.p2
	end

	m.modified = md
	m.modifiedBy = type(entry.mb) == "string" and entry.mb or sender
	return true
end

function Sync:OnEntries(msg, sender, isFull)
	if type(msg.e) ~= "table" then return end
	local count = 0
	for _, entry in ipairs(msg.e) do
		if self:ApplyEntry(entry, sender) then
			count = count + 1
		end
	end
	Roster:ValidateLinks()
	local peer = self.peers[sender]
	if peer then peer.seen = time() end

	if count > 0 then
		self.lastSync = { from = sender, time = time(), count = count }
		if isFull then
			GuildInfo:Print(L["Sync: %d entries received from %s."]:format(count, sender))
		end
		self:NotifyUI()
	end
end
