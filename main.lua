local mat4 = require("lib.mathsies").mat4
local vec3 = require("lib.mathsies").vec3
local quat = require("lib.mathsies").quat

local loadObj = require("loadObj")
local normaliseOrZero = require("normalise-or-zero")
local consts = require("consts") -- proably move forwardZ etc into consts

math.tau = math.pi * 2

local rightX, upY, forwardZ = 1, 1, 1
local rightVector = vec3(rightX, 0, 0)
local upVector = vec3(0, upY, 0)
local forwardVector = vec3(0, 0, forwardZ)

local defaultRaycastNearPlaneDistanceLinear = 1

local planeMesh = love.graphics.newMesh(consts.vertexFormat, {
	{-1, -1, 0, 0, 0, forwardZ},
	{-1, 1, 0, 0, 0, forwardZ},
	{1, -1, 0, 0, 0, forwardZ},
	{-1, 1, 0, 0, 0, forwardZ},
	{1, -1, 0, 0, 0, forwardZ},
	{1, 1, 0, 0, 0, forwardZ}
}, "triangles", "static")
local sphereMesh = loadObj("meshes/sphere.obj")

local shader = love.graphics.newShader("shader.glsl")

local eye, retina, pupil, objects, mode, canvas

local function linearRetina()
	retina.type = "rectangle"
	retina.position = forwardVector * defaultRaycastNearPlaneDistanceLinear
	retina.orientation = quat()
end

local function fisheyeRetina()
	retina.type = "sphere"
	retina.position = vec3()
	retina.orientation = quat()
end

function love.load()
	mode = "linear"

	eye = {
		position = vec3(0, 0, 0),
		orientation = quat.fromAxisAngle(vec3(0, math.tau / 4, 0))
	}
	retina = {}
	linearRetina()
	pupil = {
		type = "point",
		position = vec3(0, 0, 0),
		orientation = quat.fromAxisAngle(vec3(0, math.tau / 4, 0)) -- Lines start out pointing on the z
	}

	objects = {}

	canvas = love.graphics.newCanvas(love.graphics.getDimensions())
end

function love.update(dt)
	local speed = 4
	local translation = vec3()
	if love.keyboard.isDown("d") then translation = translation + rightVector end
	if love.keyboard.isDown("a") then translation = translation - rightVector end
	if love.keyboard.isDown("e") then translation = translation + upVector end
	if love.keyboard.isDown("q") then translation = translation - upVector end
	if love.keyboard.isDown("w") then translation = translation + forwardVector end
	if love.keyboard.isDown("s") then translation = translation - forwardVector end
	eye.position = eye.position + vec3.rotate(normaliseOrZero(translation) * speed, eye.orientation) * dt

	local angularSpeed = math.tau / 4
	local rotation = vec3()
	if love.keyboard.isDown("k") then rotation = rotation + rightVector end
	if love.keyboard.isDown("i") then rotation = rotation - rightVector end
	if love.keyboard.isDown("l") then rotation = rotation + upVector end
	if love.keyboard.isDown("j") then rotation = rotation - upVector end
	if love.keyboard.isDown("u") then rotation = rotation + forwardVector end
	if love.keyboard.isDown("o") then rotation = rotation - forwardVector end
	eye.orientation = quat.normalise(eye.orientation * quat.fromAxisAngle(normaliseOrZero(rotation) * angularSpeed * dt))
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
	end
end

function love.draw()
	love.graphics.setCanvas(canvas)
	love.graphics.clear()

	shader:send("discardBackwardsFragments", true)
	shader:send("aspectRatio", love.graphics.getWidth() / love.graphics.getHeight())

	-- TODO: Different types of pupil and retina

	local eyeToWorld = mat4.transform(eye.position, eye.orientation)

	local retinaToEye = mat4.transform(retina.position, retina.orientation)
	local retinaToWorld = eyeToWorld * retinaToEye;
	shader:send("retinaToWorld", {mat4.components(retinaToWorld)})
	-- shader:send("retinaToWorldNormal", {normalMatrix(retinaToWorld)})

	local pupilToEye = mat4.transform(pupil.position, pupil.orientation)
	local pupilToWorld = eyeToWorld * pupilToEye;
	shader:send("pupilToWorld", {mat4.components(pupilToWorld)})

	-- TODO: Send spheres etc to shader

	love.graphics.setShader(shader)
	love.graphics.draw(retina.type == "rectangle" and planeMesh or retina.type == "sphere" and sphereMesh)
	love.graphics.setShader()
	-- TODO: Skybox, Elite-style indicator showing where forward vector is relative to current orientation, etc (does the skybox need special perspective handling?)

	love.graphics.setCanvas()
	love.graphics.draw(canvas, 0, love.graphics.getHeight(), 0, 1, -1)
end
