local addonName, ns = ...

---@class CDMLayout
---@field classAndSpecTag number
---@field cooldownInfo table
---@field isDefault boolean
---@field layoutID number
---@field layoutName string
---@field orderedCooldownIDs number[]

M33CDMSYNCSTRINGS = M33CDMSYNCSTRINGS or {}

local function DecodeTable(encoded)
	local ok, decoded = pcall(C_EncodingUtil.DecodeBase64, encoded);
	if not ok then return false, "DecodeBase64 failed: " .. decoded; end

	local ok, decompressed = pcall(C_EncodingUtil.DecompressString, decoded);
	if not ok then return false, "DecompressString failed: " .. decompressed; end

	local ok, deserialized = pcall(C_EncodingUtil.DeserializeCBOR, decompressed);
	if not ok then return false, "DeserializeCBOR failed: " .. deserialized; end

	return true, deserialized;
end

local function EncodeTable(data)
	local ok, serialized = pcall(C_EncodingUtil.SerializeCBOR, data, {ignoreSerializationErrors=true});
	if not ok then return false, "SerializeCBOR failed: " .. serialized; end

	local ok, compressed = pcall(C_EncodingUtil.CompressString, serialized);
	if not ok then return false, "CompressString failed: " .. compressed; end

	local ok, encoded = pcall(C_EncodingUtil.EncodeBase64, compressed);
	if not ok then return false, "EncodeBase64 failed: " .. encoded; end

	return true, encoded;
end

local function saveLayouts()
	local expTable = {
        rawencoded = C_CooldownViewer.GetLayoutData()
    }

	local ok, exp = EncodeTable(expTable)
	assert(ok, exp)
	M33CDMSYNCSTRINGS[UnitClassBase("player")] = exp
end

local function restoreLayouts()
	local imp = M33CDMSYNCSTRINGS[UnitClassBase("player")]
	if not imp then return end
	local ok, impTable = DecodeTable(imp)
	assert(ok, impTable)

    if not impTable.rawencoded then
        print("[M33CDMSync] No layout data found in the decoded table, aborting import")
        return
    end

    if type(impTable.rawencoded) ~= "string" then
        print("[M33CDMSync] Invalid layout data format, expected a string, aborting import")
        return
    end

    if impTable.rawencoded == C_CooldownViewer.GetLayoutData() then
        print("[M33CDMSync] Layout data is identical to current, skipping import")
        return
    end

    C_CooldownViewer.SetLayoutData(impTable.rawencoded)
    print("[M33CDMSync] Layout data reimported")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGOUT")
f:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGOUT" then
		saveLayouts()
    end
end)

restoreLayouts()
