local _, Flame = ...

-- Get Librairies
local AceAddon = LibStub("AceAddon-3.0");
local AceGUI = LibStub("AceGUI-3.0");
local Serializer = LibStub:GetLibrary("AceSerializer-3.0");

local Compresser = LibStub:GetLibrary("LibCompress")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local configForDeflate = {level = 9}

-- Declare Addon
Flame = AceAddon:NewAddon(Flame, "Flame", "AceEvent-3.0", "AceBucket-3.0", "AceConsole-3.0")

-- [WeakAuras2] Start
-- @ WeakAuras/Transmission.lua
local function recurseStringify(data, level, lines)
    for k, v in pairs(data) do
        local lineFormat = strrep("    ", level) .. "[%s] = %s"
        local form1, form2, value
        local ktype, vtype = type(k), type(v)
        if ktype == "string" then
            form1 = "%q"
        elseif ktype == "number" then
            form1 = "%d"
        else
            form1 = "%s"
        end
        if vtype == "string" then
            form2 = "%q"
            v = v:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\"", "\\\"")
        elseif vtype == "boolean" then
            v = tostring(v)
            form2 = "%s"
        else
            form2 = "%s"
        end
        lineFormat = lineFormat:format(form1, form2)
        if vtype == "table" then
            tinsert(lines, lineFormat:format(k, "{"))
            recurseStringify(v, level + 1, lines)
            tinsert(lines, strrep("    ", level) .. "},")
        else
            tinsert(lines, lineFormat:format(k, v) .. ",")
        end
    end
end
local function SerializeTable(data)
    local lines = {"{"}
    recurseStringify(data, 1, lines)
    tinsert(lines, "}")
    return table.concat(lines, "\n")
end
local function TableToString(inTable, forChat)
    local serialized = Serializer:Serialize(inTable)
    local compressed = LibDeflate:CompressDeflate(serialized, configForDeflate)
    -- prepend with "!" so that we know that it is not a legacy compression
    -- also this way, old versions of weakauras will error out due to the "bad" encoding
    local encoded = "!"
    if(forChat) then
        encoded = encoded .. LibDeflate:EncodeForPrint(compressed)
    else
        encoded = encoded .. LibDeflate:EncodeForWoWAddonChannel(compressed)
    end
    return encoded
end
local function StringToTable(inString, fromChat)
    -- if gsub strips off a ! at the beginning then we know that this is not a legacy encoding
    local encoded, usesDeflate = inString:gsub("^%!", "")
    local decoded
    if(fromChat) then
        if usesDeflate == 1 then
        decoded = LibDeflate:DecodeForPrint(encoded)
        else
        decoded = decodeB64(encoded)
        end
    else
        decoded = LibDeflate:DecodeForWoWAddonChannel(encoded)
    end

    if not decoded then
        return "Error decoding."
    end

    local decompressed, errorMsg = nil, "unknown compression method"
    if usesDeflate == 1 then
        decompressed = LibDeflate:DecompressDeflate(decoded)
    else
        decompressed, errorMsg = Compresser:Decompress(decoded)
    end
    if not(decompressed) then
        return "Error decompressing: " .. errorMsg
    end

    local success, deserialized = Serializer:Deserialize(decompressed);
    if not(success) then
        return "Error deserializing "..deserialized;
    end
    return deserialized;
end
-- [WeakAuras2] End

-- Credit @daurnimator stackoverflow.com
local function range ( from , to )
    return function (_,last)
            if last >= to then return nil
            else return last+1
            end
        end , nil , from-1
end

-- Credit @ingemar https://forums.coronalabs.com/topic/42019-split-utf-8-string-word-with-foreign-characters-to-letters/
local UTF8ToCharArray = function(str)
    local charArray = {};
    local iStart = 0;
    local strLen = str:len();
    
    local function bit(b)
        return 2 ^ (b - 1);
    end
 
    local function hasbit(w, b)
        return w % (b + b) >= b;
    end
    
    local checkMultiByte = function(i)
        if (iStart ~= 0) then
            charArray[#charArray + 1] = str:sub(iStart, i - 1);
            iStart = 0;
        end        
    end
    
    for i = 1, strLen do
        local b = str:byte(i);
        local multiStart = hasbit(b, bit(7)) and hasbit(b, bit(8));
        local multiTrail = not hasbit(b, bit(7)) and hasbit(b, bit(8));
 
        if (multiStart) then
            checkMultiByte(i);
            iStart = i;
            
        elseif (not multiTrail) then
            checkMultiByte(i);
            charArray[#charArray + 1] = str:sub(i, i);
        end
    end
    
    -- process if last character is multi-byte
    checkMultiByte(strLen + 1);
 
    return charArray;
end

-- MAIN FUNCTION
function Flame:Translate (text)
    if self.db.profile.chat then
        local delim = {",", ";"}
        local p = "[^"..table.concat(delim).."]+"
        -- Check if there is any Chinese Character in the text

        if strfind(text, "[\227-\237]") then
            -- Convert input str into a table
            local textTbl = UTF8ToCharArray(text)

            -- Pinyin
            if Flame.db.profile.pinyin then
                local pinyin = ''
                for k,v in pairs(textTbl) do
                    if Flame.dictionary[v]==nil then
                        pinyin=pinyin..v
                    else
                        local pin = Flame.dictionary[v][2]
                        if pin then
                            pinyin=pinyin.." "..pin.." "
                        end
                    end
                end
                print (pinyin)
            end

            local textSize = 0
            for _,v in pairs(textTbl) do textSize=textSize+1 end
            if textSize<=Flame.db.profile.maxChar then

                -- Chunk Alphabetical Letters into sequence
                local last = false
                local idxRmv = 0
                local word = ''
                for i, v in pairs (textTbl) do
                    if strfind(v, "[^a-zA-Z]")==nil then
                        if i == #textTbl then
                            word=word..textTbl[i]
                            textTbl[i] = word 
                        else
                            if last == false then
                                idxRmv = i
                            end
                            word=word..textTbl[i] 
                            textTbl[i] = nil
                            last=true
                        end
                    else 
                        if last then
                            textTbl[i-1] = word 
                            word = ''
                        end
                        last=false
                    end
                end

                local textTblOrder = {}
                for k, v in pairs (textTbl) do
                    table.insert(textTblOrder, v)
                end
                textTbl = textTblOrder

                for i, cn in pairs(textTbl) do
                    -- Convert cn keys into a table
                    local subTbl = Flame.indexTable[cn]
                    if subTbl~=nil then
                        for cnK, t in pairs(subTbl) do
                            local cnTbl = {cnK}
                            if strfind(cnK, "[\227-\237]") then
                                cnTbl = UTF8ToCharArray(cnK)
                            end
                            local sizeCnTbl = table.getn(cnTbl)-1
                            local t = {}
                            for y in range(i,i+sizeCnTbl) do
                                table.insert(t, textTbl[y])
                            end
                            local cnKey = table.concat(t)
                            local enValue = Flame.indexTable[cn][cnKey]
                            if enValue~= nil then
                                for y in range(i,i+sizeCnTbl) do
                                    table.remove(textTbl, i)
                                end
                                table.insert(textTbl, i, ' '..enValue..' ')
                                break
                            end
                        end

                    end
                end

                local output = ''

                for _, c in pairs(textTbl) do
                    if Flame.dictionary[c]==nil then
                        output=output..c
                    else
                        local description = Flame.dictionary[c][1]
                        local t = {}
                        for i in description:gmatch(p) do  
                            t[#t + 1] = i
                        end 
                        output=output.." "..t[1].." "
                    end
                end
                output = output:gsub(" +"," ")
                print (output)
            end
        end
    end
end

function Flame.HandleCmd (args)
    local inputs = UTF8ToCharArray(args)
    local w = ''
    local words = {}
    for k,v in pairs (inputs) do
        if v~=' ' then
            w=w..v
        else
            table.insert(words, w)
            w = ''
        end
        if k == table.getn(inputs) then
            table.insert(words, w)
        end
    end

    if words[1]~=nil then
        if words[1]=='add' then
            Flame:Add(words[2], words[3])
        elseif words[1]=='get' then 
            Flame:Get(words[2])
        elseif words[1]=='remove' then 
            Flame:Remove(words[2])
        elseif words[1]=='export' then 
            Flame:Export()
        elseif words[1]=='import' then 
            Flame:Import()
        elseif words[1]=='printall' then 
            Flame:PrintAll()
        elseif words[1]=='chat' then 
            Flame:Chat(words[2])
        elseif words[1]=='dict' then 
            Flame:Dict()
        elseif words[1]=='help' then 
            Flame:Help()
        end
    else
        InterfaceOptionsFrame_OpenToCategory("Flame")
    end
end


function Flame:PrintAll()
    self:Print('PRINT ALL')
    for k, v in pairs(self.db.profile.dictionary) do
        print (k,v)
    end
end

Flame.Rows = {}
function Flame:BuildRow (k, v, parent)
    local l = AceGUI:Create("SimpleGroup", {})
    l:SetFullWidth(true) 
    l:SetLayout('Flow')
    
    l.checkBox = AceGUI:Create("CheckBox")
    l.checkBox:SetWidth (30)
    l:AddChild(l.checkBox)

    l.inBox = AceGUI:Create("EditBox")
    l.inBox:SetWidth (120)
    l.inBox:SetText(k)
    l:AddChild(l.inBox)

    l.outBox = AceGUI:Create("EditBox")
    l.outBox:SetWidth (220)
    l.outBox:SetText(v)
    l:AddChild(l.outBox)

    if parent then
        parent:AddChild(l)
    end

    table.insert(Flame.Rows, l)
    return l
end

function Flame:RemoveRows()
    local removed = {}
    for i,l in pairs(Flame.Rows) do
        local checked = l.checkBox:GetValue()
        if checked then
            l:ReleaseChildren()
            local character = l.inBox:GetText()
            Flame:Remove(character, true)
            table.insert(removed, i)
        end
    end
    self.mainLayout:DoLayout()
    for i, v in pairs(removed) do
        table.remove (Flame.Rows,v)
    end
end

function Flame:SaveRows()
    for i,l in pairs(Flame.Rows) do
        local k = l.inBox:GetText()
        local v = l.outBox:GetText()
        self:Add(k, v, false)
    end
end

function Flame:Dict()
    local frame = AceGUI:Create("Frame")
    
    frame:SetTitle("Flame - Dictionary")
    frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
    frame:SetLayout("Flow")
    frame:SetHeight(600)
    frame:SetWidth(450)

    local scrollcontainer = AceGUI:Create("SimpleGroup") -- "InlineGroup" is also good
    scrollcontainer:SetFullWidth(true)
    scrollcontainer:SetHeight(500)
    scrollcontainer:SetLayout("Fill")

    frame:AddChild(scrollcontainer)

    Flame.mainLayout = AceGUI:Create("ScrollFrame")
    Flame.mainLayout:SetLayout("Flow") 
    scrollcontainer:AddChild(Flame.mainLayout)

    Flame.Rows = {}
    for k, v in pairs(self.db.profile.dictionary) do
        local layout = self:BuildRow(k, v, Flame.mainLayout)
    end

    local buttonAdd = AceGUI:Create("Button")
    buttonAdd:SetText("Add")
    buttonAdd:SetWidth(130)
    buttonAdd:SetCallback("OnClick", function(self) Flame:BuildRow('', '', Flame.mainLayout) end)
    frame:AddChild(buttonAdd)    

    local buttonRemove = AceGUI:Create("Button")
    buttonRemove:SetText("Remove")
    buttonRemove:SetWidth(130)
    buttonRemove:SetCallback("OnClick", function(self) Flame:RemoveRows() end)
    frame:AddChild(buttonRemove)

    local buttonSave = AceGUI:Create("Button")
    buttonSave:SetText("Save")
    buttonSave:SetWidth(130)
    buttonSave:SetCallback("OnClick", function(self) Flame:SaveRows() end)
    frame:AddChild(buttonSave)

end

function Flame:Chat(status)
    if status == 'true' or status == '1' then
        self:Print('CHAT ENABLE')
        self.db.profile.chat = true
    elseif status == 'false' or status == '0' then
        self:Print('CHAT DISABLE')
        self.db.profile.chat = false
    end
end

function Flame:Help()
    self:Print('USAGE')
    print ('/flame add {chinese} {translation}')
    print ('/flame get {chinese}')
    print ('/flame remove {chinese}')
    print ('/flame chat {0 or 1}')
    print ('/flame export')
    print ('/flame import')
    print ('/flame help')
end

function Flame:Add(character, translation, verbose)
    self.db.profile.dictionary[character]=translation
    if verbose~=false then 
        self:Print('ADD', character, translation)
    end
end

function Flame:Get(character)
    self:Print('GET', character, self.db.profile.dictionary[character])
end

function Flame:Remove(character, verbose)
    self.db.profile.dictionary[character]=nil
    if verbose~=false then 
        self:Print('REMOVE', character)
    end
end
function Flame:ImportData(data)
    local t = StringToTable(data, true)
    for k,v in pairs(t) do self.db.profile.dictionary[k] = v end
    -- self.db.profile.dictionary = t
    self:Print ('IMPORTED')
    for k,v in pairs(t) do
        print (k,v)
    end
end

function Flame:Import()
    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Flame - Import")
    frame:SetWidth(400)
    frame:SetHeight(200)
    frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
    frame:SetLayout("Flow")

    local editbox = AceGUI:Create("MultiLineEditBox")
    editbox:SetLabel("Import")
    editbox:SetFullHeight(true)
    editbox:SetFullWidth(true)
    editbox:SetCallback("OnEnterPressed", function(self) Flame:ImportData(self.editBox:GetText()) end)
    frame:AddChild(editbox)

    local button = AceGUI:Create("Button")
    button:SetText("Import")
    button:SetWidth(200)
    frame:AddChild(button)
end

function Flame:Export()
    local dictstring = TableToString(self.db.profile.dictionary, true)

    local frame = AceGUI:Create("Frame")
    frame:SetTitle("Flame - Export")
    frame:SetWidth(400)
    frame:SetHeight(200)
    frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
    frame:SetLayout("Flow")

    local editbox = AceGUI:Create("MultiLineEditBox")
    editbox:SetLabel("Export")
    editbox:DisableButton(true)
    editbox:SetFullHeight(true)
	editbox:SetFullWidth(true)
    editbox:SetText(dictstring)
    frame:AddChild(editbox)

end


SlashCmdList["Flame_Slash_Command"] = Flame.HandleCmd
SLASH_Flame_Slash_Command1 = "/flame"


function Flame:OnInitialize()

    -- Default Database 
    local defaults = {
        profile = {
            dictionary = {
                ['*']=''
            },
            chat = true,
            pinyin = true,
            maxChar = 255,
            questsColor = {1,1,0,1},
            creaturesColor = {0,1,1,1},
            --
            yell = true,
            whisper = true,
            say = true,
            raid = true,
            party = true,
            channel = true,
            guild = true,
        },
        
    }
    
    -- Interface
    local options = {
        type = "group",
        name = "Flame",
        args = {
            options={
                name = "Options",
                type = "group",
                args={
                    chat = {
                        name = "Chat enable",
                        desc = "Enables / disables chat",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.chat = val end,
                        get = function(info) return Flame.db.profile.chat end
                    },
                    pinyin = {
                        name = "Pinyin enable",
                        desc = "Enables / disables pinyin",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.pinyin = val end,
                        get = function(info) return Flame.db.profile.pinyin end
                    },
                    maxChar = {
                        name = "Maximum Character",
                        desc = "Maximum Character to translate",
                        type = "range",
                        min = 0,
                        max = 255,
                        step = 5,
                        set = function(info,val) Flame.db.profile.maxChar = val end,
                        get = function(info) return Flame.db.profile.maxChar end
                    },
                    questsColor = {
                        name = "Quest color",
                        desc = "Colorize quest's name in the chat",
                        type = "color",
                        set = function(info,r,g,b,a) Flame.db.profile.questsColor = {r,g,b,a} end,
                        get = function(info) return unpack(Flame.db.profile.questsColor) end
                    },
                    creaturesColor = {
                        name = "Creature color",
                        desc = "Colorize creature's name in the chat",
                        type = "color",
                        set = function(info,r,g,b,a) Flame.db.profile.creaturesColor = {r,g,b,a} end,
                        get = function(info) return unpack(Flame.db.profile.creaturesColor) end
                    },
                },
            },
            channels={
                name = "Channels",
                type = "group",
                args={
                    yell = {
                        name = "Yell",
                        desc = "Yell Event",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.yell = val end,
                        get = function(info) return Flame.db.profile.yell end
                    },
                    whisper = {
                        name = "Whisper",
                        desc = "Whisper Event",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.whisper = val end,
                        get = function(info) return Flame.db.profile.whisper end
                    },
                    guild = {
                        name = "Guild",
                        desc = "Guild Event",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.guild = val end,
                        get = function(info) return Flame.db.profile.guild end
                    },
                    say = {
                        name = "Say",
                        desc = "Say Event",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.say = val end,
                        get = function(info) return Flame.db.profile.say end
                    },
                    raid = {
                        name = "Raid",
                        desc = "Raid Event",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.raid = val end,
                        get = function(info) return Flame.db.profile.raid end
                    },
                    party = {
                        name = "Party",
                        desc = "Party Event",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.party = val end,
                        get = function(info) return Flame.db.profile.party end
                    },
                    channel = {
                        name = "Channel",
                        desc = "Channel Event",
                        type = "toggle",
                        set = function(info,val) Flame.db.profile.channel = val end,
                        get = function(info) return Flame.db.profile.channel end
                    },
                }
              }
        },
        
    }

    self.db = LibStub("AceDB-3.0"):New("FlameDB", defaults, true)
    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("Flame_Options", options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Flame_Options", "Flame")

end

function Flame:ADDON_LOADED ()
        for _, t in pairs ({'quests', 'creatures'}) do
            for k,v in pairs (Flame[t]) do 
                local color = Flame.db.profile[t..'Color']
                local hex = format("\124cff%.2x%.2x%.2x", color[1]*255, color[2]*255, color[3]*255) 
                Flame[t][k]=hex.."["..v.."]|r"
            end
        end

        -- Build a single dict
        local sumTables = {}
        local sources = {Flame.db.profile.dictionary,Flame.quests,Flame.items, Flame.creatures, Flame.misc}--
        for _, s in pairs (sources) do 
            for k,v in pairs(s) do sumTables[k]=v end
        end
        Flame.datas = sumTables

        -- Create a table by first char
        local indexTable = {}
        for cn, en in pairs(Flame.datas) do
            if strfind(cn, "[\227-\237]") then
                local cnTbl = UTF8ToCharArray(cn)
                if indexTable[cnTbl[1]] == nil then
                        indexTable[cnTbl[1]] = {[cn]=en}
                else 
                        indexTable[cnTbl[1]][cn]= en
                end
            else
                if indexTable[cn] == nil then
                    indexTable[cn] = {[cn]=en}
                else 
                    indexTable[cn][cn]= en
                end 
            end
        end
        Flame.indexTable = indexTable
end


--event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons
function Flame:CHAT_MSG_CHANNEL (event, text, ...)
    if Flame.db.profile.channel then
        self:Translate(text)
    end
end
function Flame:CHAT_MSG_PARTY (event, text, ...)
    if Flame.db.profile.party then
        self:Translate(text)
    end
end
function Flame:CHAT_MSG_YELL (event, text, ...)
    if Flame.db.profile.yell then
        self:Translate(text)
    end
end
function Flame:CHAT_MSG_WHISPER (event, text, ...)
    if Flame.db.profile.whisper then
        self:Translate(text)
    end
end
function Flame:CHAT_MSG_SAY (event, text, ...)
    if Flame.db.profile.say then
        self:Translate(text)
    end
end
function Flame:CHAT_MSG_RAID (event, text, ...)
    if Flame.db.profile.raid then
        self:Translate(text)
    end
end
function Flame:CHAT_MSG_GUILD (event, text, ...)
    if Flame.db.profile.guild then
        self:Translate(text)
    end
end

function Flame:OnEnable()
    local events = {'ADDON_LOADED'}
    local chatType = {'YELL', 'WHISPER', 'SAY', 'RAID', 'GUILD', 'PARTY', 'CHANNEL'}
    for _, t in pairs (chatType) do
        table.insert(events, 'CHAT_MSG_'..t)
    end
    for _, e in pairs (events) do
        self:RegisterEvent(e)
    end
end