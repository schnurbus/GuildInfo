--[[-----------------------------------------------------------------------------
GuildInfo - Constants
Klassen, Talentspecs, Rollen und Berufe für WoW 3.3.5a
-------------------------------------------------------------------------------]]
local ADDON_NAME, ns = ...
-- Fallback, falls der Client keinen privaten Namensraum per Vararg bereitstellt
if type(ns) ~= "table" then
	ns = _G.GuildInfoNS or {}
	_G.GuildInfoNS = ns
end
local L = LibStub("AceLocale-3.0"):GetLocale("GuildInfo")

ns.Const = {}
local C = ns.Const

-------------------------------------------------------------------------------
-- Rollen
-------------------------------------------------------------------------------
C.ROLE_TANK = "TANK"
C.ROLE_HEAL = "HEAL"
C.ROLE_DPS  = "DPS"

C.ROLES = {
	{ id = C.ROLE_TANK, name = L["Tank"],   short = L["TANK_SHORT"], icon = "Interface\\Icons\\Ability_Defend",          color = { 0.60, 0.70, 1.00 } },
	{ id = C.ROLE_HEAL, name = L["Healer"], short = L["HEAL_SHORT"], icon = "Interface\\Icons\\Spell_Holy_Renew",        color = { 0.50, 1.00, 0.50 } },
	{ id = C.ROLE_DPS,  name = L["DPS"],    short = L["DPS_SHORT"],  icon = "Interface\\Icons\\INV_Sword_27",            color = { 1.00, 0.55, 0.45 } },
}
C.ROLE_BY_ID = {}
for _, role in ipairs(C.ROLES) do C.ROLE_BY_ID[role.id] = role end

-------------------------------------------------------------------------------
-- Klassen (Reihenfolge wie im Spiel 3.3.5a)
-------------------------------------------------------------------------------
C.CLASS_ORDER = {
	"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
	"DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

-- Texturkoordinaten auf Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes
C.CLASS_ICON_TCOORDS = {
	WARRIOR     = { 0.00, 0.25, 0.00, 0.25 },
	MAGE        = { 0.25, 0.50, 0.00, 0.25 },
	ROGUE       = { 0.50, 0.75, 0.00, 0.25 },
	DRUID       = { 0.75, 1.00, 0.00, 0.25 },
	HUNTER      = { 0.00, 0.25, 0.25, 0.50 },
	SHAMAN      = { 0.25, 0.50, 0.25, 0.50 },
	PRIEST      = { 0.50, 0.75, 0.25, 0.50 },
	WARLOCK     = { 0.75, 1.00, 0.25, 0.50 },
	PALADIN     = { 0.00, 0.25, 0.50, 0.75 },
	DEATHKNIGHT = { 0.25, 0.50, 0.50, 0.75 },
}
C.CLASS_ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

-- Lokalisierte Klassennamen (LOCALIZED_CLASS_NAMES_MALE existiert in 3.3.5a)
function C.GetClassName(classFile)
	if not classFile then return L["Unknown"] end
	local names = LOCALIZED_CLASS_NAMES_MALE
	return (names and names[classFile]) or classFile
end

function C.GetClassColor(classFile)
	local col = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if col then return col.r, col.g, col.b end
	return 0.8, 0.8, 0.8
end

function C.GetClassColorHex(classFile)
	local r, g, b = C.GetClassColor(classFile)
	return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

-------------------------------------------------------------------------------
-- Talentspecs
-- id        eindeutige Kennung (wird in der DB gespeichert)
-- tab       Index des Talentbaums (1-3) für die Auto-Erkennung
-- role      Rolle
-- tankTalent  optional: Talentname, der (mit >= 1 Punkt) diese Variante kennzeichnet
--             (Druide: Bär vs. Katze im selben Baum)
-------------------------------------------------------------------------------
C.SPECS = {
	DEATHKNIGHT = {
		{ id = "DK_BLOOD",  name = L["Blood"],  tab = 1, role = C.ROLE_TANK, icon = "Interface\\Icons\\Spell_Deathknight_BloodPresence" },
		{ id = "DK_FROST",  name = L["Frost"],  tab = 2, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Spell_Deathknight_FrostPresence" },
		{ id = "DK_UNHOLY", name = L["Unholy"], tab = 3, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Spell_Deathknight_UnholyPresence" },
	},
	DRUID = {
		{ id = "DRUID_BALANCE", name = L["Balance"],      tab = 1, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Spell_Nature_StarFall" },
		{ id = "DRUID_BEAR",    name = L["Feral (Bear)"], tab = 2, role = C.ROLE_TANK, icon = "Interface\\Icons\\Ability_Racial_BearForm", tankTalent = L["Protector of the Pack"] },
		{ id = "DRUID_CAT",     name = L["Feral (Cat)"],  tab = 2, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Ability_Druid_CatForm" },
		{ id = "DRUID_RESTO",   name = L["Restoration"],  tab = 3, role = C.ROLE_HEAL, icon = "Interface\\Icons\\Spell_Nature_HealingTouch" },
	},
	HUNTER = {
		{ id = "HUNTER_BM",   name = L["Beast Mastery"], tab = 1, role = C.ROLE_DPS, icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
		{ id = "HUNTER_MM",   name = L["Marksmanship"],  tab = 2, role = C.ROLE_DPS, icon = "Interface\\Icons\\Ability_Marksmanship" },
		{ id = "HUNTER_SURV", name = L["Survival"],      tab = 3, role = C.ROLE_DPS, icon = "Interface\\Icons\\Ability_Hunter_SwiftStrike" },
	},
	MAGE = {
		{ id = "MAGE_ARCANE", name = L["Arcane"], tab = 1, role = C.ROLE_DPS, icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
		{ id = "MAGE_FIRE",   name = L["Fire"],   tab = 2, role = C.ROLE_DPS, icon = "Interface\\Icons\\Spell_Fire_FireBolt02" },
		{ id = "MAGE_FROST",  name = L["Frost"],  tab = 3, role = C.ROLE_DPS, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
	},
	PALADIN = {
		{ id = "PALA_HOLY", name = L["Holy"],        tab = 1, role = C.ROLE_HEAL, icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
		{ id = "PALA_PROT", name = L["Protection"],  tab = 2, role = C.ROLE_TANK, icon = "Interface\\Icons\\Spell_Holy_DevotionAura" },
		{ id = "PALA_RET",  name = L["Retribution"], tab = 3, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Spell_Holy_AuraOfLight" },
	},
	PRIEST = {
		{ id = "PRIEST_DISC",   name = L["Discipline"], tab = 1, role = C.ROLE_HEAL, icon = "Interface\\Icons\\Spell_Holy_WordFortitude" },
		{ id = "PRIEST_HOLY",   name = L["Holy"],       tab = 2, role = C.ROLE_HEAL, icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit" },
		{ id = "PRIEST_SHADOW", name = L["Shadow"],     tab = 3, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
	},
	ROGUE = {
		{ id = "ROGUE_ASSA",   name = L["Assassination"], tab = 1, role = C.ROLE_DPS, icon = "Interface\\Icons\\Ability_Rogue_Eviscerate" },
		{ id = "ROGUE_COMBAT", name = L["Combat"],        tab = 2, role = C.ROLE_DPS, icon = "Interface\\Icons\\Ability_BackStab" },
		{ id = "ROGUE_SUB",    name = L["Subtlety"],      tab = 3, role = C.ROLE_DPS, icon = "Interface\\Icons\\Ability_Stealth" },
	},
	SHAMAN = {
		{ id = "SHAMAN_ELE",   name = L["Elemental"],   tab = 1, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Spell_Nature_Lightning" },
		{ id = "SHAMAN_ENH",   name = L["Enhancement"], tab = 2, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Spell_Nature_LightningShield" },
		{ id = "SHAMAN_RESTO", name = L["Restoration"], tab = 3, role = C.ROLE_HEAL, icon = "Interface\\Icons\\Spell_Nature_MagicImmunity" },
	},
	WARLOCK = {
		{ id = "LOCK_AFFLI", name = L["Affliction"],  tab = 1, role = C.ROLE_DPS, icon = "Interface\\Icons\\Spell_Shadow_DeathCoil" },
		{ id = "LOCK_DEMO",  name = L["Demonology"],  tab = 2, role = C.ROLE_DPS, icon = "Interface\\Icons\\Spell_Shadow_Metamorphosis" },
		{ id = "LOCK_DESTRO", name = L["Destruction"], tab = 3, role = C.ROLE_DPS, icon = "Interface\\Icons\\Spell_Shadow_RainOfFire" },
	},
	WARRIOR = {
		{ id = "WARR_ARMS", name = L["Arms"],       tab = 1, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Ability_Warrior_SavageBlow" },
		{ id = "WARR_FURY", name = L["Fury"],       tab = 2, role = C.ROLE_DPS,  icon = "Interface\\Icons\\Ability_Warrior_InnerRage" },
		{ id = "WARR_PROT", name = L["Protection"], tab = 3, role = C.ROLE_TANK, icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance" },
	},
}

C.SPEC_BY_ID = {}
for classFile, list in pairs(C.SPECS) do
	for _, spec in ipairs(list) do
		spec.classFile = classFile
		C.SPEC_BY_ID[spec.id] = spec
	end
end

function C.GetSpec(id)
	return id and C.SPEC_BY_ID[id] or nil
end

function C.GetSpecName(id)
	local spec = C.GetSpec(id)
	return spec and spec.name or ""
end

function C.GetSpecsForClass(classFile)
	return classFile and C.SPECS[classFile] or nil
end

-------------------------------------------------------------------------------
-- Berufe (Hauptberufe in 3.3.5a)
-------------------------------------------------------------------------------
C.PROFESSIONS = {
	{ id = "ALCHEMY",        name = L["Alchemy"],        icon = "Interface\\Icons\\Trade_Alchemy" },
	{ id = "BLACKSMITHING",  name = L["Blacksmithing"],  icon = "Interface\\Icons\\Trade_BlackSmithing" },
	{ id = "ENCHANTING",     name = L["Enchanting"],     icon = "Interface\\Icons\\Trade_Engraving" },
	{ id = "ENGINEERING",    name = L["Engineering"],    icon = "Interface\\Icons\\Trade_Engineering" },
	{ id = "HERBALISM",      name = L["Herbalism"],      icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow" },
	{ id = "INSCRIPTION",    name = L["Inscription"],    icon = "Interface\\Icons\\INV_Inscription_Tradeskill01" },
	{ id = "JEWELCRAFTING",  name = L["Jewelcrafting"],  icon = "Interface\\Icons\\INV_Misc_Gem_01" },
	{ id = "LEATHERWORKING", name = L["Leatherworking"], icon = "Interface\\Icons\\Trade_LeatherWorking" },
	{ id = "MINING",         name = L["Mining"],         icon = "Interface\\Icons\\Trade_Mining" },
	{ id = "SKINNING",       name = L["Skinning"],       icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
	{ id = "TAILORING",      name = L["Tailoring"],      icon = "Interface\\Icons\\Trade_Tailoring" },
}

C.PROFESSION_BY_ID = {}
C.PROFESSION_BY_NAME = {}
for _, prof in ipairs(C.PROFESSIONS) do
	C.PROFESSION_BY_ID[prof.id] = prof
	C.PROFESSION_BY_NAME[prof.name] = prof
end

function C.GetProfession(id)
	return id and C.PROFESSION_BY_ID[id] or nil
end

function C.GetProfessionName(id)
	local prof = C.GetProfession(id)
	return prof and prof.name or ""
end

-------------------------------------------------------------------------------
-- Hilfsfunktionen
-------------------------------------------------------------------------------
function C.ColorText(text, r, g, b)
	return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text or "")
end

function C.IconText(texture, size, ...)
	size = size or 14
	local n = select("#", ...)
	if n == 4 then
		-- Texcoords in Prozent (0-1) -> Pixel auf 256er Basis (Format: |Tpath:h:w:x:y:dimx:dimy:l:r:t:b|t)
		local l, r, t, b = ...
		return string.format("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t", texture, size, size, l * 256, r * 256, t * 256, b * 256)
	end
	return string.format("|T%s:%d:%d|t", texture, size, size)
end

function C.ClassIconText(classFile, size)
	local tc = classFile and C.CLASS_ICON_TCOORDS[classFile]
	if not tc then return "" end
	return C.IconText(C.CLASS_ICON_TEXTURE, size, tc[1], tc[2], tc[3], tc[4])
end
