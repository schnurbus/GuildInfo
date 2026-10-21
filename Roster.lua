--[[-----------------------------------------------------------------------------
GuildInfo - Roster
Gildenliste einlesen, eigenen Char erkennen, Main/Twink-Logik
-------------------------------------------------------------------------------]]
local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = _G.GuildInfoNS end
local L = LibStub("AceLocale-3.0"):GetLocale("GuildInfo")
local GuildInfo = ns.Addon
local C = ns.Const

local Roster = {}
GuildInfo.Roster = Roster
ns.Roster = Roster

local time, pairs, ipairs, tsort, tinsert = time, pairs, ipairs, table.sort, table.insert

-------------------------------------------------------------------------------
-- Klassen-Fallback: lokalisierter Name -> Klassen-Token
-------------------------------------------------------------------------------
local classByLocalized
local function ResolveClassFile(classFileName, localizedClass)
	if classFileName and classFileName ~= "" then return classFileName end
	if not localizedClass then return nil end
	if not classByLocalized then
		classByLocalized = {}
		for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByLocalized[name] = token end
		for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByLocalized[name] = token end
	end
	return classByLocalized[localizedClass]
end

-------------------------------------------------------------------------------
-- Roster einlesen
-------------------------------------------------------------------------------
-- Offline-Filter nur für die Dauer des Einlesens aktivieren und danach den
-- vorherigen Zustand wiederherstellen, damit die "Offline anzeigen"-Checkbox
-- im Blizzard-Gildenfenster unverändert bleibt.
local function WithOfflineMembers(fn, ...)
	if not (GetGuildRosterShowOffline and SetGuildRosterShowOffline) then
		return fn(...)
	end
	local previous = GetGuildRosterShowOffline()
	if previous then
		return fn(...)
	end
	SetGuildRosterShowOffline(true)
	local ok, err = pcall(fn, ...)
	SetGuildRosterShowOffline(false)
	Roster.lastFilterToggle = GetTime()
	if not ok then error(err, 0) end
end

function Roster:Scan()
	if not IsInGuild() then return end
	local guild = GuildInfo:GetGuildData()
	if not guild then return end
	WithOfflineMembers(self.ScanMembers, self, guild)
	self:UpdateSelf()
	self:ValidateLinks()
	self.scanned = true
end

function Roster:ScanMembers(guild)
	local total = GetNumGuildMembers(true)
	if not total or total == 0 then return end

	local now = time()
	local seen = {}

	for i = 1, total do
		local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName = GetGuildRosterInfo(i)
		if name and name ~= "" then
			seen[name] = true
			local m = guild.members[name]
			m.rank        = rank or ""
			m.rankIndex   = rankIndex or 0
			m.level       = level or 0
			m.class       = class
			m.classFile   = ResolveClassFile(classFileName, class) or m.classFile
			m.zone        = zone or ""
			m.note        = note or ""
			m.officerNote = officernote or ""
			m.online      = online and true or false
			m.status      = status
			m.inGuild     = true
			if online then
				m.lastSeen = now
			elseif GetGuildRosterLastOnline then
				local years, months, days, hours = GetGuildRosterLastOnline(i)
				if years or months or days or hours then
					local offset = ((years or 0) * 365 + (months or 0) * 30 + (days or 0)) * 86400 + (hours or 0) * 3600
					local approx = now - offset
					-- Nur aktualisieren, wenn wir keinen genaueren Wert haben
					if (m.lastSeen or 0) == 0 or approx > m.lastSeen then
						m.lastSeen = approx
					end
				end
			end
		end
	end

	-- Nicht mehr vorhandene Mitglieder als "ehemalig" markieren
	for name, m in pairs(guild.members) do
		if not seen[name] and m.inGuild then
			m.inGuild = false
			m.online = false
		end
	end
end

-------------------------------------------------------------------------------
-- Eigenen Charakter: Specs und Berufe automatisch erkennen
-------------------------------------------------------------------------------
local function DetectSpecForGroup(classFile, group)
	local specs = C.GetSpecsForClass(classFile)
	if not specs then return nil end

	local numTabs = GetNumTalentTabs()
	if not numTabs or numTabs == 0 then return nil end

	local bestTab, bestPoints, totalPoints = nil, 0, 0
	for tab = 1, numTabs do
		local _, _, pointsSpent = GetTalentTabInfo(tab, false, false, group)
		pointsSpent = pointsSpent or 0
		totalPoints = totalPoints + pointsSpent
		if pointsSpent > bestPoints then
			bestTab, bestPoints = tab, pointsSpent
		end
	end
	if not bestTab or totalPoints == 0 then return nil end

	-- Kandidaten für diesen Baum sammeln (Druide: Bär/Katze teilen sich einen Baum)
	local candidates = {}
	for _, spec in ipairs(specs) do
		if spec.tab == bestTab then tinsert(candidates, spec) end
	end
	if #candidates == 0 then return nil end
	if #candidates == 1 then return candidates[1].id end

	for _, spec in ipairs(candidates) do
		if spec.tankTalent then
			local numTalents = GetNumTalents(bestTab, false, false) or 0
			for t = 1, numTalents do
				local tname, _, _, _, rank = GetTalentInfo(bestTab, t, false, false, group)
				if tname == spec.tankTalent then
					if (rank or 0) > 0 then return spec.id end
					break
				end
			end
		end
	end
	-- Kein Tank-Talent gefunden -> erste Variante ohne tankTalent
	for _, spec in ipairs(candidates) do
		if not spec.tankTalent then return spec.id end
	end
	return candidates[1].id
end

local function DetectProfessions()
	local found = {}
	local num = GetNumSkillLines() or 0
	for i = 1, num do
		local skillName, isHeader = GetSkillLineInfo(i)
		if skillName and not isHeader then
			local prof = C.PROFESSION_BY_NAME[skillName]
			if prof then
				tinsert(found, prof.id)
				if #found >= 2 then break end
			end
		end
	end
	return found[1], found[2]
end

function Roster:UpdateSelf()
	local guild = GuildInfo:GetGuildData()
	if not guild then return end
	local myName = UnitName("player")
	if not myName then return end

	local m = guild.members[myName]
	local _, classFile = UnitClass("player")
	m.classFile = classFile or m.classFile
	m.class = m.class or UnitClass("player")
	m.level = UnitLevel("player") or m.level
	m.online = true
	m.lastSeen = time()
	m.inGuild = IsInGuild() and true or m.inGuild

	local auto = GuildInfo.db.profile.autoDetect

	-- Talente
	local numGroups = GetNumTalentGroups and GetNumTalentGroups() or 1
	local spec1 = DetectSpecForGroup(classFile, 1)
	local spec2 = numGroups >= 2 and DetectSpecForGroup(classFile, 2) or nil
	if auto then
		if spec1 then m.mainSpec = spec1 end
		if numGroups >= 2 then m.offSpec = spec2 end
	else
		if not m.mainSpec and spec1 then m.mainSpec = spec1 end
		if not m.offSpec and spec2 then m.offSpec = spec2 end
	end

	-- Berufe
	local p1, p2 = DetectProfessions()
	if auto then
		m.prof1, m.prof2 = p1, p2
	else
		if not m.prof1 and p1 then m.prof1 = p1 end
		if not m.prof2 and p2 then m.prof2 = p2 end
	end

	-- Eigene Daten an die Gilde melden, falls sich etwas geändert hat
	local sig = table.concat({ tostring(m.mainSpec), tostring(m.offSpec), tostring(m.prof1), tostring(m.prof2) }, ":")
	if sig ~= self.lastSelfSig then
		self.lastSelfSig = sig
		if GuildInfo.Sync then
			GuildInfo.Sync:QueueSelf()
		end
	end
end

-------------------------------------------------------------------------------
-- Main / Twink
-------------------------------------------------------------------------------
function Roster:ValidateLinks()
	local guild = GuildInfo:GetGuildData()
	if not guild then return end
	for name, m in pairs(guild.members) do
		if m.mainOf then
			local main = rawget(guild.members, m.mainOf)
			if not main or not main.isMain or m.mainOf == name then
				m.mainOf = nil
			end
		end
		if m.isMain and m.mainOf then
			m.mainOf = nil
		end
	end
end

function Roster:SetMain(name, isMain)
	local guild = GuildInfo:GetGuildData()
	if not guild or not name then return end
	local m = guild.members[name]
	if isMain then
		m.isMain = true
		m.mainOf = nil
	else
		m.isMain = false
		-- Alle Twinks dieses Mains lösen
		for _, other in pairs(guild.members) do
			if other.mainOf == name then other.mainOf = nil end
		end
	end
end

function Roster:SetMainOf(name, mainName)
	local guild = GuildInfo:GetGuildData()
	if not guild or not name then return end
	local m = guild.members[name]
	if not mainName or mainName == "" or mainName == name then
		m.mainOf = nil
		return
	end
	local main = guild.members[mainName]
	if not main.isMain then
		main.isMain = true
		main.mainOf = nil
	end
	m.isMain = false
	m.mainOf = mainName
	-- Falls dieser Char selbst Main war: seine Twinks an den neuen Main hängen
	for _, other in pairs(guild.members) do
		if other.mainOf == name then other.mainOf = mainName end
	end
end

-------------------------------------------------------------------------------
-- Automatische Erkennung anhand von Rang und Notizen
-------------------------------------------------------------------------------
-- Ränge, die (case-insensitive) eines dieser Wörter enthalten, gelten als Twink-Rang
local TWINK_RANK_KEYWORDS = { "twink" }

local function IsTwinkRank(rank)
	if not rank or rank == "" then return false end
	local lower = strlower(rank)
	for _, kw in ipairs(TWINK_RANK_KEYWORDS) do
		if lower:find(kw, 1, true) then return true end
	end
	return false
end

-- Buchstaben (ASCII) und alle Mehrbyte-Zeichen (UTF-8, z.B. Umlaute) gelten als Namensbestandteil
local function IsNameByte(b)
	if not b then return false end
	return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b >= 128
end

-- Prüft, ob `word` als eigenständiges Wort in `text` vorkommt (beide bereits kleingeschrieben)
local function ContainsWord(text, word)
	local start = 1
	while true do
		local s, e = text:find(word, start, true)
		if not s then return false end
		if not IsNameByte(text:byte(s - 1)) and not IsNameByte(text:byte(e + 1)) then
			return true
		end
		start = s + 1
	end
end

-- Löst einen in einer Notiz gefundenen Namen auf den zugehörigen Main auf.
-- Main-Rang -> der Name selbst; Twink-Rang mit gültiger Zuordnung -> dessen Main; sonst nil.
local function ResolveToMain(guild, candidate, selfName, twinkRank)
	if candidate == selfName then return nil end
	if twinkRank[candidate] == false then return candidate end
	if twinkRank[candidate] == true then
		local c = rawget(guild.members, candidate)
		local main = c and c.mainOf
		if main and main ~= selfName and twinkRank[main] == false then
			return main
		end
	end
	return nil
end

-- Sucht in Gilden- und Offiziersnotiz nach Namen aktueller Mitglieder.
-- Liefert den Main nur, wenn alle Treffer eindeutig auf denselben Main zeigen.
local function FindMainInNotes(guild, name, m, twinkRank, lowerNames)
	for _, text in ipairs({ m.note, m.officerNote }) do
		if text and text ~= "" then
			local lowerText = strlower(text)
			local found, count = nil, 0
			for candidate, lowerCandidate in pairs(lowerNames) do
				if candidate ~= name and ContainsWord(lowerText, lowerCandidate) then
					local main = ResolveToMain(guild, candidate, name, twinkRank)
					if main and main ~= found then
						found = main
						count = count + 1
					end
				end
			end
			if count == 1 then return found end
			if count > 1 then return nil end -- mehrdeutig
		end
	end
	return nil
end

-- Führt die Erkennung für alle aktuellen Mitglieder durch.
-- Rückgabe: { mains = n, twinks = n, changes = n, unresolved = { name, ... }, changed = { name, ... } }
function Roster:AutoDetectMainsAndTwinks()
	local stats = { mains = 0, twinks = 0, changes = 0, unresolved = {}, changed = {} }
	local guild = GuildInfo:GetGuildData()
	if not guild then return stats end

	-- Zustand vor der Erkennung merken, um geänderte Einträge zu ermitteln
	local before = {}
	for name, m in pairs(guild.members) do
		before[name] = (m.isMain and "1" or "0") .. (m.mainOf or "")
	end

	-- Rang-Klassifikation aller aktuellen Mitglieder (true = Twink-Rang, false = Main-Rang)
	local twinkRank, lowerNames = {}, {}
	for name, m in pairs(guild.members) do
		if m.inGuild then
			twinkRank[name] = IsTwinkRank(m.rank)
			lowerNames[name] = strlower(name)
		end
	end

	-- 1) Alle Chars ohne Twink-Rang sind Mains
	for name, isTwink in pairs(twinkRank) do
		if not isTwink then
			local m = guild.members[name]
			if not m.isMain or m.mainOf then
				stats.changes = stats.changes + 1
			end
			self:SetMain(name, true)
			stats.mains = stats.mains + 1
		end
	end

	-- 2) Twinks über Notizen zuordnen; mehrere Durchläufe, damit Verweise auf
	--    andere Twinks aufgelöst werden können, sobald deren Main bekannt ist
	local pending = {}
	for name, isTwink in pairs(twinkRank) do
		if isTwink then pending[name] = true end
	end

	local progress = true
	while progress do
		progress = false
		for name in pairs(pending) do
			local m = guild.members[name]
			local main = FindMainInNotes(guild, name, m, twinkRank, lowerNames)
			if main then
				if m.mainOf ~= main or m.isMain then
					stats.changes = stats.changes + 1
				end
				self:SetMainOf(name, main)
				stats.twinks = stats.twinks + 1
				pending[name] = nil
				progress = true
			end
		end
	end

	-- Nicht erkannte Twinks melden, sofern sie nicht bereits gültig zugeordnet sind
	for name in pairs(pending) do
		local m = guild.members[name]
		if not (m.mainOf and twinkRank[m.mainOf] == false) then
			tinsert(stats.unresolved, name)
		end
	end
	tsort(stats.unresolved)

	self:ValidateLinks()

	for name, m in pairs(guild.members) do
		local after = (m.isMain and "1" or "0") .. (m.mainOf or "")
		if before[name] ~= after then
			tinsert(stats.changed, name)
		end
	end
	tsort(stats.changed)
	return stats
end

function Roster:GetMains(includeFormer)
	local guild = GuildInfo:GetGuildData()
	local list = {}
	if not guild then return list end
	for name, m in pairs(guild.members) do
		if m.isMain and (includeFormer or m.inGuild) then
			tinsert(list, name)
		end
	end
	tsort(list)
	return list
end

function Roster:GetTwinks(mainName, includeFormer)
	local guild = GuildInfo:GetGuildData()
	local list = {}
	if not guild or not mainName then return list end
	for name, m in pairs(guild.members) do
		if m.mainOf == mainName and (includeFormer or m.inGuild) then
			tinsert(list, name)
		end
	end
	tsort(list)
	return list
end

-- Liefert den "Anker"-Namen für die Gruppierung (Main-Name, oder eigener Name)
function Roster:GetGroupKey(name, m)
	if m.mainOf then return m.mainOf end
	return name
end

-------------------------------------------------------------------------------
-- Gefilterte und sortierte Liste
-- opts = { search=, classFile=, role=, onlineOnly=, showFormer=, sortKey=, sortAsc=, groupTwinks= }
-------------------------------------------------------------------------------
local function SpecRole(specId)
	local spec = C.GetSpec(specId)
	return spec and spec.role or nil
end

local function MatchesFilter(name, m, opts)
	if not opts.showFormer and not m.inGuild then return false end
	if opts.onlineOnly and not m.online then return false end
	if opts.classFile and opts.classFile ~= "" and m.classFile ~= opts.classFile then return false end
	if opts.role and opts.role ~= "" then
		if SpecRole(m.mainSpec) ~= opts.role and SpecRole(m.offSpec) ~= opts.role then return false end
	end
	if opts.search and opts.search ~= "" then
		local s = opts.search:lower()
		local hay = (name .. " " .. (m.class or "") .. " " .. (m.rank or "") .. " " ..
			C.GetSpecName(m.mainSpec) .. " " .. C.GetSpecName(m.offSpec) .. " " ..
			C.GetProfessionName(m.prof1) .. " " .. C.GetProfessionName(m.prof2) .. " " ..
			(m.note or "") .. " " .. (m.userNote or "") .. " " .. (m.mainOf or "")):lower()
		if not hay:find(s, 1, true) then return false end
	end
	return true
end

local sortValue = {
	name    = function(e) return e.name:lower() end,
	level   = function(e) return e.data.level or 0 end,
	class   = function(e) return C.GetClassName(e.data.classFile):lower() end,
	rank    = function(e) return e.data.rankIndex or 99 end,
	mainSpec = function(e) return C.GetSpecName(e.data.mainSpec):lower() end,
	offSpec = function(e) return C.GetSpecName(e.data.offSpec):lower() end,
	prof1   = function(e) return C.GetProfessionName(e.data.prof1):lower() end,
	prof2   = function(e) return C.GetProfessionName(e.data.prof2):lower() end,
	main    = function(e)
		if e.data.isMain then return "0" .. e.name:lower() end
		if e.data.mainOf then return "1" .. e.data.mainOf:lower() .. e.name:lower() end
		return "2" .. e.name:lower()
	end,
	online  = function(e) return e.data.online and 0 or 1 end,
}

local function MakeComparator(sortKey, sortAsc)
	local getter = sortValue[sortKey] or sortValue.name
	return function(a, b)
		-- Online immer vor Offline, danach gewählte Sortierung
		local oa, ob = a.data.online and true or false, b.data.online and true or false
		if oa ~= ob then return oa end
		local va, vb = getter(a), getter(b)
		if va == vb then
			return a.name:lower() < b.name:lower()
		end
		if sortAsc then return va < vb else return va > vb end
	end
end

function Roster:GetFilteredList(opts)
	local guild = GuildInfo:GetGuildData()
	local list = {}
	if not guild then return list end

	for name, m in pairs(guild.members) do
		if MatchesFilter(name, m, opts) then
			tinsert(list, { name = name, data = m })
		end
	end

	if not opts.groupTwinks then
		tsort(list, MakeComparator(opts.sortKey, opts.sortAsc))
		return list
	end

	-- Gruppierung: Mains (bzw. ungebundene Chars) sortiert, Twinks darunter eingerückt
	local byName = {}
	for _, e in ipairs(list) do byName[e.name] = e end

	local roots, twinksOf = {}, {}
	for _, e in ipairs(list) do
		local mainName = e.data.mainOf
		if mainName and byName[mainName] then
			twinksOf[mainName] = twinksOf[mainName] or {}
			tinsert(twinksOf[mainName], e)
		else
			tinsert(roots, e)
		end
	end
	local cmp = MakeComparator(opts.sortKey, opts.sortAsc)
	tsort(roots, cmp)

	local result = {}
	for _, root in ipairs(roots) do
		root.indent = 0
		tinsert(result, root)
		local tw = twinksOf[root.name]
		if tw then
			tsort(tw, cmp)
			for _, t in ipairs(tw) do
				t.indent = 1
				tinsert(result, t)
			end
		end
	end
	return result
end

function Roster:GetCounts()
	local guild = GuildInfo:GetGuildData()
	local total, online = 0, 0
	if not guild then return 0, 0 end
	for _, m in pairs(guild.members) do
		if m.inGuild then
			total = total + 1
			if m.online then online = online + 1 end
		end
	end
	return total, online
end
