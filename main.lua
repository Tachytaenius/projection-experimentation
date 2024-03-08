local mat4 = require("lib.mathsies").mat4
local vec3 = require("lib.mathsies").vec3
local quat = require("lib.mathsies").quat

local loadObj = require("loadObj")
local consts = require("consts") -- proably move forwardZ etc into consts

math.tau = math.pi * 2

local forwardZ = 1
local forwardVector = vec3(0, 0, forwardZ)
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

local eye, retina, pupil, objects

function love.load()
	-- TODO: Move retina to have centre over pupil when in fisheye mode
	eye = {
		position = vec3(0, 0, 0),
		orientation = quat.fromAxisAngle(vec3(0, math.tau / 4, 0))
	}
	retina = {
		type = "rectangle",
		position = vec3(0, 0, forwardZ),
		orientation = quat(),
		-- width = 20,
		-- height = 20
	}
	pupil = {
		type = "point",
		position = vec3(0, 0, 0),
		orientation = quat.fromAxisAngle(vec3(0, math.tau / 4, 0)) -- Lines start out pointing on the z
	}

	objects = {}
end

function love.update(dt)
	local speed = 4
	local translation = vec3()
	if love.keyboard.isDown("w") then translation.z = translation.z + speed end
	if love.keyboard.isDown("s") then translation.z = translation.z - speed end
	if love.keyboard.isDown("a") then translation.x = translation.x - speed end
	if love.keyboard.isDown("d") then translation.x = translation.x + speed end
	if love.keyboard.isDown("q") then translation.y = translation.y - speed end
	if love.keyboard.isDown("e") then translation.y = translation.y + speed end
	eye.position = eye.position + vec3.rotate(translation, eye.orientation) * dt

	local angularSpeed = math.tau / 4
	local rotation = vec3()
	if love.keyboard.isDown("j") then rotation.y = rotation.y - angularSpeed end
	if love.keyboard.isDown("l") then rotation.y = rotation.y + angularSpeed end
	if love.keyboard.isDown("i") then rotation.x = rotation.x - angularSpeed end
	if love.keyboard.isDown("k") then rotation.x = rotation.x + angularSpeed end
	if love.keyboard.isDown("u") then rotation.z = rotation.z + angularSpeed end
	if love.keyboard.isDown("o") then rotation.z = rotation.z - angularSpeed end
	eye.orientation = quat.normalise(eye.orientation * quat.fromAxisAngle(rotation * dt))
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
	if key == "r" then
		if retina.type == "rectangle" then
			retina.type = "sphere"
		elseif retina.type == "sphere" then
			retina.type = "rectangle"
		end
	end
end

function love.draw()
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
end
