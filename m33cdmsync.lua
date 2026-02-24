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

local getLayoutByName = function(layoutName)
	local CVS = CooldownViewerSettings
	local LM = CVS:GetLayoutManager()
	for _, layout in pairs(LM.layouts) do
		---@cast layout CDMLayout
		if layout.layoutName == layoutName then
			return layout
		end
	end
end

local removeLayout = function(layoutID)
	local CVS = CooldownViewerSettings
	local LM = CVS:GetLayoutManager()

	LM:RemoveLayout(layoutID)
	CVS:SaveCurrentLayout();
end

local getCurrentSpecTag = function()
	local CVS = CooldownViewerSettings
	local LM = CVS:GetLayoutManager()

	return LM.currentSpecTag
end

local function saveLayouts()
	local CVS = CooldownViewerSettings
	local LM = CVS:GetLayoutManager()

	local expTable = {}

	for _, layout in pairs(LM.layouts) do
		local layoutID = layout.layoutID
		local layoutName = layout.layoutName
		local ok, rawencoded = EncodeTable(layout)

		local importStr = LM:GetSerializer():SerializeLayouts(layoutID)
		tinsert(expTable, {
			importStr = importStr,
			layoutName = layoutName,
			rawencoded = rawencoded,
		})
	end

	local ok, exp = EncodeTable(expTable)
	assert(ok, exp)
	M33CDMSYNCSTRINGS[UnitClassBase("player")] = exp
end

local function deepCompare(t1, t2)
	if type(t1) ~= type(t2) then return false end
	if type(t1) ~= "table" then return t1 == t2 end

	local keys = {}
	for k in pairs(t1) do keys[k] = true end
	for k in pairs(t2) do keys[k] = true end

	for k in pairs(keys) do
		if not deepCompare(t1[k], t2[k]) then return false end
	end

	return true
end


local function restoreLayouts()
	local imp = M33CDMSYNCSTRINGS[UnitClassBase("player")]
	if not imp then return end
	local ok, impTable = DecodeTable(imp)
	assert(ok, impTable)

	local shouldReload = false

	for _, layoutData in ipairs(impTable) do
		local CVS = CooldownViewerSettings
		local LM = CVS:GetLayoutManager()
		local layoutName = layoutData.layoutName
		local importStr = layoutData.importStr

		local oldLayout = getLayoutByName(layoutName)
		local shouldImport = true
		while oldLayout do
			local ok, decodedLayout = DecodeTable(layoutData.rawencoded)
			local eq = deepCompare(oldLayout, decodedLayout)
			if eq then
				print("[M33CDMSync] Layout", layoutName, "is identical, skipping import")
				shouldImport = false
				break
			end
			removeLayout(oldLayout.layoutID) -- need to remove old profile with same name first for updating to work and not be confusing
            print("[M33CDMSync] Removed old layout", layoutName, "width id", oldLayout.layoutID)
			oldLayout = getLayoutByName(layoutName)
		end

		if shouldImport then
			print("[M33CDMSync] Importing layout:", layoutName)

			local layoutIDs = LM:CreateLayoutsFromSerializedData(importStr)
			local importedLayout = LM:GetLayout(layoutIDs[1])

			local currentSpecTag = getCurrentSpecTag()
			if currentSpecTag == importedLayout.classAndSpecTag then
				CVS:SetActiveLayoutByID(importedLayout.layoutID)
			end
			LM:SaveLayouts()
			shouldReload = true
		end
	end

	if shouldReload then
		StaticPopupDialogs["M33_CDM_SYNC_RELOAD"] = {
			text = "M33CDMSync: Layouts have been updated. Please reload your UI to avoid taint.",
			button1 = "Reload Now",
			button2 = CANCEL,
			OnAccept = ReloadUI,
			timeout = 0,
			whileDead = true,
			hideOnEscape = false,
			showAlert = true,
		}
		StaticPopup_Show("M33_CDM_SYNC_RELOAD")
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
local vl, pew, cvdl
f:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGOUT" then
		saveLayouts()
		return
	elseif event == "VARIABLES_LOADED" then
		vl = true
	elseif event == "PLAYER_ENTERING_WORLD" then
		local isInitialLogin, isReloadingUi = ...
		if not isInitialLogin and not isReloadingUi then return end
		pew = true
	elseif event == "COOLDOWN_VIEWER_DATA_LOADED" then
		cvdl = true
	end
	if vl and pew and cvdl then
		C_Timer.After(3, function()
			restoreLayouts()
		end)
	end
end)
