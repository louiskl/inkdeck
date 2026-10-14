#!/usr/bin/env python3
"""Unit tests for pure-Lua helpers (time zones, ICS, RSS, JSON, layout)."""
import os
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = os.path.join(ROOT, "inkdeck.koplugin")

TESTS = r'''
local U = require("inkdeck/util")
local json = require("inkdeck/json")
local L = require("inkdeck/layout")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- time zone: Berlin summer (UTC+2) and winter (UTC+1)
U.timezone = "Europe/Berlin"
local summer = U.timegm({ year = 2026, month = 10, day = 14, hour = 17, min = 46 })
eq(U.hhmm(summer), "19:46", "CEST")
local winter = U.timegm({ year = 2026, month = 12, day = 24, hour = 17, min = 0 })
eq(U.hhmm(winter), "18:00", "CET")
-- DST switch: 2026-10-25 01:00 UTC
eq(U.hhmm(U.timegm({ year = 2026, month = 10, day = 25, hour = 0, min = 30 })), "02:30", "before switch")
eq(U.hhmm(U.timegm({ year = 2026, month = 10, day = 25, hour = 1, min = 30 })), "02:30", "after switch")
U.timezone = "America/New_York"
eq(U.hhmm(U.timegm({ year = 2026, month = 7, day = 1, hour = 16, min = 0 })), "12:00", "EDT")
eq(U.hhmm(U.timegm({ year = 2026, month = 1, day = 15, hour = 17, min = 0 })), "12:00", "EST")
U.timezone = "+05:30"
eq(U.hhmm(U.timegm({ year = 2026, month = 1, day = 15, hour = 0, min = 0 })), "05:30", "fixed offset")
U.timezone = "Europe/Berlin"
-- local epoch roundtrip
local e = U.localEpoch({ year = 2026, month = 7, day = 1, hour = 9, min = 15 })
eq(U.hhmm(e), "09:15", "roundtrip")
eq(U.weekday(2026, 10, 14), 3, "Wednesday")
eq(U.isoWeek(summer), 42, "ISO week")
local I18N = require("inkdeck/i18n")
I18N.set("de_DE")
eq(U.dateLong(summer), "Mittwoch, 14. Oktober", "dateLong de")
eq(U.relDay(summer, summer), "Heute", "relDay de")
I18N.set("en")
eq(U.dateLong(summer), "Wednesday, October 14", "dateLong en")
eq(U.dateShort(summer), "Wed 14 Oct", "dateShort en")
U.clock12 = true
eq(U.hhmm(summer), "7:46 PM", "12h clock")
U.clock12 = false
I18N.set("de")
eq(U.timegm({ year = 2026, month = 14, day = 1 }), U.timegm({ year = 2027, month = 2, day = 1 }), "month overflow")

-- ICS: UTC time, all-day, weekly RRULE with BYDAY + EXDATE, floating time
local ics = table.concat({
  "BEGIN:VCALENDAR",
  "BEGIN:VEVENT", "SUMMARY:Meeting", "DTSTART:20261015T080000Z", "DTEND:20261015T090000Z", "END:VEVENT",
  "BEGIN:VEVENT", "SUMMARY:Feiertag", "DTSTART;VALUE=DATE:20261016", "END:VEVENT",
  "BEGIN:VEVENT", "SUMMARY:Vorlesung\\, Teil 2", "DTSTART;TZID=Europe/Berlin:20261005T100000",
  "DTEND;TZID=Europe/Berlin:20261005T113000", "RRULE:FREQ=WEEKLY;BYDAY=MO,TH;UNTIL=20261231T000000Z",
  "EXDATE;TZID=Europe/Berlin:20261019T100000", "END:VEVENT",
  "BEGIN:VEVENT", "SUMMARY:Abgesagt", "STATUS:CANCELLED", "DTSTART:20261015T100000Z", "END:VEVENT",
  "BEGIN:VEVENT", "SUMMARY:Lange", " Zeile", "DTSTART:20261020T120000", "DURATION:PT2H", "END:VEVENT",
  "END:VCALENDAR" }, "\r\n")
local from = U.localEpoch({ year = 2026, month = 10, day = 14, hour = 0 })
local to = from + 10 * 86400
local evs = U.parseICS(ics, from, to)
local titles = {}
for _, ev in ipairs(evs) do titles[#titles + 1] = U.dateShort(ev.start) .. " " .. (ev.all_day and "ganz" or U.hhmm(ev.start)) .. " " .. ev.title end
local got = table.concat(titles, " | ")
I18N.set("de")
local want = "Do 15.10. 10:00 Meeting | Do 15.10. 10:00 Vorlesung, Teil 2 | Fr 16.10. ganz Feiertag | Do 22.10. 10:00 Vorlesung, Teil 2 | Di 20.10. 12:00 LangeZeile"
-- sort check (by start)
table.sort(titles)
eq(#evs, 5, "event count (" .. got .. ")")
assert(got:find("Mo 19.10.") == nil, "EXDATE ignored: " .. got)
assert(got:find("Abgesagt") == nil, "cancelled shown")
assert(got:find("LangeZeile"), "unfolding failed: " .. got)
for _, ev in ipairs(evs) do if ev.title == "LangeZeile" then eq(ev["end"] - ev.start, 7200, "duration") end end

-- RSS + entities
local items, ft = U.parseFeed([==[<rss><channel><title>Feed &amp; Co</title><item><title><![CDATA[Hallo &amp; Tschüss]]></title><description>&lt;p&gt;Text&lt;/p&gt;</description></item></channel></rss>]==])
eq(ft, "Feed & Co", "feed title")
eq(items[1].title, "Hallo & Tschüss", "cdata title")
eq(items[1].text, "Text", "encoded html")

-- JSON roundtrip incl. unicode escapes
local obj = json.decode('{"a":[1,2.5,true,null,"\\u00e4\\ud83d\\ude00"],"b":{"c":"x\\ny"}}')
eq(obj.a[2], 2.5, "float")
eq(obj.a[5], "ä😀", "unicode")
eq(obj.a[4], json.null, "null")
local back = json.decode(json.encode(obj))
eq(back.b.c, "x\ny", "roundtrip")
eq(json.encode(json.decode("[]")), "[]", "empty array stays array")

-- layout packing: default home page in portrait
local items2 = { { size = "w" }, { size = "s" }, { size = "t" }, { size = "s" }, { size = "w" } }
local placed, overflow = L.pack(items2, 2, 4)
eq(#placed, 5, "all placed"); eq(#overflow, 0, "no overflow")
eq(placed[3].col, 1); eq(placed[3].row, 1); eq(placed[4].row, 2); eq(placed[5].row, 3)
-- landscape 4x2
placed = L.pack(items2, 4, 2)
eq(#placed, 5, "landscape all placed")
-- overflow
local _, of = L.pack({ { size = "l" }, { size = "l" }, { size = "l" } }, 2, 4)
eq(#of, 1, "overflow detected")
-- navigation
L.rects(placed, 4, 2, { x = 0, y = 40, w = 800, h = 560 }, 10)
local r = L.navigate(placed, 1, "Right")
eq(r, 2, "right from clock -> weather")
-- every T()/F() string must have a German translation
local missing = I18N.missing("de", KEYS)
assert(#missing == 0, "missing German translations: " .. table.concat(missing, " | "))
print("all util tests passed (" .. #KEYS .. " strings translated)")
'''

lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'package.path = "{PLUGIN}/?.lua;" .. package.path')
import re, glob
keys = set()
for f in glob.glob(os.path.join(PLUGIN, "**", "*.lua"), recursive=True):
    src = open(f).read()
    for m in re.finditer(r'(?<![\w.])[TF]\("((?:[^"\\]|\\.)*)"', src):
        keys.add(m.group(1))
    for m in re.finditer(r'F\([^"\n]*?and "((?:[^"\\]|\\.)*)" or "((?:[^"\\]|\\.)*)"', src):
        keys.update(m.groups())
    m = re.search(r'name = "([^"]+)",', src)
    if "/widgets/" in f and m and not f.endswith("base.lua"):
        keys.add(m.group(1))
# static check: modules using T()/F() must import them
for f in glob.glob(os.path.join(PLUGIN, "**", "*.lua"), recursive=True):
    if f.endswith("i18n.lua"):
        continue
    src = open(f).read()
    for name in ("T", "F"):
        if re.search(r'(?<![\w.])' + name + r'\("', src) and not re.search(r'^local ' + name + ' = ', src, re.M):
            raise SystemExit(f"{f}: uses {name}() without importing it")
tbl = lua.table_from([k.encode().decode("unicode_escape").encode("latin-1").decode("utf-8") for k in sorted(keys)])
lua.globals().KEYS = tbl
lua.execute(TESTS)
