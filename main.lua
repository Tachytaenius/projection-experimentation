local mat4 = require("lib.mathsies").mat4
local vec3 = require("lib.mathsies").vec3
local quat = require("lib.mathsies").quat

local loadObj = require("loadObj")
local normaliseOrZero = require("normalise-or-zero")
local limitVectorLength = require("limit-vector-length")
local consts = require("consts") -- proably move forwardZ etc into consts

math.tau = math.pi * 2

local rightX, upY, forwardZ = 1, 1, 1
local rightVector = vec3(rightX, 0, 0)
local upVector = vec3(0, upY, 0)
local forwardVector = vec3(0, 0, forwardZ)

local defaultRaycastNearPlaneDistanceLinear = 0.125
local defaultRaycastVerticalFOVLinear = math.rad(90)

local defaultRaycastSphereRadiusFisheye = 0.125

local blackHoleCanvasScale = 0.25
local noBlackHoleCanvasScale = 1
local currentCanvasScale

local planeMesh = love.graphics.newMesh(consts.vertexFormat, {
	{-1, -1, 0, 0, 0, forwardZ},
	{-1, 1, 0, 0, 0, forwardZ},
	{1, -1, 0, 0, 0, forwardZ},
	{-1, 1, 0, 0, 0, forwardZ},
	{1, -1, 0, 0, 0, forwardZ},
	{1, 1, 0, 0, 0, forwardZ}
}, "triangles", "static")
local sphereMesh = loadObj("meshes/sphere.obj")

local eye, retina, pupil, objects, canvas, shader
local enableBlackHoles, showHelp, solidColourSky
local mouseDx, mouseDy

local time

local function getRetinaScale()
	local w, h = canvas:getDimensions()
	local aspect = w / h
	if retina.type == "rectangle" then
		-- Vertical FOV defines the scale on the y axis
		-- The scale on the x axis is defined from the scale on the y and the aspect, whether that causes a larger or smaller horizontal FOV
		-- Maybe I should replace vertical FOV with a "FOV of largest axis"...?
		return vec3(
			aspect * math.tan(defaultRaycastVerticalFOVLinear / 2),
			math.tan(defaultRaycastVerticalFOVLinear / 2),
			1
		) * defaultRaycastNearPlaneDistanceLinear
	elseif retina.type == "ellipsoid" then
		-- Similar approach as with rectangle retinae
		return vec3(
			aspect * 1,
			1,
			1
		) * defaultRaycastSphereRadiusFisheye
	elseif retina.type == "sphere" then
		return vec3(defaultRaycastSphereRadiusFisheye)
	end
end

local function linearRetina()
	retina.type = "rectangle"
	retina.position = forwardVector * defaultRaycastNearPlaneDistanceLinear
	retina.orientation = quat()
	retina.scale = getRetinaScale()
end

local function fisheyeRetina()
	retina.type = "sphere"
	retina.position = vec3()
	retina.orientation = quat()
	retina.scale = getRetinaScale()
end

local function ellipsoidFisheyeRetina()
	retina.type = "ellipsoid"
	retina.position = vec3()
	retina.orientation = quat()
	retina.scale = getRetinaScale()
end

local function resendAllObjects()
	local numSpheres = 0
	local numAABBs = 0
	local numBlackHoles = 0
	for _, object in ipairs(objects) do
		if object.type == "sphere" then
			shader:send("spheres[" .. numSpheres .. "].position", {vec3.components(object.position)})
			shader:send("spheres[" .. numSpheres .. "].radius", object.radius)
			numSpheres = numSpheres + 1
		elseif object.type == "AABB" then
			shader:send("AABBs[" .. numAABBs .. "].position", {vec3.components(object.position)})
			shader:send("AABBs[" .. numAABBs .. "].sideLengths", {vec3.components(object.sideLengths)})
			numAABBs = numAABBs + 1
		elseif
			object.type == "blackHole"
			and enableBlackHoles
		then
			shader:send("blackHoles[" .. numBlackHoles .. "].position", {vec3.components(object.position)})
			shader:send("blackHoles[" .. numBlackHoles .. "].radius", object.radius)
			shader:send("blackHoles[" .. numBlackHoles .. "].colour", object.colour)
			shader:send("blackHoles[" .. numBlackHoles .. "].gravityExponent", object.gravityExponent)
			shader:send("blackHoles[" .. numBlackHoles .. "].gravityStrength", object.gravityStrength)
			numBlackHoles = numBlackHoles + 1
		end
	end
	shader:send("numSpheres", numSpheres)
	shader:send("numAABBs", numAABBs)
	shader:send("numBlackHoles", numBlackHoles)
end

local function rebuildCanvas()
	local w, h = love.graphics.getDimensions()
	canvas = love.graphics.newCanvas(w * currentCanvasScale, h * currentCanvasScale)
end

function love.load()
	enableBlackHoles = false
	currentCanvasScale = noBlackHoleCanvasScale

	love.graphics.setDefaultFilter("nearest")

	rebuildCanvas()

	eye = {
		position = vec3(0, 0, 0),
		orientation = quat()
	}
	retina = {}
	linearRetina()
	pupil = {
		type = "point",
		position = vec3(0, 0, 0),
		orientation = quat.fromAxisAngle(vec3(0, math.tau / 4, 0)) -- Lines start out pointing on the z
	}

	shader = love.graphics.newShader(
		love.filesystem.read("shaders/include/lib/simplex3d.glsl") ..
		love.filesystem.read("shaders/include/sky.glsl") ..
		love.filesystem.read("shaders/main.glsl")
	)

	objects = {}
	local function posAxis()
		return (love.math.random() * 2 - 1) * 15
	end
	local function size()
		return love.math.random () * 3
	end
	for _ = 1, 32 do
		local x, y, z = posAxis(), posAxis(), posAxis()
		local w, h, d = size(), size(), size()
		objects[#objects + 1] = {
			type = "AABB",
			position = vec3(x, y, z),
			sideLengths = vec3(w, h, d)
		}
	end
	for _ = 1, 32 do
		local x, y, z = posAxis(), posAxis(), posAxis()
		-- local r = size()
		local r = 1 -- Consistent size
		objects[#objects + 1] = {
			type = "sphere",
			position = vec3(x, y, z),
			radius = r
		}
	end
	for _ = 1, 5 do
		local x, y, z = posAxis(), posAxis(), posAxis()
		local minSize = 0.5
		local maxSize = 2
		local r = love.math.random() * (maxSize - minSize) + minSize
		objects[#objects + 1] = {
			type = "blackHole",
			position = vec3(x, y, z),
			radius = r,
			gravityExponent = -2,
			gravityStrength = r / maxSize * 150,
			colour = {0, 0, 0}
		}
	end

	time = 0

	showHelp = true
	solidColourSky = true
end

function love.mousepressed()
	love.mouse.setRelativeMode(not love.mouse.getRelativeMode())
end

function love.update(dt)
	if not (mouseDx and mouseDy) or love.mouse.getRelativeMode() == false then
		mouseDx = 0
		mouseDy = 0
	end

	resendAllObjects()

	local speed = love.keyboard.isDown("lshift") and 20 or 4
	local translation = vec3()
	if love.keyboard.isDown("d") then translation = translation + rightVector end
	if love.keyboard.isDown("a") then translation = translation - rightVector end
	if love.keyboard.isDown("e") then translation = translation + upVector end
	if love.keyboard.isDown("q") then translation = translation - upVector end
	if love.keyboard.isDown("w") then translation = translation + forwardVector end
	if love.keyboard.isDown("s") then translation = translation - forwardVector end
	eye.position = eye.position + vec3.rotate(normaliseOrZero(translation) * speed, eye.orientation) * dt

	local maxAngularSpeed = math.tau * 2
	local keyboardRotationSpeed = math.tau / 4
	local keyboardRotationMultiplier = keyboardRotationSpeed / maxAngularSpeed
	local mouseMovementForMaxSpeed = 20
	local rotation = vec3()
	if love.keyboard.isDown("k") then rotation = rotation + rightVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("i") then rotation = rotation - rightVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("l") then rotation = rotation + upVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("j") then rotation = rotation - upVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("u") then rotation = rotation + forwardVector * keyboardRotationMultiplier end
	if love.keyboard.isDown("o") then rotation = rotation - forwardVector * keyboardRotationMultiplier end
	rotation = rotation + upVector * mouseDx / mouseMovementForMaxSpeed
	rotation = rotation + rightVector * mouseDy / mouseMovementForMaxSpeed
	eye.orientation = quat.normalise(eye.orientation * quat.fromAxisAngle(limitVectorLength(rotation, 1) * maxAngularSpeed * dt))

	time = time + dt

	mouseDx, mouseDy = nil, nil
end

-- Used to transform normals
local function normalMatrix(modelToWorld)
	local m = mat4.transpose(mat4.inverse(modelToWorld))
	return
		m._00, m._01, m._02,
		m._10, m._11, m._12,
		m._20, m._21, m._22
end

function love.keypressed(key)
	if key == "1" then -- Linear
		linearRetina()
	elseif key == "2" then
		fisheyeRetina()
	elseif key == "3" then
		ellipsoidFisheyeRetina()

	elseif key == "b" then
		enableBlackHoles = not enableBlackHoles
		currentCanvasScale = enableBlackHoles and blackHoleCanvasScale or noBlackHoleCanvasScale
		rebuildCanvas()
	elseif key == "h" then
		showHelp = not showHelp
	elseif key == "z" then
		solidColourSky = not solidColourSky
	end
end

function love.resize(w, h)
	rebuildCanvas()
	retina.scale = getRetinaScale()
end

function love.mousemoved(_, _, dx, dy)
	mouseDx, mouseDy = dx, dy
end

function love.draw()
	love.graphics.setCanvas(canvas)
	love.graphics.clear()

	shader:send("discardBackwardsFragments", true)

	if enableBlackHoles then
		shader:send("initialRaySpeed", 10)
		shader:send("maxRaySteps", 200)
		shader:send("rayTimestep", 0.025)
		shader:send("limitedRays", true)
	else
		shader:send("initialRaySpeed", 1)
		shader:send("maxRaySteps", 1)
		shader:send("rayTimestep", 1)
		shader:send("limitedRays", false)
	end

	if solidColourSky then
		shader:send("solidSky", true)
		shader:send("solidSkyColour", {0.1, 0.1, 0.1})
	else
		shader:send("solidSky", false)
	end

	-- TODO: Different types of pupil and retina

	local eyeToWorld = mat4.transform(eye.position, eye.orientation)

	local retinaToEye = mat4.transform(retina.position, retina.orientation, retina.scale)
	local retinaToWorld = eyeToWorld * retinaToEye;
	shader:send("retinaToWorld", {mat4.components(retinaToWorld)})
	-- shader:send("retinaToWorldNormal", {normalMatrix(retinaToWorld)})

	local pupilToEye = mat4.transform(pupil.position, pupil.orientation)
	local pupilToWorld = eyeToWorld * pupilToEye;
	shader:send("pupilToWorld", {mat4.components(pupilToWorld)})

	-- TODO: Send spheres etc to shader

	local aspect = canvas:getWidth() / canvas:getHeight()
	local retinaScaleClip
	-- The goal is to show the whole retina on the screen
	if
		retina.type == "rectangle"
		or retina.type == "ellipsoid"
	then
		retinaScaleClip = vec3(1) -- No scaling, since [-1, 1] already maps to the corners of the viewport regardless of aspect
	elseif retina.type == "sphere" then
		retinaScaleClip = vec3( -- Show whole of sphere on screen
			math.min(1 / aspect, 1),
			math.min(aspect, 1),
			1
		)
	end
	shader:send("retinaScaleClip", {vec3.components(retinaScaleClip)})

	love.graphics.setShader(shader)
	love.graphics.draw(
		retina.type == "rectangle" and planeMesh or
		(retina.type == "sphere" or retina.type == "ellipsoid") and sphereMesh
	)
	love.graphics.setShader()
	-- TODO: Skybox, Elite-style indicator showing where forward vector is relative to current orientation, etc (does the skybox need special perspective handling?)

	love.graphics.setCanvas()
	love.graphics.draw(canvas, 0, love.graphics.getHeight(), 0, 1 / currentCanvasScale, -1 / currentCanvasScale)

	if showHelp then
		love.graphics.print(
			"WASDQE: Translate\n" ..
			"LShift: Translate faster\n" ..
			"IJKLUO and mouse: Rotate\n" ..
			"Click: Grab/ungrab mouse\n" ..
			"B: Toggle black holes (and limited segmented rays and reduced resolution)\n" ..
			"1: Linear, 2: Spherical fisheye, 3: Ellipsoid Fisheye\n" ..
			"Z: Toggle solid colour sky\n" ..
			"H: Toggle help"
		)
	end
end
