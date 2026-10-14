-- Tiny translation layer. English is the source language; add a table below for more languages.
-- Usage:  local T = require("inkdeck/i18n").t   T("Back: close")
--         local F = require("inkdeck/i18n").f   F("%d open", n)
local I = { lang = "en" }

local NAMES = {
    en = {
        DAYS = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" },
        DAYS_SHORT = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" },
        MONTHS = { "January", "February", "March", "April", "May", "June", "July",
            "August", "September", "October", "November", "December" },
        MONTHS_SHORT = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" },
    },
    de = {
        DAYS = { "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag" },
        DAYS_SHORT = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" },
        MONTHS = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli",
            "August", "September", "Oktober", "November", "Dezember" },
        MONTHS_SHORT = { "Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez" },
    },
}

local TRANSLATIONS = {
    de = {
        -- widget names
        ["Clock"] = "Uhr", ["Weather"] = "Wetter", ["Calendar"] = "Kalender", ["News"] = "Nachrichten",
        ["Reminders"] = "Erinnerungen", ["Now Playing"] = "Läuft gerade", ["Media Player"] = "Media Player",
        ["Smart Home"] = "Smart Home", ["Photo frame"] = "Bilderrahmen", ["Countdown"] = "Countdown",
        ["Note"] = "Notiz", ["Spotify"] = "Spotify",
        -- weather conditions
        ["Clear"] = "Klar", ["Mostly clear"] = "Überwiegend klar", ["Partly cloudy"] = "Teils bewölkt",
        ["Overcast"] = "Bewölkt", ["Fog"] = "Nebel", ["Rime fog"] = "Reifnebel",
        ["Light drizzle"] = "Leichter Niesel", ["Drizzle"] = "Niesel", ["Heavy drizzle"] = "Starker Niesel",
        ["Freezing drizzle"] = "Gefr. Niesel", ["Light rain"] = "Leichter Regen", ["Rain"] = "Regen",
        ["Heavy rain"] = "Starker Regen", ["Freezing rain"] = "Eisregen", ["Light snow"] = "Leichter Schnee",
        ["Snow"] = "Schnee", ["Heavy snow"] = "Starker Schnee", ["Snow grains"] = "Schneegriesel",
        ["Showers"] = "Schauer", ["Heavy showers"] = "Starke Schauer", ["Snow showers"] = "Schneeschauer",
        ["Thunderstorm"] = "Gewitter", ["Thunderstorm, hail"] = "Gewitter, Hagel",
        -- Home Assistant states
        ["On"] = "An", ["Off"] = "Aus", ["Open"] = "Offen", ["Closed"] = "Zu", ["Playing"] = "Spielt",
        ["Paused"] = "Pausiert", ["Idle"] = "Bereit", ["Home"] = "Zuhause", ["Away"] = "Weg",
        ["Locked"] = "Zu", ["Unlocked"] = "Offen", ["Run"] = "Start",
        -- general
        ["   ·   Back: close"] = "   ·   Zurück: schließen",
        ["   ·   ◀ ▶ source"] = "   ·   ◀ ▶ Quelle",
        ["%d h ago"] = "vor %d Std.",
        ["%d min ago"] = "vor %d Min.",
        ["%d on"] = "%d an",
        ["%d open"] = "%d offen",
        ["%d today"] = "%d heute",
        ["%s / %s   ·  Rain %s%%"] = "%s / %s   ·  Regen %s%%",
        ["%s / %s  ·  Wind %d km/h"] = "%s / %s  ·  Wind %d km/h",
        ["(No text in this feed)"] = "(Kein Text im Feed)",
        ["+  New reminder …"] = "+  Neue Erinnerung …",
        ["7 DAYS"] = "7 TAGE",
        ["About & folders"] = "Info & Ordner",
        ["Action failed: "] = "Aktion fehlgeschlagen: ",
        ["Add your Last.fm username and API key in the editor."] = "Last.fm-Nutzername und API-Schlüssel im Editor eintragen.",
        ["Agenda"] = "Termine",
        ["All day"] = "Tag",
        ["All done!"] = "Alles erledigt!",
        ["Back: close"] = "Zurück: schließen",
        ["Back: close   ·   Page keys: next widget"] = "Zurück: schließen   ·   Blättern: nächstes Widget",
        ["Bridge unreachable"] = "Bridge nicht erreichbar",
        ["Calendar unavailable"] = "Kalender nicht erreichbar",
        ["Cancel"] = "Abbrechen",
        ["Choose a media_player entity in the editor."] = "Im Editor eine media_player-Entität wählen.",
        ["Configuration:"] = "Konfiguration:",
        ["Controls: the d-pad moves the selection, OK opens a widget, the page keys switch pages, the Menu key opens the InkDeck menu."] =
            "Bedienung: Steuerkreuz bewegt die Auswahl, Mitte öffnet ein Widget, Blättern-Tasten wechseln die Seite, Menü-Taste öffnet das InkDeck-Menü.",
        ["Date missing (YYYY-MM-DD)"] = "Datum fehlt (JJJJ-MM-TT)",
        ["Empty"] = "Leer",
        ["Error: "] = "Fehler: ",
        ["Exit InkDeck"] = "InkDeck beenden",
        ["Feels %s  ·  %s / %s"] = "Gefühlt %s  ·  %s / %s",
        ["Feels like %s"] = "Gefühlt %s",
        ["Hide selection frame"] = "Auswahlrahmen ausblenden",
        ["High %s  ·  Low %s"] = "Max %s  ·  Min %s",
        ["Home Assistant not set up.\nAdd URL and token in the editor."] = "Home Assistant nicht eingerichtet.\nURL und Token im Editor eintragen.",
        ["Home Assistant unreachable"] = "Home Assistant nicht erreichbar",
        ["InkDeck dashboard"] = "InkDeck Dashboard",
        ["InkDeck: config.json is invalid and was ignored."] = "InkDeck: config.json ist fehlerhaft und wird ignoriert.",
        ["Landscape"] = "Querformat",
        ["Last played %s"] = "Zuletzt gehört %s",
        ["Last.fm unavailable"] = "Last.fm nicht erreichbar",
        ["Loading news …"] = "Lade Nachrichten …",
        ["Loading weather …"] = "Lade Wetter …",
        ["Month"] = "Monat",
        ["NEXT HOURS"] = "NÄCHSTE STUNDEN",
        ["New reminder"] = "Neue Erinnerung",
        ["News unavailable"] = "Nachrichten nicht erreichbar",
        ["Next: "] = "Danach: ",
        ["No calendar linked yet.\nAdd an ICS link in the editor."] = "Noch kein Kalender verknüpft.\nICS-Link im Editor eintragen.",
        ["No devices selected"] = "Keine Geräte ausgewählt",
        ["No events in the next %d days"] = "Keine Termine in den nächsten %d Tagen",
        ["No feed configured"] = "Kein Feed eingestellt",
        ["No photos found.\nCopy JPG or PNG files into the folder inkdeck/%s on your device."] =
            "Keine Fotos gefunden.\nKopiere JPG- oder PNG-Dateien in den Ordner inkdeck/%s auf deinem Gerät.",
        ["No upcoming events"] = "Keine anstehenden Termine",
        ["Nothing playing right now"] = "Gerade läuft nichts",
        ["Nothing scrobbled yet"] = "Noch nichts gescrobbelt",
        ["Now playing"] = "Läuft gerade",
        ["OK: play/pause   ·   ◀ ▶ track   ·   ▲ ▼ volume   ·   Back: close"] =
            "Mitte: Play/Pause   ·   ◀ ▶ Titel   ·   ▲ ▼ Lautstärke   ·   Zurück: schließen",
        ["Open InkDeck"] = "InkDeck öffnen",
        ["Open when KOReader starts"] = "Beim Start von KOReader öffnen",
        ["PHOTO FRAME"] = "BILDERRAHMEN",
        ["Page %d"] = "Seite %d",
        ["Photos:"] = "Fotos:",
        ["Portrait"] = "Hochformat",
        ["Put photos (JPG/PNG) into the folder\ninkdeck/%s"] = "Lege Fotos (JPG/PNG) in den Ordner\ninkdeck/%s",
        ["Refresh everything"] = "Alles aktualisieren",
        ["Reload configuration"] = "Konfiguration neu laden",
        ["Save"] = "Speichern",
        ["Show selection frame"] = "Auswahlrahmen zeigen",
        ["Shows your latest Last.fm scrobble   ·   Back: close"] = "Zeigt deinen letzten Last.fm-Scrobble   ·   Zurück: schließen",
        ["Spotify needs the optional InkDeck bridge.\nSet the bridge address in the editor – or use the Last.fm widget instead."] =
            "Spotify braucht die optionale InkDeck-Bridge.\nBridge-Adresse im Editor eintragen – oder stattdessen das Last.fm-Widget nutzen.",
        ["Sun %s – %s"] = "Sonne %s – %s",
        ["This page is empty.\nAdd widgets in the editor and copy config.json to your device."] =
            "Diese Seite ist leer.\nWidgets im Editor hinzufügen und config.json aufs Gerät kopieren.",
        ["Today"] = "Heute",
        ["Tomorrow"] = "Morgen",
        ["Updated %s"] = "Stand %s",
        ["Weather unavailable"] = "Wetter nicht erreichbar",
        ["Week %d"] = "Kalenderwoche %d",
        ["Week %d  ·  %d"] = "KW %d  ·  %d",
        ["Week %d  ·  Day %d of the year"] = "Kalenderwoche %d  ·  Tag %d des Jahres",
        ["Widget error:"] = "Widget-Fehler:",
        ["Wind %d km/h  ·  Humidity %d%%"] = "Wind %d km/h  ·  Feuchte %d%%",
        ["all day"] = "ganztägig",
        ["day since %s"] = "Tag seit %s",
        ["day until %s"] = "Tag bis %s",
        ["days since %s"] = "Tage seit %s",
        ["days until %s"] = "Tage bis %s",
        ["just now"] = "gerade eben",
        ["nothing playing"] = "nichts läuft",
        ["paused"] = "pausiert",
        ["playing"] = "spielt",
        ["▲ ▼ next/previous article   ·   OK/Back: list"] = "▲ ▼ Artikel wechseln   ·   Mitte/Zurück: zur Liste",
        ["▲ ▼ scroll   ·   OK: month view   ·   Back: close"] = "▲ ▼ blättern   ·   Mitte: Monatsansicht   ·   Zurück: schließen",
        ["▲ ▼ select   ·   OK: check off   ·   ◀ delete   ·   Back: close"] = "▲ ▼ auswählen   ·   Mitte: abhaken   ·   ◀ löschen   ·   Zurück: schließen",
        ["▲ ▼ select   ·   OK: read"] = "▲ ▼ auswählen   ·   Mitte: lesen",
        ["▲ ▼ select   ·   OK: switch   ·   ◀ ▶ dim   ·   Back: close"] = "▲ ▼ auswählen   ·   Mitte: schalten   ·   ◀ ▶ dimmen   ·   Zurück: schließen",
        ["◀ ▶ change month   ·   OK: agenda   ·   Back: close"] = "◀ ▶ Monat wechseln   ·   Mitte: Terminliste   ·   Zurück: schließen",
        ["◀ ▶ previous / next photo   ·   Back: close"] = "◀ ▶ vorheriges / nächstes Foto   ·   Zurück: schließen",
    },
}

I.available = { "en", "de" }

-- accepts "de", "de_DE", "de-AT", "en_US", "C", …
function I.set(lang)
    lang = tostring(lang or "en"):lower():match("^(%a%a)") or "en"
    I.lang = (TRANSLATIONS[lang] or lang == "en") and lang or "en"
end

function I.t(s)
    local tr = TRANSLATIONS[I.lang]
    return tr and tr[s] or s
end

function I.f(s, ...)
    return string.format(I.t(s), ...)
end

function I.names()
    return NAMES[I.lang] or NAMES.en
end

-- for tests: keys missing in a language
function I.missing(lang, keys)
    local out = {}
    for _, k in ipairs(keys) do
        if not (TRANSLATIONS[lang] or {})[k] then out[#out + 1] = k end
    end
    return out
end

return I
