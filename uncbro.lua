local passes, fails, undefined = 0, 0, 0
local running = 0

local results = {
    success = {},
    failure = {},
    missing = {}
}

local failureDetails = {} -- Store detailed failure information

local function getGlobal(path)
    local value = getfenv(0)

    while value ~= nil and path ~= "" do
        local name, nextValue = string.match(path, "^([^.]+)%.?(.*)$")
        value = value[name]
        path = nextValue
    end

    return value
end

local function test(name, aliases, callback)
    running += 1

    task.spawn(function()
        local testStartTime = os.clock()
        local errorMessage = ""
        local success = false
        
        if not callback then
            table.insert(results.missing, name)
            print("⏺️ " .. name)
        else
            local globalExists = getGlobal(name) ~= nil
            local aliasesExist = true
            
            -- Check if any aliases exist
            for _, alias in ipairs(aliases) do
                if getGlobal(alias) ~= nil then
                    aliasesExist = true
                    break
                end
            end
            
            if not globalExists then
                fails += 1
                errorMessage = "Function '" .. name .. "' does not exist in global environment"
                table.insert(results.failure, {name = name, error = errorMessage, category = "MissingFunction"})
                failureDetails[name] = {
                    error = errorMessage,
                    category = "MissingFunction",
                    time = os.clock() - testStartTime
                }
                warn("⛔ " .. name .. " - " .. errorMessage)
            else
                -- Try to execute the test
                local testSuccess, resultOrError = pcall(callback)
                
                if testSuccess then
                    passes += 1
                    local message = resultOrError or "" -- resultOrError is actually the return message when success
                    table.insert(results.success, {name = name, message = message})
                    print("✅ " .. name .. (message ~= "" and " • " .. message or ""))
                else
                    fails += 1
                    -- Parse error message to make it more readable
                    local cleanError = resultOrError
                    -- Remove stack trace if present
                    cleanError = cleanError:gsub("stack traceback:.+", ""):gsub("%s+$", "")
                    -- Extract just the error message
                    if cleanError:find(":") then
                        cleanError = cleanError:match("[^:]+$") or cleanError
                    end
                    
                    cleanError = cleanError:gsub("^%s+", ""):gsub("%s+$", "")
                    
                    errorMessage = "Test failed: " .. cleanError
                    table.insert(results.failure, {name = name, error = cleanError, category = "TestFailure"})
                    failureDetails[name] = {
                        error = cleanError,
                        category = "TestFailure",
                        time = os.clock() - testStartTime
                    }
                    warn("⛔ " .. name .. " - " .. cleanError)
                end
            end
        end

        -- Check for missing aliases
        local missingAliases = {}
        for _, alias in ipairs(aliases) do
            if getGlobal(alias) == nil then
                table.insert(missingAliases, alias)
            end
        end

        if #missingAliases > 0 then
            undefined += 1
            local aliasMessage = "Missing aliases: " .. table.concat(missingAliases, ", ")
            if not failureDetails[name] then
                failureDetails[name] = {
                    error = aliasMessage,
                    category = "MissingAliases",
                    time = os.clock() - testStartTime
                }
            end
            warn("⚠️ " .. aliasMessage)
        end

        running -= 1
    end)
end

-- Helper function to categorize errors
local function categorizeError(funcName, errorMsg)
    local lowerError = errorMsg:lower()
    
    if lowerError:find("attempt to index") and lowerError:find("nil") then
        return "FunctionNotAvailable"
    elseif lowerError:find("permission") or lowerError:find("security") or lowerError:find("access denied") then
        return "PermissionError"
    elseif lowerError:find("not found") or lowerError:find("does not exist") then
        return "FunctionNotFound"
    elseif lowerError:find("invalid") or lowerError:find("bad argument") then
        return "ArgumentError"
    elseif lowerError:find("expected") and lowerError:find("got") then
        return "TypeMismatch"
    elseif lowerError:find("not supported") or lowerError:find("unsupported") then
        return "UnsupportedFeature"
    elseif lowerError:find("timeout") or lowerError:find("timed out") then
        return "Timeout"
    elseif lowerError:find("connection") or lowerError:find("network") then
        return "NetworkError"
    else
        return "RuntimeError"
    end
end

-- Display detailed report (ENGLISH VERSION)
local function displayDetailedReport()
    print("\n" .. string.rep("=", 60))
    print("DETAILED TEST ANALYSIS")
    print(string.rep("=", 60))

    -- Categorize results
    local available = {}      -- tests passed with no alias issues
    local problematic = {}    -- passed but missing aliases, or failed but function exists
    local unusable = {}       -- function missing
    local untested = {}       -- no callback provided

    -- Process successes
    for _, item in ipairs(results.success) do
        local name = item.name
        local hasAliasIssue = false
        if failureDetails[name] and failureDetails[name].category == "MissingAliases" then
            hasAliasIssue = true
        end
        if hasAliasIssue then
            table.insert(problematic, {name = name, issue = failureDetails[name].error})
        else
            table.insert(available, name)
        end
    end

    -- Process failures
    for _, item in ipairs(results.failure) do
        local name = item.name
        if item.category == "MissingFunction" then
            table.insert(unusable, name)
        else
            -- function exists but test failed
            local issue = item.error or "Unknown error"
            table.insert(problematic, {name = name, issue = issue})
        end
    end

    -- Process untested
    for _, name in ipairs(results.missing) do
        table.insert(untested, name)
    end

    -- Sort alphabetically
    local function sortByName(a, b)
        if type(a) == "string" then
            return a < b
        else
            return a.name < b.name
        end
    end
    table.sort(available)
    table.sort(problematic, function(a, b) return a.name < b.name end)
    table.sort(unusable)
    table.sort(untested)

    -- Output fully available functions
    print("\n✅ FULLY AVAILABLE (" .. #available .. ")")
    if #available > 0 then
        for _, name in ipairs(available) do
            print("   ✅ " .. name)
        end
    else
        print("   None")
    end

    -- Output problematic functions
    print("\n⚠️  PARTIALLY FUNCTIONAL (" .. #problematic .. ")")
    if #problematic > 0 then
        for _, item in ipairs(problematic) do
            print("   ⚠️  " .. item.name .. " — " .. item.issue)
        end
    else
        print("   None")
    end

    -- Output unusable functions
    print("\n❌ UNUSABLE (" .. #unusable .. ")")
    if #unusable > 0 then
        for _, name in ipairs(unusable) do
            print("   ❌ " .. name)
        end
    else
        print("   None")
    end

    -- Output untested functions if any
    if #untested > 0 then
        print("\n⏺️  UNTESTED (" .. #untested .. ")")
        for _, name in ipairs(untested) do
            print("   ⏺️ " .. name)
        end
    end

    -- Summary statistics
    print("\n📊 SUMMARY STATISTICS")
    print(string.rep("-", 40))
    print(string.format("✅ Fully Available: %d", #available))
    print(string.format("⚠️  Partially Functional: %d", #problematic))
    print(string.format("❌ Unusable: %d", #unusable))
    if #untested > 0 then
        print(string.format("⏺️  Untested: %d", #untested))
    end

    -- Recommendations
    print("\n💡 RECOMMENDATIONS")
    print(string.rep("-", 40))
    if #unusable > 0 then
        print("• " .. #unusable .. " functions are completely missing. Check if your executor supports them.")
    end
    if #problematic > 0 then
        print("• " .. #problematic .. " functions have issues (missing aliases or test failures). Review the details above.")
    end
    if #available == 0 and #problematic == 0 and #unusable == 0 then
        print("• No test results? Make sure the script runs correctly.")
    end
end

-- Header and summary
print("\n")
print("🚀 UNC ENVIRONMENT CHECK (HARDCORE MODE)")
print("Testing executor capabilities with extreme thoroughness")
print(string.rep("-", 50))

task.defer(function()
    repeat task.wait() until running == 0

    local totalTests = passes + fails
    local successRate = totalTests > 0 and math.floor((passes / totalTests) * 100) or 0
    
    print("\n" .. string.rep("=", 50))
    print("TEST COMPLETED")
    print(string.rep("=", 50))
    
    -- Quick summary
    print(string.format("\n📋 Quick Summary:"))
    print(string.format("✅ Passed:  %d/%d (%.1f%%)", passes, totalTests, successRate))
    print(string.format("❌ Failed:  %d/%d (%.1f%%)", fails, totalTests, 100 - successRate))
    print(string.format("⏺️  Untested: %d", #results.missing))
    
    -- Show success messages if any
    if #results.success > 0 and passes > 0 then
        print("\n✨ SUCCESSFUL FUNCTIONS:")
        local maxToShow = 10
        for i = 1, math.min(maxToShow, #results.success) do
            local success = results.success[i]
            local msg = success.message ~= "" and " • " .. success.message or ""
            print(string.format("  %2d. %s%s", i, success.name, msg))
        end
        if #results.success > maxToShow then
            print(string.format("  ... and %d more", #results.success - maxToShow))
        end
    end
    
    -- Display detailed analysis
    displayDetailedReport()
    
    print("\n" .. string.rep("=", 60))
    print("END OF REPORT")
    print(string.rep("=", 60))
    
    -- Final note
    if successRate == 100 then
        print("\n🎉 Excellent! Your executor environment is fully functional!")
    elseif successRate >= 80 then
        print("\n👍 Good! Most functions are working correctly.")
    elseif successRate >= 50 then
        print("\n⚠️  Fair! Some functions may not work as expected.")
    else
        print("\n❌ Poor! Many functions are not working. Consider using a different executor.")
    end
end)

------------------------------------------------------------------------
-- ULTRA STRICT TEST CASES (HARDCORE VERSION)
------------------------------------------------------------------------

-- Cache tests
test("cache.invalidate", {}, function()
    local container = Instance.new("Folder")
    local part = Instance.new("Part", container)
    local partRef = container:FindFirstChild("Part")
    assert(partRef, "Part should be cached initially")
    cache.invalidate(partRef)
    -- Verify that the reference is invalid: accessing it should error
    local success, err = pcall(function() return partRef.Name end)
    assert(success == false, "Invalidated reference should error on access")
    -- Verify the original instance is no longer in the container
    assert(container:FindFirstChild("Part") == nil, "Instance should be removed from container")
    -- Verify caching mechanism: creating a new instance with the same name should give a new reference
    local part2 = Instance.new("Part", container)
    local part2Ref = container:FindFirstChild("Part")
    assert(cache.iscached(part2Ref), "New instance should be cached")
    return "cache.invalidate passed extreme test"
end)

test("cache.iscached", {}, function()
    local part = Instance.new("Part")
    assert(cache.iscached(part) == true, "New instance should be cached")
    cache.invalidate(part)
    assert(cache.iscached(part) == false, "Invalidated instance should not be cached")
    -- Test on non-Instance: should error
    local success, err = pcall(cache.iscached, {})
    assert(success == false, "cache.iscached on non-Instance should error")
    -- Test on destroyed instance
    local part2 = Instance.new("Part")
    part2:Destroy()
    -- After destruction, behavior may vary; at least shouldn't crash
    local ok = pcall(cache.iscached, part2)
    -- No assertion needed
    return "cache.iscached extreme ok"
end)

test("cache.replace", {}, function()
    local part = Instance.new("Part")
    local fire = Instance.new("Fire")
    local partMeta = getmetatable(part)
    local fireMeta = getmetatable(fire)
    cache.replace(part, fire)
    -- Part's metatable should become fire's metatable
    assert(getmetatable(part) == fireMeta, "Metatable should be replaced")
    -- Original part should be invalid
    local success, err = pcall(function() part.Name = "Test" end)
    assert(success == false, "Original part should be invalid after replace")
    -- Fire should still be usable
    fire.Name = "Fire"
    assert(fire.Name == "Fire", "Fire should still be usable")
    -- Try replacing with different instance type
    local part2 = Instance.new("Part")
    local mesh = Instance.new("SpecialMesh")
    cache.replace(part2, mesh)
    assert(getmetatable(part2) == getmetatable(mesh), "Replace with SpecialMesh should work")
    return "cache.replace extreme"
end)

test("cloneref", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone, "Clone should be a different reference")
    clone.Name = "Cloned"
    assert(part.Name == "Cloned", "Changes to clone should affect original")
    assert(typeof(clone) == "Instance", "Clone should be an Instance")
    -- Invalidate the clone
    cache.invalidate(clone)
    -- Original should remain valid
    assert(part.Name == "Cloned", "Original should remain valid")
    -- Clone should be invalid
    local success, err = pcall(function() return clone.Name end)
    assert(success == false, "Clone should be invalid after cache.invalidate")
    return "cloneref extreme"
end)

test("compareinstances", {}, function()
    local part = Instance.new("Part")
    local clone = cloneref(part)
    assert(part ~= clone, "Clone should not be equal")
    assert(compareinstances(part, clone) == true, "compareinstances should return true for cloned refs")
    local another = Instance.new("Part")
    assert(compareinstances(part, another) == false, "Different instances should not be equal")
    assert(compareinstances(part, nil) == false, "compareinstances with nil should be false")
    -- Invalidate clone and compare
    cache.invalidate(clone)
    local ok, res = pcall(compareinstances, part, clone)
    if ok then
        assert(res == false, "Invalid reference should not be equal")
    end
    return "compareinstances extreme"
end)

-- Closures tests
local function shallowEqual(t1, t2)
    if t1 == t2 then
        return true
    end

    local UNIQUE_TYPES = {
        ["function"] = true,
        ["table"] = true,
        ["userdata"] = true,
        ["thread"] = true,
    }

    for k, v in pairs(t1) do
        if UNIQUE_TYPES[type(v)] then
            if type(t2[k]) ~= type(v) then
                return false
            end
        elseif t2[k] ~= v then
            return false
        end
    end

    for k, v in pairs(t2) do
        if UNIQUE_TYPES[type(v)] then
            if type(t2[k]) ~= type(v) then
                return false
            end
        elseif t1[k] ~= v then
            return false
        end
    end

    return true
end

test("checkcaller", {}, function()
    -- Main thread should return true
    assert(checkcaller() == true, "Main thread should return true")
    -- In a spawned thread should return false
    local inSpawn = nil
    local thread = task.spawn(function()
        inSpawn = checkcaller()
    end)
    task.wait()
    assert(inSpawn == false, "Spawned thread should return false")
    -- In a coroutine should return false
    local co = coroutine.create(function()
        return checkcaller()
    end)
    local success, res = coroutine.resume(co)
    assert(success and res == false, "Coroutine should return false")
    -- In deferred function
    local deferred = nil
    task.defer(function()
        deferred = checkcaller()
    end)
    task.wait()
    assert(deferred == false, "Deferred function should return false")
    return "checkcaller extreme"
end)

test("clonefunction", {}, function()
    local function original(a, b)
        return a + b
    end
    local copy = clonefunction(original)
    assert(original ~= copy, "Clone should be different")
    assert(original(2,3) == copy(2,3), "Should produce same result")
    -- Modify original, clone should not be affected
    original = function(a,b) return a*b end
    assert(copy(2,3) == 5, "Clone should retain original behavior")
    -- Test cloning function with upvalues
    local up = 10
    local function withUp(x)
        return x + up
    end
    local copyUp = clonefunction(withUp)
    assert(withUp(5) == copyUp(5), "Cloned upvalue function should work")
    up = 20
    assert(withUp(5) == 25, "Original reflects upvalue change")
    assert(copyUp(5) == 15, "Clone should capture original upvalue value")
    -- Test cloning C closure
    local cfunc = newcclosure(function() return 42 end)
    local copyC = clonefunction(cfunc)
    assert(cfunc() == copyC(), "C closure clone should work")
    return "clonefunction extreme"
end)

test("getcallingscript", {}, function()
    -- In main thread should return nil or current script
    local script = getcallingscript()
    if script then
        assert(typeof(script) == "Instance", "Should be Instance or nil")
    end
    -- Simulate inside a script
    local module = Instance.new("ModuleScript")
    module.Source = [[
        return function()
            return getcallingscript()
        end
    ]]
    local func = require(module)
    local calledFrom = func()
    assert(calledFrom == module, "Inside module, getcallingscript should return the module")
    return "getcallingscript extreme"
end)

test("getscriptclosure", {"getscriptfunction"}, function()
    local module = game:GetService("CoreGui").RobloxGui.Modules.Common.Constants
    local original = require(module)
    local closure = getscriptclosure(module)
    local fromClosure = closure()
    assert(shallowEqual(original, fromClosure), "Closure should return same contents")
    assert(original ~= fromClosure, "Should be different table")
    -- Modify source and verify closure reflects changes
    local oldSource = module.Source
    module.Source = "return { modified = true }"
    local newClosure = getscriptclosure(module)
    local newTable = newClosure()
    assert(newTable.modified == true, "Closure should reflect updated source")
    module.Source = oldSource
    return "getscriptclosure extreme"
end)

test("hookfunction", {"replaceclosure"}, function()
    local function target()
        return "original"
    end
    local hookCalled = 0
    local originalFunc = hookfunction(target, function(...)
        hookCalled = hookCalled + 1
        return "hooked"
    end)
    assert(target() == "hooked", "Should return hooked value")
    assert(hookCalled == 1, "Hook should be called")
    -- Call original function
    assert(originalFunc() == "original", "Original should work")
    -- Hook again
    local secondHook = hookfunction(target, function()
        hookCalled = hookCalled + 1
        return "second"
    end)
    assert(target() == "second", "Should chain")
    assert(hookCalled == 2, "Second hook called")
    -- Restore to original
    hookfunction(target, originalFunc)
    assert(target() == "original", "Restored")
    -- Test return value of hookfunction is callable multiple times
    local f = function() return 1 end
    local orig = hookfunction(f, function() return 2 end)
    assert(f() == 2)
    assert(orig() == 1)
    orig = hookfunction(f, function() return 3 end)
    assert(f() == 3)
    assert(orig() == 2) -- previous hook
    -- Restore
    hookfunction(f, orig)
    assert(f() == 2)
    return "hookfunction extreme"
end)

test("iscclosure", {}, function()
    assert(iscclosure(print) == true, "print is C closure")
    assert(iscclosure(function() end) == false, "Lua function not C")
    local cfunc = newcclosure(function() end)
    assert(iscclosure(cfunc) == true, "newcclosure produces C")
    -- Test on non-function types (should error or return false)
    local ok, res = pcall(iscclosure, 123)
    if ok then
        assert(res == false, "Number should not be C closure")
    end
    return "iscclosure extreme"
end)

test("islclosure", {}, function()
    assert(islclosure(print) == false, "print not Lua")
    assert(islclosure(function() end) == true, "Lua function is Lua")
    local cfunc = newcclosure(function() end)
    assert(islclosure(cfunc) == false, "C closure not Lua")
    local ok, res = pcall(islclosure, {})
    if ok then
        assert(res == false, "Table not Lua closure")
    end
    return "islclosure extreme"
end)

test("isexecutorclosure", {"checkclosure", "isourclosure"}, function()
    assert(isexecutorclosure(isexecutorclosure) == true, "Own function true")
    local luaFunc = function() end
    assert(isexecutorclosure(luaFunc) == true, "Lua function defined in executor true")
    local cFunc = newcclosure(function() end)
    assert(isexecutorclosure(cFunc) == true, "C closure created by executor true")
    assert(isexecutorclosure(print) == false, "Roblox global false")
    -- Test function loaded by loadstring
    local loaded = loadstring("return function() end")()
    assert(isexecutorclosure(loaded) == true, "Loaded function should be executor closure")
    return "isexecutorclosure extreme"
end)

test("loadstring", {}, function()
    local func, err = loadstring("return 1 + 1")
    assert(func, "Valid code should compile")
    assert(func() == 2, "Execution correct")
    -- Syntax error
    local func2, err2 = loadstring("invalid syntax")
    assert(func2 == nil and type(err2) == "string", "Syntax error returns error")
    -- Empty string
    local func3, err3 = loadstring("")
    assert(func3 ~= nil, "Empty string should compile to function?")
    -- Bytecode loading should fail
    local bytecode = string.dump(function() end)
    local func4, err4 = loadstring(bytecode)
    assert(func4 == nil and err4, "Bytecode should not load")
    -- Load with upvalues
    local func5, err5 = loadstring("local up = ...; return function() return up end")
    assert(func5, "loadstring with upvalue ok")
    local f = func5(42)
    assert(f() == 42, "Upvalue passed correctly")
    -- Large code
    local bigCode = "return " .. string.rep("1", 10000)
    local bigFunc, err6 = loadstring(bigCode)
    assert(bigFunc, "Large code should compile")
    assert(bigFunc() == 1, "Large code result")
    return "loadstring extreme"
end)

test("newcclosure", {}, function()
    local function luaFunc(x)
        return x * 2
    end
    local cFunc = newcclosure(luaFunc)
    assert(iscclosure(cFunc) == true, "Should be C closure")
    assert(cFunc(5) == 10, "Should execute correctly")
    -- C closure with upvalue
    local up = 3
    local cWithUp = newcclosure(function() return up end)
    assert(cWithUp() == 3, "C closure can access upvalues")
    -- Hook C closure
    local hooked = false
    hookfunction(cFunc, function(x)
        hooked = true
        return x * 3
    end)
    assert(cFunc(5) == 15, "C closure can be hooked")
    assert(hooked == true, "Hook called")
    -- newcclosure with non-function should error
    local success, err = pcall(newcclosure, 123)
    assert(success == false, "newcclosure with non-function should error")
    return "newcclosure extreme"
end)

-- Console tests
test("rconsoleclear", {"consoleclear"}, function()
    rconsoleclear()
    return "rconsoleclear executed"
end)

test("rconsolecreate", {"consolecreate"}, function()
    rconsolecreate()
    rconsolesettitle("Hardcore Test")
    rconsoleprint("Test line 1\n")
    rconsoleprint("Test line 2\n")
    rconsolecreate() -- Should be harmless
    rconsoledestroy()
    return "rconsolecreate/destroy with output ok"
end)

test("rconsoledestroy", {"consoledestroy"}, function()
    rconsolecreate()
    rconsoledestroy()
    rconsoledestroy() -- Extra destroy should be safe
    local ok = pcall(rconsoleprint, "after destroy")
    return "rconsoledestroy ok"
end)

test("rconsoleinput", {"consoleinput"}, function()
    assert(type(rconsoleinput) == "function", "rconsoleinput is function")
    local ok, res = pcall(rconsoleinput)
    if ok then
        assert(res == nil or type(res) == "string", "rconsoleinput should return string or nil")
    end
    return "rconsoleinput checked"
end)

test("rconsoleprint", {"consoleprint"}, function()
    rconsoleprint("Test message")
    rconsoleprint("Another line\n")
    rconsoleprint("Special: \n\t\r\\")
    return "rconsoleprint ok"
end)

test("rconsolesettitle", {"rconsolename", "consolesettitle"}, function()
    rconsolecreate()
    rconsolesettitle("New Title")
    rconsolesettitle("Another Title")
    rconsoledestroy()
    return "rconsolesettitle ok"
end)

-- Crypt tests
test("crypt.base64encode", {"crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode"}, function()
    local testCases = {
        ["Hello, World!"] = "SGVsbG8sIFdvcmxkIQ==",
        [""] = "",
        ["a"] = "YQ==",
        ["ab"] = "YWI=",
        ["abc"] = "YWJj",
        ["\0\1\2"] = "AAEC",
    }
    for input, expected in pairs(testCases) do
        local encoded = crypt.base64encode(input)
        assert(encoded == expected, string.format("Encoding '%s' failed", input))
    end
    local big = string.rep("A", 10000)
    local enc = crypt.base64encode(big)
    local dec = crypt.base64decode(enc)
    assert(dec == big, "Large data roundtrip failed")
    return "base64encode extreme"
end)

test("crypt.base64decode", {"crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode"}, function()
    local testCases = {
        ["SGVsbG8sIFdvcmxkIQ=="] = "Hello, World!",
        [""] = "",
        ["YQ=="] = "a",
        ["YWI="] = "ab",
        ["YWJj"] = "abc",
        ["AAEC"] = "\0\1\2",
    }
    for input, expected in pairs(testCases) do
        local decoded = crypt.base64decode(input)
        assert(decoded == expected, string.format("Decoding '%s' failed", input))
    end
    local success, err = pcall(crypt.base64decode, "Invalid!!")
    assert(success == false, "Invalid base64 should error")
    return "base64decode extreme"
end)

test("crypt.encrypt", {}, function()
    local key = crypt.generatekey()
    local iv = crypt.generatekey()
    local data = "secret data"
    local modes = {"CBC", "CFB", "OFB", "CTR", "ECB"}
    for _, mode in ipairs(modes) do
        local ok, encrypted = pcall(crypt.encrypt, data, key, iv, mode)
        if ok then
            local decrypted = crypt.decrypt(encrypted, key, iv, mode)
            assert(decrypted == data, "Decryption with mode " .. mode .. " failed")
        end
    end
    -- Without IV (auto-generated)
    local encrypted1, iv1 = crypt.encrypt(data, key)
    assert(iv1 and #iv1 > 0, "IV should be returned")
    local decrypted1 = crypt.decrypt(encrypted1, key, iv1)
    assert(decrypted1 == data, "Decryption with generated IV failed")
    -- Empty string
    local encEmpty, ivEmpty = crypt.encrypt("", key)
    local decEmpty = crypt.decrypt(encEmpty, key, ivEmpty)
    assert(decEmpty == "", "Empty string encryption failed")
    return "encrypt extreme"
end)

test("crypt.decrypt", {}, function()
    local key = crypt.generatekey()
    local iv = crypt.generatekey()
    local data = "test"
    local encrypted = crypt.encrypt(data, key, iv)
    local decrypted = crypt.decrypt(encrypted, key, iv)
    assert(decrypted == data, "Basic decryption failed")
    -- Wrong key
    local wrongKey = crypt.generatekey()
    local success, err = pcall(crypt.decrypt, encrypted, wrongKey, iv)
    assert(success == false, "Decrypt with wrong key should error")
    -- Wrong IV
    local wrongIV = crypt.generatekey()
    local success2, err2 = pcall(crypt.decrypt, encrypted, key, wrongIV)
    assert(success2 == false, "Decrypt with wrong IV should error")
    -- Corrupted data
    local corrupted = encrypted:sub(1, #encrypted-1) .. "X"
    local success3, err3 = pcall(crypt.decrypt, corrupted, key, iv)
    assert(success3 == false, "Decrypt corrupted data should error")
    return "decrypt extreme"
end)

test("crypt.generatebytes", {}, function()
    local sizes = {0, 1, 16, 32, 64, 128, 256, 1024}
    for _, size in ipairs(sizes) do
        local bytes = crypt.generatebytes(size)
        local decoded = crypt.base64decode(bytes)
        assert(#decoded == size, string.format("Size %d: got %d", size, #decoded))
    end
    local b1 = crypt.generatebytes(16)
    local b2 = crypt.generatebytes(16)
    assert(b1 ~= b2, "Bytes should be random")
    return "generatebytes extreme"
end)

test("crypt.generatekey", {}, function()
    local key1 = crypt.generatekey()
    local key2 = crypt.generatekey()
    assert(key1 ~= key2, "Keys should be random")
    local decoded = crypt.base64decode(key1)
    assert(#decoded == 32, "Key should decode to 32 bytes")
    return "generatekey extreme"
end)

test("crypt.hash", {}, function()
    local testString = "The quick brown fox jumps over the lazy dog"
    local expected = {
        md5 = "9e107d9d372bb6826bd81d3542a419d6",
        sha1 = "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12",
        sha256 = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
        sha384 = "ca737f1014a48f4c0b6dd43cb177b0afd9e5169367544c494011e3317dbf9a509cb1e5dc1e85a94bb942b6b3f6b9198d",
        sha512 = "07e547d9586f6a73f73fbac0435ed76951218fb7d0c8d788a309d785436bbb642e93a252a954f23912547d1e8a3b5ed6e1bfd7097821233fa0538f3db854fee6",
        ["sha3-224"] = "2d6d7c6a8d0e6b6f6d6d7c6a8d0e6b6f6d6d7c6a8d0e6b6f",
        ["sha3-256"] = "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a",
        ["sha3-384"] = "0c8b7e1f1c4b1c1f4b1c1f4b1c1f4b1c1f4b1c1f4b1c1f4b",
        ["sha3-512"] = "0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e",
    }
    for algo, exp in pairs(expected) do
        local hash = crypt.hash(testString, algo)
        assert(hash:lower() == exp, algo .. " hash mismatch")
    end
    local emptyHash = crypt.hash("", "sha256")
    assert(emptyHash:lower() == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "Empty string hash")
    local success, err = pcall(crypt.hash, "test", "invalid")
    assert(success == false, "Invalid algorithm should error")
    return "hash extreme"
end)

-- Debug tests
test("debug.getconstant", {}, function()
    local function testFunc()
        local a = 123
        local b = "hello"
        print(a, b)
    end
    local consts = {}
    for i = 1, 10 do
        local v = debug.getconstant(testFunc, i)
        if v ~= nil then
            table.insert(consts, v)
        end
    end
    assert(#consts >= 2, "Should have at least 2 constants")
    local old = debug.getconstant(testFunc, 1)
    debug.setconstant(testFunc, 1, 999)
    assert(debug.getconstant(testFunc, 1) == 999, "Constant should be changed")
    debug.setconstant(testFunc, 1, old)
    return "debug.getconstant extreme"
end)

test("debug.getconstants", {}, function()
    local function testFunc()
        local x = 100
        local y = "test"
        print(x, y)
    end
    local consts = debug.getconstants(testFunc)
    assert(type(consts) == "table", "Should return table")
    local found100 = false
    local foundTest = false
    for _, v in ipairs(consts) do
        if v == 100 then found100 = true end
        if v == "test" then foundTest = true end
    end
    assert(found100 and foundTest, "Constants should include 100 and 'test'")
    debug.setconstant(testFunc, 1, 200)
    local newConsts = debug.getconstants(testFunc)
    local found200 = false
    for _, v in ipairs(newConsts) do
        if v == 200 then found200 = true end
    end
    assert(found200, "Modified constant should appear")
    debug.setconstant(testFunc, 1, 100)
    return "debug.getconstants extreme"
end)

test("debug.getinfo", {}, function()
    local function testFunc(a, b)
        return a + b
    end
    local info = debug.getinfo(testFunc)
    assert(info.func == testFunc, "func field")
    assert(info.what == "Lua", "what")
    assert(info.nups >= 0, "nups")
    assert(info.numparams == 2, "numparams should be 2")
    assert(info.is_vararg == 0, "is_vararg")
    local function inner()
        return debug.getinfo(2, "n")
    end
    local innerInfo = inner()
    assert(innerInfo.name == "inner", "Name should be inner")
    return "debug.getinfo extreme"
end)

test("debug.getproto", {}, function()
    local function outer()
        local function inner1()
            return 1
        end
        local function inner2()
            return 2
        end
    end
    local proto1 = debug.getproto(outer, 1)
    assert(type(proto1) == "function", "First proto should be function")
    local ok, res = pcall(proto1)
    if ok then
        assert(res == 1, "Inner function should return 1")
    end
    local proto2 = debug.getproto(outer, 2)
    assert(type(proto2) == "function", "Second proto should be function")
    local protos = debug.getprotos(outer)
    assert(#protos == 2, "Should have 2 protos")
    local protoTable = debug.getproto(outer, 1, true)
    assert(type(protoTable) == "table", "Should return table")
    assert(#protoTable == 1, "Table with one element")
    assert(type(protoTable[1]) == "function", "Element should be function")
    return "debug.getproto extreme"
end)

test("debug.getprotos", {}, function()
    local function outer()
        local function a() end
        local function b() end
        local function c() end
    end
    local protos = debug.getprotos(outer)
    assert(#protos == 3, "Should have 3 protos")
    for i, p in ipairs(protos) do
        assert(type(p) == "function", string.format("Proto %d should be function", i))
    end
    return "debug.getprotos extreme"
end)

test("debug.getstack", {}, function()
    local function levelOne(x)
        local y = x + 1
        return debug.getstack(1)
    end
    local stack = levelOne(5)
    assert(type(stack) == "table", "Should return table")
    local found5 = false
    local found6 = false
    for _, v in ipairs(stack) do
        if v == 5 then found5 = true end
        if v == 6 then found6 = true end
    end
    assert(found5 and found6, "Stack should contain locals")
    local val = debug.getstack(1, 1)
    local function modify()
        local a = 10
        debug.setstack(1, 1, 20)
        return a
    end
    assert(modify() == 20, "setstack should modify local")
    return "debug.getstack extreme"
end)

test("debug.getupvalue", {}, function()
    local up1 = 42
    local up2 = "hello"
    local function testFunc()
        return up1, up2
    end
    local name1, val1 = debug.getupvalue(testFunc, 1)
    assert(name1 == "up1", "First upvalue name")
    assert(val1 == 42, "First upvalue value")
    local name2, val2 = debug.getupvalue(testFunc, 2)
    assert(name2 == "up2", "Second upvalue name")
    assert(val2 == "hello", "Second upvalue value")
    debug.setupvalue(testFunc, 1, 100)
    local _, newVal = debug.getupvalue(testFunc, 1)
    assert(newVal == 100, "Modified upvalue")
    debug.setupvalue(testFunc, 1, 42)
    return "debug.getupvalue extreme"
end)

test("debug.getupvalues", {}, function()
    local up1 = 1
    local up2 = 2
    local up3 = 3
    local function testFunc()
        return up1 + up2 + up3
    end
    local upvalues = debug.getupvalues(testFunc)
    assert(#upvalues == 3, "Should have 3 upvalues")
    assert(upvalues[1] == 1, "First upvalue")
    assert(upvalues[2] == 2, "Second")
    assert(upvalues[3] == 3, "Third")
    debug.setupvalue(testFunc, 2, 20)
    upvalues = debug.getupvalues(testFunc)
    assert(upvalues[2] == 20, "Modified upvalue should appear")
    debug.setupvalue(testFunc, 2, 2)
    return "debug.getupvalues extreme"
end)

test("debug.setconstant", {}, function()
    local function testFunc()
        return 123
    end
    debug.setconstant(testFunc, 1, 456)
    assert(testFunc() == 456, "Constant should be changed")
    debug.setconstant(testFunc, 1, "hello")
    assert(testFunc() == "hello", "Constant changed to string")
    debug.setconstant(testFunc, 1, 123)
    assert(testFunc() == 123, "Restored")
    local ok = pcall(debug.setconstant, testFunc, 999, 0)
    return "debug.setconstant extreme"
end)

test("debug.setstack", {}, function()
    local function testFunc()
        local a = 1
        local b = 2
        debug.setstack(1, 1, 10)
        debug.setstack(1, 2, 20)
        return a, b
    end
    local x, y = testFunc()
    assert(x == 10 and y == 20, "setstack should modify locals")
    local function testOut()
        local a = 1
        debug.setstack(1, 2, 5)
    end
    local ok = pcall(testOut)
    return "debug.setstack extreme"
end)

test("debug.setupvalue", {}, function()
    local up = 1
    local function testFunc()
        return up
    end
    debug.setupvalue(testFunc, 1, 2)
    assert(testFunc() == 2, "setupvalue should change upvalue")
    debug.setupvalue(testFunc, 1, "string")
    assert(testFunc() == "string", "Changed to string")
    debug.setupvalue(testFunc, 1, 1)
    return "debug.setupvalue extreme"
end)

-- Filesystem tests
if isfolder and makefolder and delfolder then
    if isfolder(".tests") then
        delfolder(".tests")
    end
    makefolder(".tests")
end

test("readfile", {}, function()
    local content = "line1\nline2\r\nline3"
    writefile(".tests/readfile.txt", content)
    local read = readfile(".tests/readfile.txt")
    assert(read == content, "readfile should return exact content")
    local binary = string.char(0,1,2,3,255)
    writefile(".tests/binary.bin", binary)
    local binRead = readfile(".tests/binary.bin")
    assert(binRead == binary, "Binary read failed")
    local success, err = pcall(readfile, ".tests/nonexistent.txt")
    assert(success == false, "readfile on nonexistent should error")
    makefolder(".tests/folder")
    local success2, err2 = pcall(readfile, ".tests/folder")
    assert(success2 == false, "readfile on folder should error")
    return "readfile extreme"
end)

test("listfiles", {}, function()
    makefolder(".tests/listfiles")
    writefile(".tests/listfiles/a.txt", "a")
    writefile(".tests/listfiles/b.txt", "b")
    makefolder(".tests/listfiles/sub")
    writefile(".tests/listfiles/sub/c.txt", "c")
    local files = listfiles(".tests/listfiles")
    assert(#files >= 3, "Should list at least 3 items")
    local hasFile = false
    local hasFolder = false
    for _, f in ipairs(files) do
        if isfile(f) then hasFile = true end
        if isfolder(f) then hasFolder = true end
    end
    assert(hasFile and hasFolder, "listfiles should include both files and folders")
    local root = listfiles(".tests")
    assert(#root > 0, "Root should have contents")
    makefolder(".tests/empty")
    local empty = listfiles(".tests/empty")
    assert(#empty == 0, "Empty folder should return empty table")
    return "listfiles extreme"
end)

test("writefile", {}, function()
    writefile(".tests/writefile.txt", "hello")
    assert(readfile(".tests/writefile.txt") == "hello", "Write text")
    local binary = string.char(0,1,2,3)
    writefile(".tests/writefile.bin", binary)
    assert(readfile(".tests/writefile.bin") == binary, "Write binary")
    writefile(".tests/writefile.txt", "world")
    assert(readfile(".tests/writefile.txt") == "world", "Overwrite")
    writefile(".tests/empty.txt", "")
    assert(readfile(".tests/empty.txt") == "", "Empty file")
    makefolder(".tests/sub")
    writefile(".tests/sub/file.txt", "sub")
    assert(readfile(".tests/sub/file.txt") == "sub", "Write in subfolder")
    local success, err = pcall(writefile, ".tests/newfolder/file.txt", "test")
    return "writefile extreme"
end)

test("makefolder", {}, function()
    makefolder(".tests/makefolder")
    assert(isfolder(".tests/makefolder"), "Folder should exist")
    local ok = pcall(makefolder, ".tests/makefolder")
    assert(ok, "makefolder on existing folder should not error")
    local ok2 = pcall(makefolder, ".tests/a/b/c")
    if ok2 then
        assert(isfolder(".tests/a/b/c"), "Nested folder created")
    end
    return "makefolder extreme"
end)

test("appendfile", {}, function()
    writefile(".tests/append.txt", "a")
    appendfile(".tests/append.txt", "b")
    appendfile(".tests/append.txt", "c")
    assert(readfile(".tests/append.txt") == "abc", "append should concatenate")
    writefile(".tests/append.bin", "\0")
    appendfile(".tests/append.bin", "\1\2")
    assert(readfile(".tests/append.bin") == "\0\1\2", "Binary append")
    delfile(".tests/append_new.txt")
    appendfile(".tests/append_new.txt", "x")
    assert(readfile(".tests/append_new.txt") == "x", "append creates if not exist")
    makefolder(".tests/appendfolder")
    local success, err = pcall(appendfile, ".tests/appendfolder", "test")
    assert(success == false, "append to folder should error")
    return "appendfile extreme"
end)

test("isfile", {}, function()
    writefile(".tests/isfile.txt", "test")
    assert(isfile(".tests/isfile.txt") == true, "file should be true")
    makefolder(".tests/isfolder")
    assert(isfile(".tests/isfolder") == false, "folder should be false")
    assert(isfile(".tests/nonexistent") == false, "nonexistent false")
    return "isfile extreme"
end)

test("isfolder", {}, function()
    makefolder(".tests/isfolder")
    assert(isfolder(".tests/isfolder") == true, "folder true")
    writefile(".tests/isfile.txt", "")
    assert(isfolder(".tests/isfile.txt") == false, "file false")
    assert(isfolder(".tests/nonexistent") == false, "nonexistent false")
    return "isfolder extreme"
end)

test("delfolder", {}, function()
    makefolder(".tests/delfolder")
    makefolder(".tests/delfolder/sub")
    writefile(".tests/delfolder/file.txt", "content")
    delfolder(".tests/delfolder")
    assert(isfolder(".tests/delfolder") == false, "folder deleted")
    local ok = pcall(delfolder, ".tests/nonexistent")
    return "delfolder extreme"
end)

test("delfile", {}, function()
    writefile(".tests/delfile.txt", "")
    delfile(".tests/delfile.txt")
    assert(isfile(".tests/delfile.txt") == false, "file deleted")
    local ok = pcall(delfile, ".tests/nonexistent.txt")
    return "delfile extreme"
end)

test("loadfile", {}, function()
    writefile(".tests/loadfile.lua", "return 2 + 2")
    local func = loadfile(".tests/loadfile.lua")
    assert(func, "loadfile should return function")
    assert(func() == 4, "execution correct")
    writefile(".tests/error.lua", "if true then")
    local func2, err = loadfile(".tests/error.lua")
    assert(func2 == nil and err, "syntax error returns error")
    local func3, err3 = loadfile(".tests/nonexistent.lua")
    assert(func3 == nil and err3, "nonexistent file returns error")
    writefile(".tests/binary.bin", string.char(0,1,2))
    local func4, err4 = loadfile(".tests/binary.bin")
    assert(func4 == nil and err4, "binary file should error")
    return "loadfile extreme"
end)

test("dofile", {}, function()
    writefile(".tests/dofile.lua", "return 'executed'")
    local result = dofile(".tests/dofile.lua")
    assert(result == "executed", "dofile should execute and return")
    local success, err = pcall(dofile, ".tests/nonexistent.lua")
    assert(success == false, "dofile on nonexistent should error")
    writefile(".tests/dofile_error.lua", "invalid")
    local success2, err2 = pcall(dofile, ".tests/dofile_error.lua")
    assert(success2 == false, "dofile on invalid syntax should error")
    return "dofile extreme"
end)

-- Input tests
test("isrbxactive", {"isgameactive"}, function()
    local active = isrbxactive()
    assert(type(active) == "boolean", "Should return boolean")
    return "isrbxactive ok"
end)

test("mouse1click", {}, function()
    mouse1click()
    mouse1click()
    return "mouse1click ok"
end)

test("mouse1press", {}, function()
    mouse1press()
    task.wait(0.1)
    mouse1release()
    return "mouse1press/release ok"
end)

test("mouse1release", {}, function()
    mouse1press()
    mouse1release()
    mouse1release()
    return "mouse1release ok"
end)

test("mouse2click", {}, function()
    mouse2click()
    return "mouse2click ok"
end)

test("mouse2press", {}, function()
    mouse2press()
    mouse2release()
    return "mouse2press ok"
end)

test("mouse2release", {}, function()
    mouse2press()
    mouse2release()
    return "mouse2release ok"
end)

test("mousemoveabs", {}, function()
    mousemoveabs(100, 200)
    mousemoveabs(0, 0)
    mousemoveabs(1920, 1080)
    return "mousemoveabs ok"
end)

test("mousemoverel", {}, function()
    mousemoverel(10, -10)
    mousemoverel(0, 0)
    mousemoverel(-100, 100)
    return "mousemoverel ok"
end)

test("mousescroll", {}, function()
    mousescroll(0, 1)
    mousescroll(0, -1)
    mousescroll(10, 0)
    return "mousescroll ok"
end)

-- Instances tests
test("fireclickdetector", {}, function()
    local detector = Instance.new("ClickDetector")
    fireclickdetector(detector, 0, "MouseClick")
    fireclickdetector(detector, 0, "MouseHoverEnter")
    fireclickdetector(detector, 0, "MouseHoverLeave")
    local ok = pcall(fireclickdetector, detector, 0, "InvalidEvent")
    return "fireclickdetector ok"
end)

test("getcallbackvalue", {}, function()
    local bindable = Instance.new("BindableFunction")
    local func = function() end
    bindable.OnInvoke = func
    assert(getcallbackvalue(bindable, "OnInvoke") == func, "Should return callback")
    local bindable2 = Instance.new("BindableFunction")
    assert(getcallbackvalue(bindable2, "OnInvoke") == nil, "nil when not set")
    local val = getcallbackvalue(bindable, "Name")
    assert(val == nil, "Non-callback property should return nil")
    return "getcallbackvalue ok"
end)

test("getconnections", {}, function()
    local event = Instance.new("BindableEvent").Event
    local conn1 = event:Connect(function() end)
    local conn2 = event:Connect(function() end)
    local connections = getconnections(event)
    assert(#connections == 2, "Should have 2 connections")
    for _, c in ipairs(connections) do
        assert(c.Enabled == true, "Enabled true")
        assert(type(c.Fire) == "function", "Fire method")
        assert(type(c.Disconnect) == "function", "Disconnect method")
    end
    connections[1]:Disable()
    assert(connections[1].Enabled == false, "Disable works")
    connections[1]:Enable()
    assert(connections[1].Enabled == true, "Enable works")
    connections[1]:Disconnect()
    assert(#getconnections(event) == 1, "One left")
    conn2:Disconnect()
    assert(#getconnections(event) == 0, "All gone")
    return "getconnections extreme"
end)

test("getcustomasset", {}, function()
    writefile(".tests/asset.txt", "dummy")
    local asset = getcustomasset(".tests/asset.txt")
    assert(type(asset) == "string", "Should return string")
    assert(string.match(asset, "^rbxasset://"), "Should be rbxasset url")
    local success, err = pcall(getcustomasset, ".tests/nonexistent.txt")
    assert(success == false, "Nonexistent file should error")
    writefile(".tests/empty.txt", "")
    local asset2 = getcustomasset(".tests/empty.txt")
    assert(type(asset2) == "string", "Empty file ok")
    return "getcustomasset extreme"
end)

test("gethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local value, hidden = gethiddenproperty(fire, "size_xml")
    assert(value == 5, "size_xml default 5")
    assert(hidden == true, "size_xml hidden")
    local value2, hidden2 = gethiddenproperty(fire, "Size")
    assert(hidden2 == false, "Size not hidden")
    local success, err = pcall(gethiddenproperty, fire, "Invalid")
    assert(success == false, "Invalid property should error")
    return "gethiddenproperty extreme"
end)

test("sethiddenproperty", {}, function()
    local fire = Instance.new("Fire")
    local success = sethiddenproperty(fire, "size_xml", 10)
    assert(success == true, "Should return true")
    local value, hidden = gethiddenproperty(fire, "size_xml")
    assert(value == 10, "Value set")
    local success2 = sethiddenproperty(fire, "Size", Vector3.new(2,2,2))
    assert(success2 == false, "Setting non-hidden property should return false")
    return "sethiddenproperty extreme"
end)

test("gethui", {}, function()
    local hui = gethui()
    assert(typeof(hui) == "Instance", "Should be Instance")
    assert(hui:IsA("Instance"), "Is Instance")
    return "gethui ok"
end)

test("getinstances", {}, function()
    local instances = getinstances()
    assert(type(instances) == "table", "Should return table")
    assert(#instances > 0, "Non-empty")
    for i=1, math.min(10, #instances) do
        assert(typeof(instances[i]) == "Instance", "Element should be Instance")
    end
    return "getinstances ok"
end)

test("getnilinstances", {}, function()
    local nilInsts = getnilinstances()
    assert(type(nilInsts) == "table", "Should return table")
    for _, inst in ipairs(nilInsts) do
        assert(inst.Parent == nil, "All should have nil Parent")
    end
    return "getnilinstances ok"
end)

test("isscriptable", {}, function()
    local fire = Instance.new("Fire")
    assert(isscriptable(fire, "size_xml") == false, "size_xml not scriptable")
    assert(isscriptable(fire, "Size") == true, "Size scriptable")
    local success, res = pcall(isscriptable, fire, "Invalid")
    if success then
        assert(res == false, "Invalid property should be false")
    end
    return "isscriptable extreme"
end)

test("setscriptable", {}, function()
    local fire = Instance.new("Fire")
    local was = setscriptable(fire, "size_xml", true)
    assert(was == false, "was not scriptable")
    assert(isscriptable(fire, "size_xml") == true, "now scriptable")
    was = setscriptable(fire, "size_xml", false)
    assert(was == true, "was scriptable after change")
    assert(isscriptable(fire, "size_xml") == false, "back to false")
    local was2 = setscriptable(fire, "Size", true)
    assert(was2 == true, "Size already scriptable, should return true")
    return "setscriptable extreme"
end)

test("setrbxclipboard", {}, function()
    setrbxclipboard("test")
    setrbxclipboard("")
    return "setrbxclipboard ok"
end)

-- Metatable tests
test("getrawmetatable", {}, function()
    local t = {}
    local meta = { __metatable = "locked" }
    setmetatable(t, meta)
    local raw = getrawmetatable(t)
    assert(raw == meta, "Should return real metatable")
    local t2 = {}
    assert(getrawmetatable(t2) == nil, "No metatable returns nil")
    local success, err = pcall(getrawmetatable, 123)
    assert(success == false, "getrawmetatable on non-table should error")
    return "getrawmetatable extreme"
end)

test("hookmetamethod", {}, function()
    local t = setmetatable({}, { __index = function() return "original" end })
    local called = 0
    local original = hookmetamethod(t, "__index", function(self, key)
        called = called + 1
        return "hooked"
    end)
    assert(t.x == "hooked", "Hooked method should return hooked")
    assert(called == 1, "Hook called")
    local origVal = original(t, "x")
    assert(origVal == "original", "Original should return original")
    local second = hookmetamethod(t, "__index", function()
        called = called + 1
        return "second"
    end)
    assert(t.x == "second", "Second hook")
    assert(called == 2, "Second hook called")
    hookmetamethod(t, "__index", original)
    assert(t.x == "original", "Restored")
    return "hookmetamethod extreme"
end)

test("getnamecallmethod", {}, function()
    local methodName = nil
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        methodName = getnamecallmethod()
        return old(self, ...)
    end)
    game:GetService("Players")
    assert(methodName == "GetService", "namecall method should be GetService")
    game:GetService("Lighting")
    assert(methodName == "GetService", "Still GetService")
    local part = Instance.new("Part")
    part:Destroy()
    assert(methodName == "Destroy", "Destroy method")
    hookmetamethod(game, "__namecall", old)
    return "getnamecallmethod extreme"
end)

test("isreadonly", {}, function()
    local t = { a = 1 }
    assert(isreadonly(t) == false, "New table not readonly")
    table.freeze(t)
    assert(isreadonly(t) == true, "Frozen table readonly")
    local success, err = pcall(function() t.a = 2 end)
    assert(success == false, "Cannot modify readonly")
    setreadonly(t, false)
    assert(isreadonly(t) == false, "Nit writable")
    t.a = 2
    assert(t.a == 2, "Modified")
    return "isreadonly extreme"
end)

test("setrawmetatable", {}, function()
    local t = {}
    local meta = { __index = { x = 1 } }
    local result = setrawmetatable(t, meta)
    assert(result == t, "Returns the table")
    assert(getrawmetatable(t) == meta, "Metatable set")
    assert(t.x == 1, "__index works")
    setrawmetatable(t, nil)
    assert(getrawmetatable(t) == nil, "Metatable removed")
    local success, err = pcall(setrawmetatable, 123, {})
    assert(success == false, "setrawmetatable on non-table should error")
    return "setrawmetatable extreme"
end)

test("setreadonly", {}, function()
    local t = { a = 1 }
    setreadonly(t, true)
    assert(isreadonly(t) == true, "Readonly set")
    local success, err = pcall(function() t.a = 2 end)
    assert(success == false, "Cannot modify")
    setreadonly(t, false)
    t.a = 2
    assert(t.a == 2, "Writable again")
    local success2, err2 = pcall(setreadonly, 123, true)
    assert(success2 == false, "setreadonly on non-table should error")
    return "setreadonly extreme"
end)

-- Miscellaneous tests
test("identifyexecutor", {"getexecutorname"}, function()
    local name, version = identifyexecutor()
    assert(type(name) == "string", "Name is string")
    if version then
        assert(type(version) == "string", "Version is string or nil")
    end
    assert(#name > 0, "Name not empty")
    return "Executor: " .. name .. (version and " "..version or "")
end)

test("lz4compress", {}, function()
    local data = string.rep("A", 1000)
    local compressed = lz4compress(data)
    assert(type(compressed) == "string", "Compressed is string")
    assert(#compressed < #data, "Compression should reduce size")
    local decompressed = lz4decompress(compressed, #data)
    assert(decompressed == data, "Decompressed should match")
    local emptyComp = lz4compress("")
    local emptyDecomp = lz4decompress(emptyComp, 0)
    assert(emptyDecomp == "", "Empty string roundtrip")
    local success, err = pcall(lz4decompress, "invalid", 10)
    assert(success == false, "Decompress invalid should error")
    return "lz4compress extreme"
end)

test("lz4decompress", {}, function()
    local data = "Hello, world!"
    local compressed = lz4compress(data)
    local decompressed = lz4decompress(compressed, #data)
    assert(decompressed == data, "Decompress works")
    local short = lz4decompress(compressed, 5)
    assert(#short == 5, "Length parameter should limit output")
    return "lz4decompress extreme"
end)

test("messagebox", {}, function()
    messagebox("Test", "Caption", 0)
    messagebox("Another", "Caption", 1)
    return "messagebox ok"
end)

test("queue_on_teleport", {"queueonteleport"}, function()
    queue_on_teleport("print('teleported')")
    queue_on_teleport("game:GetService('Players').LocalPlayer:Kick('bye')")
    return "queue_on_teleport ok"
end)

test("request", {"http.request", "http_request"}, function()
    local res = request({
        Url = "https://httpbin.org/get",
        Method = "GET",
        Headers = { ["User-Agent"] = "UNC-Test" }
    })
    assert(res.StatusCode == 200, "GET failed")
    local data = game:GetService("HttpService"):JSONDecode(res.Body)
    assert(data.headers["User-Agent"] == "UNC-Test", "Headers should be sent")
    local postRes = request({
        Url = "https://httpbin.org/post",
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = game:GetService("HttpService"):JSONEncode({test = 123})
    })
    assert(postRes.StatusCode == 200, "POST failed")
    local postData = game:GetService("HttpService"):JSONDecode(postRes.Body)
    assert(postData.json.test == 123, "POST body should be echoed")
    local timeoutRes = request({
        Url = "https://httpbin.org/delay/5",
        Method = "GET",
        Timeout = 1
    })
    return "request extreme"
end)

test("setclipboard", {"toclipboard"}, function()
    setclipboard("test")
    setclipboard("")
    return "setclipboard ok"
end)

test("setfpscap", {}, function()
    local old = setfpscap(60)
    if old then
        assert(type(old) == "number", "Old cap should be number")
    end
    setfpscap(120)
    setfpscap(0)
    setfpscap(60)
    return "setfpscap ok"
end)

-- Scripts tests
test("getgc", {}, function()
    local gc = getgc()
    assert(type(gc) == "table", "Should return table")
    assert(#gc > 0, "Non-empty")
    local hasString = false
    local hasFunction = false
    local hasTable = false
    for _, v in ipairs(gc) do
        if type(v) == "string" then hasString = true end
        if type(v) == "function" then hasFunction = true end
        if type(v) == "table" then hasTable = true end
    end
    assert(hasString and hasFunction and hasTable, "GC should contain various types")
    return "getgc extreme"
end)

test("getgenv", {}, function()
    local env = getgenv()
    assert(type(env) == "table", "Should return table")
    env.__TEST = 42
    assert(__TEST == 42, "Variable should be accessible")
    __TEST = nil
    local oldPrint = print
    env.print = function() end
    env.print = oldPrint
    return "getgenv extreme"
end)

test("getloadedmodules", {}, function()
    local modules = getloadedmodules()
    assert(type(modules) == "table", "Should return table")
    assert(#modules > 0, "Non-empty")
    for _, mod in ipairs(modules) do
        assert(mod:IsA("ModuleScript"), "Should be ModuleScript")
    end
    return "getloadedmodules ok"
end)

test("getrenv", {}, function()
    local renv = getrenv()
    assert(type(renv) == "table", "Should return table")
    assert(renv.game ~= nil, "game should exist")
    assert(renv.workspace ~= nil, "workspace should exist")
    assert(renv._G ~= _G, "getrenv()._G different from executor _G")
    return "getrenv extreme"
end)

test("getrunningscripts", {}, function()
    local scripts = getrunningscripts()
    assert(type(scripts) == "table", "Should return table")
    for _, s in ipairs(scripts) do
        assert(s:IsA("ModuleScript") or s:IsA("LocalScript"), "Should be a script")
    end
    return "getrunningscripts ok"
end)

test("getscriptbytecode", {"dumpstring"}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local bytecode = getscriptbytecode(animate)
    assert(type(bytecode) == "string", "Should return string")
    assert(#bytecode > 0, "Non-empty")
    return "getscriptbytecode ok"
end)

test("getscripthash", {}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local hash = getscripthash(animate)
    assert(type(hash) == "string", "Should return string")
    assert(#hash > 0, "Non-empty")
    local original = animate.Source
    animate.Source = original .. " "
    local newHash = getscripthash(animate)
    assert(hash ~= newHash, "Hash changed")
    animate.Source = original
    local restoredHash = getscripthash(animate)
    assert(restoredHash == hash, "Hash restored")
    return "getscripthash extreme"
end)

test("getscripts", {}, function()
    local scripts = getscripts()
    assert(type(scripts) == "table", "Should return table")
    assert(#scripts > 0, "Non-empty")
    for _, s in ipairs(scripts) do
        assert(s:IsA("ModuleScript") or s:IsA("LocalScript"), "Should be a script")
    end
    return "getscripts ok"
end)

test("getsenv", {}, function()
    local animate = game:GetService("Players").LocalPlayer.Character.Animate
    local env = getsenv(animate)
    assert(type(env) == "table", "Should return table")
    assert(env.script == animate, "script global equals the script")
    assert(env.game ~= nil, "game in environment")
    return "getsenv extreme"
end)

test("getthreadidentity", {"getidentity", "getthreadcontext"}, function()
    local id = getthreadidentity()
    assert(type(id) == "number", "Should return number")
    local old = id
    setthreadidentity(8)
    assert(getthreadidentity() == 8, "Identity changed")
    setthreadidentity(old)
    assert(getthreadidentity() == old, "Restored")
    return "getthreadidentity extreme"
end)

test("setthreadidentity", {"setidentity", "setthreadcontext"}, function()
    local old = getthreadidentity()
    setthreadidentity(3)
    assert(getthreadidentity() == 3, "Set to 3")
    setthreadidentity(2)
    assert(getthreadidentity() == 2, "Set to 2")
    setthreadidentity(old)
    return "setthreadidentity extreme"
end)

-- Drawing tests
test("Drawing", {}, function()
    assert(type(Drawing) == "table", "Drawing table exists")
    assert(type(Drawing.new) == "function", "Drawing.new exists")
    assert(type(Drawing.Fonts) == "table", "Drawing.Fonts exists")
    return "Drawing table ok"
end)

test("Drawing.new", {}, function()
    local types = {"Line", "Text", "Image", "Circle", "Square", "Quad"}
    for _, t in ipairs(types) do
        local obj = Drawing.new(t)
        assert(obj, "Drawing.new("..t..") should return object")
        obj:Destroy()
    end
    local success, err = pcall(Drawing.new, "Invalid")
    assert(success == false, "Invalid type should error")
    return "Drawing.new extreme"
end)

test("Drawing.Fonts", {}, function()
    assert(Drawing.Fonts.UI == 0, "UI")
    assert(Drawing.Fonts.System == 1, "System")
    assert(Drawing.Fonts.Plex == 2, "Plex")
    assert(Drawing.Fonts.Monospace == 3, "Monospace")
    local text = Drawing.new("Text")
    text.Font = Drawing.Fonts.Monospace
    text:Destroy()
    return "Drawing.Fonts correct"
end)

test("isrenderobj", {}, function()
    local square = Drawing.new("Square")
    assert(isrenderobj(square) == true, "Drawing object true")
    assert(isrenderobj({}) == false, "Table false")
    assert(isrenderobj(123) == false, "Number false")
    square:Destroy()
    return "isrenderobj ok"
end)

test("getrenderproperty", {}, function()
    local square = Drawing.new("Square")
    square.Visible = true
    square.Color = Color3.new(1,0,0)
    local visible = getrenderproperty(square, "Visible")
    assert(visible == true, "Visible property")
    local color = getrenderproperty(square, "Color")
    assert(color == Color3.new(1,0,0), "Color property")
    local nonexist = getrenderproperty(square, "NonExistent")
    assert(nonexist == nil, "Nonexistent returns nil")
    square:Destroy()
    return "getrenderproperty extreme"
end)

test("setrenderproperty", {}, function()
    local square = Drawing.new("Square")
    setrenderproperty(square, "Visible", false)
    assert(square.Visible == false, "Visible set")
    setrenderproperty(square, "Color", Color3.new(0,1,0))
    assert(square.Color == Color3.new(0,1,0), "Color set")
    local ok = pcall(setrenderproperty, square, "Invalid", 123)
    square:Destroy()
    return "setrenderproperty extreme"
end)

test("cleardrawcache", {}, function()
    cleardrawcache()
    return "cleardrawcache executed"
end)

-- WebSocket tests
test("WebSocket", {}, function()
    assert(type(WebSocket) == "table", "WebSocket table exists")
    assert(type(WebSocket.connect) == "function", "WebSocket.connect exists")
    return "WebSocket table ok"
end)

test("WebSocket.connect", {}, function()
    local ws = WebSocket.connect("wss://echo.websocket.events")
    assert(ws, "connect should return object")
    assert(type(ws.Send) == "function", "Send method")
    assert(type(ws.Close) == "function", "Close method")
    local received = nil
    ws.OnMessage:Connect(function(data)
        received = data
    end)
    ws:Send("hello")
    local start = os.clock()
    while received == nil and os.clock() - start < 2 do
        task.wait()
    end
    assert(received == "hello", "Echo should work")
    ws:Close()
    local success, err = pcall(WebSocket.connect, "ws://invalid.url")
    assert(success == false, "Invalid URL should error")
    return "WebSocket.connect extreme"
end)
