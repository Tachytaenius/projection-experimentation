const int maxSpheres = 32;
const int maxAABBs = 32;

varying vec3 fragmentPosition;
varying vec3 fragmentNormalWorld;
varying vec3 fragmentNormalCamera;

#ifdef VERTEX

uniform float aspectRatio;
uniform float verticalFOV; // TODO
uniform mat4 retinaToWorld;
uniform mat3 retinaToWorldNormal;
uniform vec3 retinaScaleClip; // How to scale the retina mesh as it is displayed to the screen. Scaling the interpreted positions for the raycasting is done within retinaToWorld

attribute vec3 VertexNormal;

vec4 position(mat4 loveTransform, vec4 vertexPositionModel) {
	fragmentPosition = (retinaToWorld * vertexPositionModel).xyz;
	fragmentNormalCamera = VertexNormal;
	fragmentNormalWorld = retinaToWorldNormal * VertexNormal;

	return vertexPositionModel * vec4(retinaScaleClip, 1.0);
}

#endif

#ifdef PIXEL

struct Sphere {
	vec3 position;
	float radius;
};

struct AABB {
	vec3 position;
	vec3 sideLengths;
};

uniform mat4 pupilToWorld;
uniform bool discardBackwardsFragments;

uniform int numSpheres;
uniform Sphere[maxSpheres] spheres;

uniform int numAABBs;
uniform AABB[maxAABBs] AABBs;

uniform float initialRaySpeed;
uniform int maxRaySteps;
uniform float rayTimestep;
uniform vec3 blackHolePosition;
uniform float blackHoleRadius;
uniform float blackHoleGravity;
uniform float blackHoleExponentPositive;
uniform vec3 blackHoleColour;
uniform bool limitedRays; // If this is false, expect maxRaySteps to be 1 and for there to be no black holes

uniform vec3 skyColour;

struct RaycastHit {
	float t;
	vec3 position;
	vec3 normal;
};
const RaycastHit raycastHitMiss = RaycastHit (0.0, vec3(0.0), vec3(0.0));

struct ConvexRaycastResult {
	bool hit;
	RaycastHit[2] hits;
};
const ConvexRaycastResult convexRaycastMiss = ConvexRaycastResult (false, RaycastHit[2](raycastHitMiss, raycastHitMiss));

ConvexRaycastResult sphereRaycast(vec3 spherePosition, float sphereRadius, vec3 rayStart, vec3 rayEnd) {
	if (rayStart == rayEnd) {
		return convexRaycastMiss;
	}

	vec3 startToEnd = rayEnd - rayStart;
	vec3 sphereToStart = rayStart - spherePosition;

	float a = dot(startToEnd, startToEnd);
	float b = 2.0 * dot(sphereToStart, startToEnd);
	float c = dot(sphereToStart, sphereToStart) - pow(sphereRadius, 2.0);
	float h = pow(b, 2.0) - 4.0 * a * c;
	if (h < 0.0) {
		return convexRaycastMiss;
	}
	float t0 = (-b - sqrt(h)) / (2.0 * a);
	vec3 pos0 = rayStart + startToEnd * t0;
	float t1 = (-b + sqrt(h)) / (2.0 * a);
	vec3 pos1 = rayStart + startToEnd * t1;
	return ConvexRaycastResult (
		true,
		RaycastHit[2] (
			RaycastHit (
				t0,
				pos0,
				normalize(pos0 - spherePosition)
			), RaycastHit (
				t1,
				pos1,
				normalize(pos1 - spherePosition)
			)
		)
	);
}

ConvexRaycastResult AABBRaycast(vec3 AABBPosition, vec3 AABBLengths, vec3 rayStart, vec3 rayEnd) {
	vec3 startToEnd = rayEnd - rayStart;
	vec3 AABBToRayStart = rayStart - (AABBPosition + AABBLengths / 2);
	
	vec3 a = 1.0 / startToEnd;
	vec3 b = a * AABBToRayStart;
	vec3 c = abs(a) * AABBLengths / 2;
	vec3 d = -b - c;
	vec3 e = -b + c;
	float t0 = max(max(d.x, d.y), d.z);
	float t1 = min(min(e.x, e.y), e.z);

	// TODO: Fix pixels appearing outside the box
	if (t0 > t1) {
		return convexRaycastMiss;
	}
	vec3 pos0 = rayStart + startToEnd * t0;
	vec3 pos1 = rayStart + startToEnd * t1;
	// TODO: Verify normals and positions and "times"
	return ConvexRaycastResult (
		true,
		RaycastHit[2] (
			RaycastHit (
				t0,
				pos0,
				step(vec3(t0), d) * -sign(startToEnd)
			),
			RaycastHit (
				t1,
				pos1,
				step(e, vec3(t1)) * sign(startToEnd)
			)
		)
	);
}

// Infinitely long ray
void tryNewClosestHit(bool limitedRays, inout bool foundHit, inout RaycastHit closestForwardHit, inout vec3 currentColour, RaycastHit newHit, vec3 newHitColour) {
	// Is it in the right range?
	if (newHit.t < 0.0 || (limitedRays && newHit.t > 1.0)) {
		return;
	}
	// Nothing to compare to? Is it closer?
	if (!foundHit || newHit.t < closestForwardHit.t) {
		closestForwardHit = newHit;
		foundHit = true;
		currentColour = newHitColour;
	}
}

// Line extends beyond start and end
vec3 closestPointOnLine(vec3 lineStart, vec3 lineEnd, vec3 point) {
	vec3 startToEnd = lineEnd - lineStart;
	vec3 startToPoint = point - lineStart;
	
	vec3 v = startToPoint - startToEnd * dot(startToPoint, startToEnd) / dot(startToEnd, startToEnd);

	return point - v;
}

vec4 effect(vec4 colour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	if (discardBackwardsFragments && fragmentNormalCamera.z < 0.0) {
		discard;
	}

	// For point pupils:
	vec3 pupilPosition = (pupilToWorld * vec4(vec3(0.0), 1.0)).xyz;
	vec3 fragmentRayDirection = normalize(fragmentPosition - pupilPosition);

	// For line pupils:
	// vec3 pupilStartPosition = (pupilToWorld * vec4(vec3(0.0), 1.0)).xyz;
	// vec3 pupilEndPosition = (pupilToWorld * vec4(forwardVector, 1.0)).xyz;
	// vec3 pointOnPupil = closestPointOnLine(pupilStartPosition, pupilEndPosition, fragmentPosition);
	// vec3 fragmentRayDirection = normalize(fragmentPosition - pointOnPupil);

	vec3 rayVelocity = fragmentRayDirection * initialRaySpeed;
	vec3 currentRayStart = fragmentPosition;
	for (int rayStepNumber = 0; rayStepNumber < maxRaySteps; rayStepNumber++) {
		vec3 rayEnd = currentRayStart + rayVelocity * rayTimestep;

		bool foundHit = false;
		RaycastHit closestForwardHit;
		vec3 currentColour;

		for (int i = 0; i < numSpheres; i++) {
			Sphere thisSphere = spheres[i];
			ConvexRaycastResult sphereResult = sphereRaycast(thisSphere.position, thisSphere.radius, currentRayStart, rayEnd);
			if (sphereResult.hit) {
				tryNewClosestHit(limitedRays, foundHit, closestForwardHit, currentColour, sphereResult.hits[0], sphereResult.hits[0].normal / 2.0 + 0.5);
				tryNewClosestHit(limitedRays, foundHit, closestForwardHit, currentColour, sphereResult.hits[1], sphereResult.hits[1].normal / 2.0 + 0.5);
			}
		}

		for (int i = 0; i < numAABBs; i++) {
			AABB thisAABB = AABBs[i];
			ConvexRaycastResult AABBResult = AABBRaycast(thisAABB.position, thisAABB.sideLengths, currentRayStart, rayEnd);
			if (AABBResult.hit) {
				tryNewClosestHit(limitedRays, foundHit, closestForwardHit, currentColour, AABBResult.hits[0], AABBResult.hits[0].normal / 2.0 + 0.5);
				tryNewClosestHit(limitedRays, foundHit, closestForwardHit, currentColour, AABBResult.hits[1], AABBResult.hits[1].normal / 2.0 + 0.5);
			}
		}

		ConvexRaycastResult blackHoleResult = sphereRaycast(blackHolePosition, blackHoleRadius, currentRayStart, rayEnd);
		if (blackHoleResult.hit) {
			tryNewClosestHit(limitedRays, foundHit, closestForwardHit, currentColour, blackHoleResult.hits[0], blackHoleColour);
			tryNewClosestHit(limitedRays, foundHit, closestForwardHit, currentColour, blackHoleResult.hits[1], blackHoleColour);
		}

		if (foundHit) {
			return vec4(currentColour, 1.0);
		}

		vec3 rayToBlackHole = blackHolePosition - currentRayStart;
		rayVelocity += normalize(rayToBlackHole) * blackHoleGravity * pow(length(rayToBlackHole), -blackHoleExponentPositive);

		currentRayStart = rayEnd;
	}

	return vec4(skyColour, 1.0);
}

#endif
