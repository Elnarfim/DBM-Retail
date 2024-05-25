--[===[@non-alpha@
do return end
--@end-non-alpha@]===]

---@class DBMGUI
local DBM_GUI = DBM_GUI

DBM_GUI.Cat_Development = DBM_GUI:CreateNewPanel("Development & Testing", "option")

local infoArea = DBM_GUI.Cat_Development:CreateArea("Development and Testing UI")
infoArea:CreateText("You are seeing this UI tab because you have an alpha or development build of DBM installed.", nil, true)

local testPanel = DBM_GUI.Cat_Development:CreateNewPanel("Tests", "option")

local slider = testPanel:CreateSlider("Time warp: %dx", 1, 500, 1, 400)
slider:SetPoint("TOPLEFT", testPanel.frame, "TOPLEFT", 20, -20)
slider:HookScript("OnValueChanged", function(self)
	local value = math.floor(self:GetValue())
	DBM.Options.TestDefaultTimewarpSpeed = value
	if DBM.Test.timeWarper then
		DBM.Test.timeWarper:SetSpeed(value)
	end
end)
slider:SetValue(DBM.Options.TestDefaultTimewarpSpeed)

local runButtons = {}

---@param tests TestDefinition[]
local function getTestDurationString(tests)
	local duration = 0
	for _, test in ipairs(tests) do
		duration = duration + test.log[#test.log][1] + 3.1 -- Tests wait 3.1 second for post-combat handlers (full event deregistration)
	end
	duration = math.floor(duration)
	local sec = duration % 60
	local min = math.floor(duration / 60)
	return ("%d:%02d"):format(min, sec)
end

---@param uiInfo TestUiInfo
---@param test TestDefinition
---@param result? TestResultEnum
local function setCombinedTestResults(uiInfo, test, result)
	if uiInfo.numTests == 1  and result == "Failure" then
		-- TODO: add flakiness detection here: did this succeed or fail in prior runs?
		test.uiInfo.statusText:SetText("Failed")
		test.uiInfo.statusText:SetTextColor(RED_FONT_COLOR:GetRGB())
		return
	end
	if result then
		uiInfo.childTestState[test] = result
	end
	local successCount = 0
	local failCount = 0
	for _, v in pairs(uiInfo.childTestState) do
		if v == "Success" then
			successCount = successCount + 1
		elseif v == "Failure" then
			failCount = failCount + 1
		end
	end
	uiInfo.statusText:SetFormattedText("%d/%d", successCount, uiInfo.numTests)
	if failCount > 0 then
		uiInfo.statusText:SetTextColor(RED_FONT_COLOR:GetRGB())
	elseif successCount == uiInfo.numTests then
		uiInfo.statusText:SetTextColor(GREEN_FONT_COLOR:GetRGB())
	else
		uiInfo.statusText:SetTextColor(ORANGE_FONT_COLOR:GetRGB())
	end
end

---@type TestDefinition[]
local queuedTests = {}

local stopButton = testPanel:CreateButton("Stop tests", 80, 30, function()
	DBM.Test:StopTests()
	for _, test in ipairs(queuedTests) do
		setCombinedTestResults(test.uiInfo, test)
	end
	for _, button in ipairs(runButtons) do
		button:Enable()
	end
end)
stopButton:SetPoint("TOPRIGHT", testPanel.frame, "TOPRIGHT", -10, -5)
stopButton:Hide()

---@param test TestDefinition
local function onTestStart(test)
	test.uiInfo.statusText:SetText("Running")
	test.uiInfo.statusText:SetTextColor(LIGHTBLUE_FONT_COLOR:GetRGB())
end

---@param results TestReporter
local function onTestFinish(test, results, testCount, numTests)
	if queuedTests[#queuedTests] == test then
		queuedTests[#queuedTests] = nil
	end
	local result = results:GetResult()
	for _, parent in ipairs(test.uiInfo.parents) do
		setCombinedTestResults(parent.uiInfo, test, result)
	end
	setCombinedTestResults(test.uiInfo, test, result)
	test.uiInfo.lastResults = results
	if results:HasDiff() then
		test.uiInfo.showDiffButton:Show()
	end
	if results:HasErrors() then
		test.uiInfo.showErrorsButton:Show()
	end
	if testCount == numTests then
		for _, button in ipairs(runButtons) do
			button:Enable()
		end
		stopButton:Hide()
	end
end

---@param event TestCallbackEvent
---@param test TestDefinition
local function testStatusCallback(event, test, ...)
	if event == "TestStart" then
		return onTestStart(test)
	else
		return onTestFinish(test, ...)
	end
end

local function onRunTestClicked(tests)
	return function()
		for _, button in ipairs(runButtons) do
			button:Disable()
		end
		stopButton:Show()
		for i = #tests, 1, -1 do
			local test = tests[i]
			queuedTests[#queuedTests + 1] = test
			test.uiInfo.showDiffButton:Hide()
			test.uiInfo.showErrorsButton:Hide()
			test.uiInfo.statusText:SetText("Queued")
			test.uiInfo.statusText:SetTextColor(BLUE_FONT_COLOR:GetRGB())
		end
		onTestStart(tests[1])
		DBM.Test:RunTests(tests, DBM.Options.TestDefaultTimewarpSpeed, testStatusCallback)
	end
end

local testYIndex = 1
---@param tests TestDefinition[]
---@return TestUiInfo
local function createTestEntry(testName, tests, parents, indentation)
	local yDistance = 22
	local yPos = -yDistance * testYIndex - 35
	testYIndex = testYIndex + 1
	local xOffset = indentation * 10
	---@class TestUiInfo
	local uiInfo = {
		parents = parents,
		numTests = #tests,
		---@type table<TestDefinition, TestResultEnum>
		childTestState = {}
	}

	local statusText = testPanel:CreateText("", 55, false)
	uiInfo.statusText = statusText
	if #tests > 0 then
		statusText:SetText("0/" .. #tests)
	end
	statusText:SetPoint("TOPLEFT", testPanel.frame, "TOPLEFT", 7, yPos)
	statusText:SetMaxLines(1)
	local nameText = testPanel:CreateText(testName, 400, false)
	nameText:SetPoint("TOPLEFT", testPanel.frame, "TOPLEFT", 60 + xOffset, yPos)
	nameText:SetMaxLines(1)
	local runButton = testPanel:CreateButton("Run", 40, 22, onRunTestClicked(tests))
	runButton.myheight = yDistance
	runButtons[#runButtons + 1] = runButton
	runButton:SetPoint("TOPRIGHT", testPanel.frame, "TOPRIGHT", -10, yPos)
	local durationText = testPanel:CreateText(getTestDurationString(tests), 50, false, nil, "RIGHT")
	durationText:SetPoint("RIGHT", runButton, "LEFT", -5, 0)
	if #tests == 1 then
		---@class TestDefinition
		local test = tests[1]
		local showDiffButton = testPanel:CreateButton("Show diff", 0, 22, function(self)
			if test.uiInfo.lastResults then
				test.uiInfo.lastResults:ReportDiff(true)
			end
		end)
		uiInfo.showDiffButton = showDiffButton
		showDiffButton:SetPoint("RIGHT", runButton, "LEFT", -50, 0)
		showDiffButton:Hide()
		local showErrorsButton = testPanel:CreateButton("Show errors", 0, 22, function(self)
			if test.uiInfo.lastResults then
				test.uiInfo.lastResults:ReportErrors()
			end
		end)
		uiInfo.showErrorsButton = showErrorsButton
		showErrorsButton:SetPoint("RIGHT", showDiffButton, "LEFT", -5, 0)
		showErrorsButton:Hide()
		uiInfo.lastResults = nil
		test.uiInfo = uiInfo
	end
	return uiInfo
end

---@param node TestTreeNode
local function gatherChildTests(node, result)
	result = result or {}
	for _, v in ipairs(node.children) do
		if v.test then
			result[#result + 1] = v.test
		end
		gatherChildTests(v, result)
	end
	return result
end

local function getParents(node)
	local result = {}
	while node.parent do
		result[#result + 1] = node.parent
		node = node.parent
	end
	return result
end

---@class node TestTreeNode
local function createTestTreeEntry(node)
	if node.test then
		node.uiInfo = createTestEntry(node.test.name, {node.test}, getParents(node), node.depth)
	end
	if node.count > 1 then
		local name = node.path == "" and "All tests" or (node.path .. "/*")
		node.uiInfo = createTestEntry(name, gatherChildTests(node), getParents(node), node.depth)
	end
	assert(not (node.test and node.count > 1))
	for _, v in ipairs(node.children) do
		createTestTreeEntry(v)
	end
end

---@class TestTreeNode
local root = {
	---@type TestTreeNode?
	parent = nil,
	---@type TestTreeNode[]
	children = {},
	---@type TestDefinition
	test = nil, -- Mutually exclusive with #children > 0, this this marks a leaf node.
	path = "",
	depth = 0,
	count = 0,
	---@type TestUiInfo
	uiInfo = nil,
	---@type table<string, TestTreeNode>
	entries = {} -- Only used during tree construction, do not use afterwards.
}

local function insertElement(node, depth, name, pathElements)
	node.count = (node.count or 0) + 1
	local path = pathElements[depth]
	if not node.entries[path] then
		local entry = {parent = node, entries = {}, path = table.concat(pathElements, "/", 1, depth), children = {}, depth = depth, count = 0}
		node.entries[path] = entry
		table.insert(node.children, entry)
	end
	if depth < #pathElements then
		insertElement(node.entries[path], depth + 1, name, pathElements)
	else
		node.entries[path].test = DBM.Test.Registry.tests[name]
		node.entries[path].count = (node.entries[path].count or 0) + 1
	end
end

local function decrementDepth(node)
	node.depth = node.depth - 1
	for _, v in ipairs(node.children) do
		decrementDepth(v)
	end
end

local function pruneTree(node)
	for k, v in ipairs(node.children) do
		if not v.test and #v.children == 1 then
			v.children[1].parent = v.children[1].parent.parent
			node.children[k] = v.children[1]
			decrementDepth(v.children[1])
		end
		pruneTree(v)
	end
end

local initialized
testPanel.frame:HookScript("OnShow", function(self)
	if initialized then return end
	initialized = true
	DBM.Test:LoadAllTests()
	if not DBM.Test:TestsLoaded() then
		local area = testPanel:CreateArea("No tests available")
		area:CreateText("Could not find any test definitions, check if DBM-Test-* mods are installed and enabled.", nil, true)
		return
	end
	for _, testName in ipairs(DBM.Test.Registry.sortedTests) do
		local pathElements = {string.split("/", testName)}
		insertElement(root, 1, testName, pathElements)
	end
	pruneTree(root)
	createTestTreeEntry(root)
end)
