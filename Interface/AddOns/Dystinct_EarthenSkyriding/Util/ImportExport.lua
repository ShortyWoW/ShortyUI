local addonName, addon = ...

local OLD_STRING_PREFIX = "DYSES:V1:"
local NEW_STRING_PREFIX = "DYSJS:V1:" -- Prefix for the new JSON format
local NEW_JSON_PREFIX = NEW_STRING_PREFIX -- Fixed variable name to match what's referenced in the code

-- Base64 decoding table
local b64 = {
    ['A'] = 0, ['B'] = 1, ['C'] = 2, ['D'] = 3, ['E'] = 4, ['F'] = 5, ['G'] = 6, ['H'] = 7,
    ['I'] = 8, ['J'] = 9, ['K'] = 10, ['L'] = 11, ['M'] = 12, ['N'] = 13, ['O'] = 14, ['P'] = 15,
    ['Q'] = 16, ['R'] = 17, ['S'] = 18, ['T'] = 19, ['U'] = 20, ['V'] = 21, ['W'] = 22, ['X'] = 23,
    ['Y'] = 24, ['Z'] = 25, ['a'] = 26, ['b'] = 27, ['c'] = 28, ['d'] = 29, ['e'] = 30, ['f'] = 31,
    ['g'] = 32, ['h'] = 33, ['i'] = 34, ['j'] = 35, ['k'] = 36, ['l'] = 37, ['m'] = 38, ['n'] = 39,
    ['o'] = 40, ['p'] = 41, ['q'] = 42, ['r'] = 43, ['s'] = 44, ['t'] = 45, ['u'] = 46, ['v'] = 47,
    ['w'] = 48, ['x'] = 49, ['y'] = 50, ['z'] = 51, ['0'] = 52, ['1'] = 53, ['2'] = 54, ['3'] = 55,
    ['4'] = 56, ['5'] = 57, ['6'] = 58, ['7'] = 59, ['8'] = 60, ['9'] = 61, ['+'] = 62, ['/'] = 63,
    ['='] = nil
}

local function DecodeBase64(data)
    if type(data) ~= "string" then
         print(addonName .. " DecodeBase64 Error: Input is not a string")
         return nil -- Return nil on bad input type
    end

    -- Strip invalid characters. Adjusted to only allow valid Base64 chars + padding
    data = string.gsub(data, '[^A-Za-z0-9%+/%=]', '')
    -- If supporting base64url, use:
    -- data = string.gsub(data, '[^A-Za-z0-9%+%/%_%-%=]', '')

    local result = ''
    local acc = 0
    local bits = 0

    if #data == 0 then
        return ""
    end

    for i = 1, #data do
        local c = data:sub(i, i)
        if c == '=' then -- Handle padding: Stop processing
            break
        end

        local b = b64[c]
        if b then
             -- Accumulate bits safely
             local success_accumulate, new_acc, new_bits = pcall(function()
                 -- Shift accumulator left by 6, add new 6 bits using bitwise OR
                 local temp_acc = bit.bor(bit.lshift(acc, 6), b)
                 local temp_bits = bits + 6                 -- We've added 6 bits
                 return temp_acc, temp_bits
             end)

             -- If accumulation failed, log it and skip to the next character automatically
             if not success_accumulate then
                 print(addonName .. " Warning: Bit accumulation failed at position " .. i .. ". Skipping char.")
                 -- No goto needed, the loop will naturally continue to the next 'i'
             else
                 -- Update accumulator and bits count ONLY if pcall was successful
                 acc = new_acc
                 bits = new_bits

                -- Extract bytes while we have enough bits
                while bits >= 8 do
                    local byteValue
                    local success_extract = pcall(function()
                         -- Get the most significant 8 bits
                         byteValue = bit.band(bit.rshift(acc, bits - 8), 0xFF)
                         -- No need to modify acc here, rshift doesn't change the original value
                         -- We just need to reduce the bits count
                         bits = bits - 8 -- Remove those 8 bits from the count
                    end)

                    if not success_extract then
                         print(addonName .. " Warning: Bit extraction failed at position " .. i .. ". Stopping byte extraction for this char.")
                         -- Use 'break' to exit the inner 'while bits >= 8' loop for this character
                         break
                    end

                    -- Convert byte to character safely
                    local charSuccess, char = pcall(string.char, byteValue)
                    if charSuccess then
                        result = result .. char
                    else
                        print(addonName .. " Warning: Invalid byte value " .. tostring(byteValue) .. " encountered at position " .. i)
                        -- Decide if you want to break the inner loop here too or just skip the char
                        -- break -- Uncomment if one bad byte should stop processing the char's bits
                    end
                end -- end while bits >= 8
            end -- end if success_accumulate
        else
             -- Optional: Warn about invalid base64 characters if desired
             -- print(addonName .. " Warning: Skipping invalid Base64 character '" .. c .. "' at position " .. i)
        end
    end -- end for loop

    -- Final check for remaining bits - Base64 shouldn't leave partial bytes if input was valid
    -- if bits > 0 and bits < 8 then
    --     print(addonName .. " Warning: Base64 decoding finished with " .. bits .. " dangling bits left over. Input might be truncated or corrupt.")
    -- end

    return result
end

-- JSON parsing functions
local function DecodeJson(json)
    local pos = 1
    local t
    
    -- Skip whitespace
    local function SkipWhitespace()
        pos = string.find(json, '[^%s]', pos) or pos
    end
    
    -- Forward declarations
    local ParseObject, ParseArray, ParseString, ParseNumber, ParseValue
    
    -- Parse JSON object
    ParseObject = function()
        local obj = {}
        pos = pos + 1  -- Skip '{'
        
        SkipWhitespace()
        if json:sub(pos, pos) == "}" then
            pos = pos + 1
            return obj
        end
        
        while true do
            SkipWhitespace()
            
            -- Parse key
            local key = ParseString()
            
            SkipWhitespace()
            -- Skip colon
            if json:sub(pos, pos) ~= ":" then
                error("Expected ':' at position " .. pos)
            end
            pos = pos + 1
            
            SkipWhitespace()
            -- Parse value
            local val = ParseValue()
            obj[key] = val
            
            SkipWhitespace()
            local c = json:sub(pos, pos)
            pos = pos + 1
            
            if c == "}" then
                break
            elseif c ~= "," then
                error("Expected ',' or '}' at position " .. (pos - 1))
            end
        end
        
        return obj
    end
    
    -- Parse JSON array
    ParseArray = function()
        local arr = {}
        pos = pos + 1  -- Skip '['
        
        SkipWhitespace()
        if json:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        
        while true do
            SkipWhitespace()
            
            -- Parse value
            local val = ParseValue()
            table.insert(arr, val)
            
            SkipWhitespace()
            local c = json:sub(pos, pos)
            pos = pos + 1
            
            if c == "]" then
                break
            elseif c ~= "," then
                error("Expected ',' or ']' at position " .. (pos - 1))
            end
        end
        
        return arr
    end
    
    -- Parse JSON string
    ParseString = function()
        local startPos = pos + 1  -- Skip opening quote
        local endPos = startPos
        
        while true do
            endPos = string.find(json, '"', endPos)
            if not endPos then
                error("Unterminated string starting at position " .. startPos)
            end
            
            -- Check if the quote is escaped
            local backslashes = 0
            local i = endPos - 1
            while json:sub(i, i) == "\\" do
                backslashes = backslashes + 1
                i = i - 1
            end
            
            if backslashes % 2 == 0 then
                break
            end
            
            endPos = endPos + 1
        end
        
        local str = json:sub(startPos, endPos - 1)
        pos = endPos + 1  -- Skip closing quote
        
        -- Handle escaped characters
        str = str:gsub('\\\"', '"')
          :gsub('\\\\', '\\')
          :gsub('\\/', '/')
          :gsub('\\b', '\b')
          :gsub('\\f', '\f')
          :gsub('\\n', '\n')
          :gsub('\\r', '\r')
          :gsub('\\t', '\t')
          :gsub('\\u(%x%x%x%x)', function(hex)
              local code = tonumber(hex, 16)
              return string.char(code)
          end)
        
        return str
    end
    
    -- Parse JSON number
    ParseNumber = function()
        local start = pos
        if json:sub(pos, pos) == "-" then
            pos = pos + 1
        end
        
        while pos <= #json and json:sub(pos, pos):match("[0-9]") do
            pos = pos + 1
        end
        
        if pos <= #json and json:sub(pos, pos) == "." then
            pos = pos + 1
            while pos <= #json and json:sub(pos, pos):match("[0-9]") do
                pos = pos + 1
            end
        end
        
        if pos <= #json and json:sub(pos, pos):match("[eE]") then
            pos = pos + 1
            if json:sub(pos, pos):match("[%+%-]") then
                pos = pos + 1
            end
            while pos <= #json and json:sub(pos, pos):match("[0-9]") do
                pos = pos + 1
            end
        end
        
        return tonumber(json:sub(start, pos - 1))
    end
    
    -- Parse JSON value
    ParseValue = function()
        SkipWhitespace()
        
        local c = json:sub(pos, pos)
        
        if c == "{" then
            return ParseObject()
        elseif c == "[" then
            return ParseArray()
        elseif c == '"' then
            return ParseString()
        elseif c:match("[%-%+0-9]") then
            return ParseNumber()
        elseif c == "t" and json:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif c == "f" and json:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif c == "n" and json:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            error("Unexpected character at position " .. pos .. ": " .. c)
        end
    end
    
    -- Start parsing
    SkipWhitespace()
    t = ParseValue()
    SkipWhitespace()
    
    if pos <= #json then
        error("Unexpected data after JSON end at position " .. pos)
    end
    
    return t
end

-- Main decode function that combines base64 decoding and JSON parsing
local function DecodeBase64JSON(base64String)
    -- Step 1: Decode base64 to get the JSON string
    local jsonString = DecodeBase64(base64String)
    
    -- Step 2: Parse the JSON string into a Lua table
    local jsonTable = DecodeJson(jsonString)
    
    return jsonTable
end

function addon:OldImportStringToTable(encodedString)
    if not addon.importExportEnabled then
        return nil, "Import/Export feature not available - missing required libraries (LibDeflate, LibSerialize)"
    end

    if not encodedString or encodedString == "" or type(encodedString) ~= "string" then
        return nil, "Invalid input string"
    end

    -- Decode the string
    local decoded = LibDeflate:DecodeForPrint(encodedString)
    if not decoded then
        return nil, "Failed to decode string"
    end

    -- Decompress the decoded string
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil, "Failed to decompress data"
    end

    -- Check for our prefix
    if not decompressed:match("^" .. OLD_STRING_PREFIX) then
        return nil, "Invalid import string: wrong format or from different addon"
    end

    -- Remove the prefix before deserialization
    local serializedData = decompressed:sub(#OLD_STRING_PREFIX + 1)

    -- Deserialize into a table
    local success, deserialized = LibSerialize:Deserialize(serializedData)
    if not success then
        return nil, "Failed to deserialize data"
    end

    return true, deserialized
end

function addon:ImportStringToTable(encodedString)

	local success, deserialized = self:OldImportStringToTable(encodedString)
	if success then
		return deserialized
	end

    local b64Success, decodedString = pcall(DecodeBase64, encodedString)

    if b64Success and decodedString and type(decodedString) == "string" then
        if decodedString:sub(1, #NEW_JSON_PREFIX) == NEW_JSON_PREFIX then -- Use NEW_JSON_PREFIX here
            local jsonString = decodedString:sub(#NEW_JSON_PREFIX + 1)
            local jsonSuccess, jsonResult = pcall(DecodeJson, jsonString)

            if jsonSuccess and type(jsonResult) == "table" then
                return jsonResult
            elseif not jsonSuccess then
                 print("JSON parsing failed after Base64 decode. Error: " .. tostring(jsonResult))
             else
                 print("JSON parsing after Base64 succeeded but result is not a table. Type: " .. type(jsonResult))
            end
        end
    elseif not b64Success then
         print("Base64 decoding failed. Error: " .. tostring(decodedString)) -- decodedString holds error
    else
        print("Base64 decoding returned non-string or nil.")
    end

    print("Failed to import: Unsupported or corrupted format.")
    return nil, "Failed to import: Unsupported or corrupted format"
end

function addon:ExportTableToString(tableToExport)
    if not addon.importExportEnabled then
        return "Import/Export feature not available - missing required libraries (LibDeflate, LibSerialize)"
    end

    if type(tableToExport) ~= "table" then
        return "Input must be a table"
    end

    -- Serialize the table
    local serialized = LibSerialize:Serialize(tableToExport)
    if not serialized then
        return "Failed to serialize data"
    end

    -- Add our prefix to the serialized string before compression
    local prefixedString = OLD_STRING_PREFIX .. serialized

    -- Compress the prefixed string
    local compressed = LibDeflate:CompressDeflate(prefixedString)
    if not compressed then
        return "Failed to compress data"
    end

    -- Encode for safe string transfer
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return "Failed to encode data"
    end

    return encoded
end