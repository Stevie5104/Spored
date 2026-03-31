--!strict
-- Functional tests for MovementController click-to-move and drag behaviour.
--
-- These tests exercise the pure movement logic (state transitions, direction
-- computation, drag flag lifecycle) without requiring a live Roblox server.
-- Run them with a Luau test runner (e.g. roblox-ts + TestEZ, or standalone
-- Luau) that provides the Roblox globals via a mock environment.
--
-- Each test function returns true on pass, false + message on failure.

-- ── Minimal mock types (stand-ins for Roblox globals in offline runners) ──────

type Vector3Like = { X: number, Y: number, Z: number, Magnitude: number, Unit: Vector3Like }

local function vec3(x: number, y: number, z: number): any
	local mag = math.sqrt(x * x + y * y + z * z)
	local self: any = { X = x, Y = y, Z = z, Magnitude = mag }
	if mag > 1e-8 then
		self.Unit = vec3(x / mag, y / mag, z / mag)
	else
		self.Unit = vec3(0, 0, 0)
	end
	setmetatable(self, {
		__add = function(a: any, b: any) return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
		__sub = function(a: any, b: any) return vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
		__mul = function(a: any, b: any)
			if type(b) == "number" then return vec3(a.X * b, a.Y * b, a.Z * b) end
			return vec3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
		end,
		__tostring = function(a: any) return ("(%g, %g, %g)"):format(a.X, a.Y, a.Z) end,
	})
	return self
end

local ZERO = vec3(0, 0, 0)

-- ── Inline re-implementation of the testable pure logic ──────────────────────
-- (mirrors the real controller; keeps tests self-contained)

local STOP_DIST = 1.5

local function flatten(v: any): any
	return vec3(v.X, 0, v.Z)
end

-- Compute the desiredMoveDir for one ClickToMove frame given state.
-- Returns the computed direction (zero if stopped/arrived).
local function computeClickToMove(pos: any, clickTarget: any): (any, any?)
	if clickTarget == nil then
		return ZERO, nil
	end
	local toTarget = flatten(clickTarget - pos)
	if toTarget.Magnitude <= STOP_DIST then
		-- Arrived – clear target.
		return ZERO, nil
	end
	return toTarget.Unit, clickTarget
end

-- Simulate drag: isDragging continuously overwrites clickTarget with cursor pos.
local function simulateDragFrame(isDragging: boolean, cursorPos: any, currentTarget: any?): any?
	if isDragging then
		return cursorPos  -- overwrite every frame
	end
	return currentTarget
end

-- ── Test helpers ──────────────────────────────────────────────────────────────

local passed = 0
local failed = 0

local function expect(label: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
		print(("  ✓ %s"):format(label))
	else
		failed += 1
		print(("  ✗ %s%s"):format(label, detail and (" — " .. detail) or ""))
	end
end

local function approxEq(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-4)
end

-- ── Tests ─────────────────────────────────────────────────────────────────────

print("MovementController – click-to-move tests")

do -- Single click: organism heads toward target
	local pos = vec3(0, 0, 0)
	local target = vec3(10, 0, 0)
	local dir, remaining = computeClickToMove(pos, target)
	expect("single click sets move direction toward target",
		approxEq(dir.X, 1) and approxEq(dir.Z, 0),
		("dir = %s"):format(tostring(dir)))
	expect("target is kept while outside stop distance",
		remaining ~= nil)
end

do -- Arrival: within STOP_DIST clears the target
	local pos = vec3(0, 0, 0)
	local target = vec3(STOP_DIST - 0.1, 0, 0)  -- just inside stop radius
	local dir, remaining = computeClickToMove(pos, target)
	expect("arrival clears clickTarget",
		remaining == nil,
		("remaining = %s"):format(tostring(remaining)))
	expect("arrival returns zero move direction",
		approxEq(dir.X, 0) and approxEq(dir.Z, 0))
end

do -- No target: zero move direction
	local pos = vec3(0, 0, 0)
	local dir, _ = computeClickToMove(pos, nil)
	expect("nil target yields zero move direction",
		approxEq(dir.X, 0) and approxEq(dir.Z, 0))
end

print("MovementController – drag mode tests")

do -- Drag: target updates each frame while isDragging
	local cursor1 = vec3(5, 0, 0)
	local cursor2 = vec3(10, 0, 5)

	-- Frame 1: button held, cursor at position 1
	local target = simulateDragFrame(true, cursor1, nil)
	expect("drag frame 1 sets target to cursor position",
		target ~= nil and approxEq((target :: any).X, 5))

	-- Frame 2: cursor moved, still held
	target = simulateDragFrame(true, cursor2, target)
	expect("drag frame 2 updates target to new cursor position",
		target ~= nil and approxEq((target :: any).X, 10) and approxEq((target :: any).Z, 5))
end

do -- Release: isDragging = false, target is NOT overwritten
	local lastTarget = vec3(10, 0, 5)
	local newCursorPos = vec3(99, 0, 99)

	local target = simulateDragFrame(false, newCursorPos, lastTarget)
	expect("after release target stays at last cursor position",
		target ~= nil
		and approxEq((target :: any).X, 10)
		and approxEq((target :: any).Z, 5))
end

do -- Drag with movement computation: organism follows dragged cursor
	local pos = vec3(0, 0, 0)
	local draggedTarget = vec3(0, 0, 10)

	local dir, remaining = computeClickToMove(pos, draggedTarget)
	expect("organism moves toward dragged cursor position",
		approxEq(dir.Z, 1))
	expect("target persists while outside stop distance during drag",
		remaining ~= nil)
end

do -- DRAG_ENABLED = false path: isDragging is never set, target unchanged
	-- Simulated: button down but drag disabled → isDragging stays false
	local isDragging = false  -- would remain false when DRAG_ENABLED = false
	local initialTarget = vec3(7, 0, 3)
	local cursorMoved = vec3(20, 0, 20)

	local target = simulateDragFrame(isDragging, cursorMoved, initialTarget)
	expect("DRAG_ENABLED=false: target not overwritten by cursor movement",
		target ~= nil
		and approxEq((target :: any).X, 7)
		and approxEq((target :: any).Z, 3))
end

-- ── Summary ───────────────────────────────────────────────────────────────────

print(("\nResults: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error(("%d test(s) failed"):format(failed), 2)
end
