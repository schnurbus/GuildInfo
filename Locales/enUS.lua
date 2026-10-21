local L = LibStub("AceLocale-3.0"):NewLocale("GuildInfo", "enUS", true)
if not L then return end

-- General
L["GuildInfo"] = true
L["Not in a guild"] = true
L["Opens the GuildInfo window"] = true
L["%d members (%d shown), %d online"] = true
L["Refresh"] = true
L["Roster refresh requested."] = true
L["Loaded. Type /gi to open the window."] = true

-- Tabs
L["Members"] = true
L["Mains & Alts"] = true
L["Options"] = true

-- Options / Sync
L["General"] = true
L["Synchronization"] = true
L["Sync status"] = true
L["Enable synchronization with guild members"] = true
L["Share my own specs and professions with the whole guild"] = true
L["Share edits with ranks up to and including"] = true
L["Sync now"] = true
L["Sync requested."] = true
L["Edits (main/alt assignment, notes, entries of other members) are only exchanged with online members whose rank is within this limit. All participants should use the same rank limit. Your own specs and professions are shared with everyone."] = true
L["Your rank (%s) is authorized to exchange edits."] = true
L["Your rank (%s) is not authorized to exchange edits."] = true
L["Last sync: %d entries from %s at %s"] = true
L["Known members with GuildInfo: %d"] = true
L["authorized"] = true
L["not authorized"] = true
L["sync disabled"] = true
L["Sync: %d entries received from %s."] = true
L["Last edited by %s on %s"] = true

-- Filters
L["Search"] = true
L["Class"] = true
L["Role"] = true
L["All classes"] = true
L["All roles"] = true
L["Online only"] = true
L["Show former members"] = true
L["Group alts under main"] = true

-- Columns
L["Name"] = true
L["Level"] = true
L["Rank"] = true
L["Main Spec"] = true
L["Off Spec"] = true
L["Profession 1"] = true
L["Profession 2"] = true
L["Main / Alt"] = true

-- Roles
L["Tank"] = true
L["Healer"] = true
L["DPS"] = true
L["TANK_SHORT"] = "T"
L["HEAL_SHORT"] = "H"
L["DPS_SHORT"] = "D"

-- Main/Alt
L["Main"] = true
L["Alt of %s"] = true
L["Is main character"] = true
L["Alt of"] = true
L["- none -"] = true
L["Unassigned"] = true
L["Alts"] = true
L["Former member"] = true
L["Auto-detect mains and alts from ranks and notes"] = true
L["Auto-detect: %d mains, %d alts assigned, %d alts unresolved (%d changes)."] = true
L["Alts without identifiable main: %s"] = true

-- Detail panel
L["Details"] = true
L["Select a member from the list."] = true
L["Note"] = true
L["Save"] = true
L["Reset"] = true
L["Saved: %s"] = true
L["Auto-detect my own specs and professions"] = true
L["Offline"] = true
L["Online"] = true
L["Last seen: %s"] = true
L["Zone: %s"] = true
L["Guild note: %s"] = true
L["Officer note: %s"] = true
L["Unknown"] = true
L["Click to edit"] = true
L["Sort by %s"] = true

-- Specs
L["Blood"] = true
L["Frost"] = true
L["Unholy"] = true
L["Balance"] = true
L["Feral (Bear)"] = true
L["Feral (Cat)"] = true
L["Restoration"] = true
L["Beast Mastery"] = true
L["Marksmanship"] = true
L["Survival"] = true
L["Arcane"] = true
L["Fire"] = true
L["Holy"] = true
L["Protection"] = true
L["Retribution"] = true
L["Discipline"] = true
L["Shadow"] = true
L["Assassination"] = true
L["Combat"] = true
L["Subtlety"] = true
L["Elemental"] = true
L["Enhancement"] = true
L["Affliction"] = true
L["Demonology"] = true
L["Destruction"] = true
L["Arms"] = true
L["Fury"] = true
-- Talent used to distinguish bear from cat (must match in-game talent name)
L["Protector of the Pack"] = true

-- Professions (names must match the in-game skill line names for auto-detection)
L["Alchemy"] = true
L["Blacksmithing"] = true
L["Enchanting"] = true
L["Engineering"] = true
L["Herbalism"] = true
L["Inscription"] = true
L["Jewelcrafting"] = true
L["Leatherworking"] = true
L["Mining"] = true
L["Skinning"] = true
L["Tailoring"] = true
