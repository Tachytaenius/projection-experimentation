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

uniform mat4 pupilToWorld;
uniform bool discardBackwardsFragments;

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
	vec3 AABBToRayStart = rayStart - (AABBPosition + AABBLengths);
	
	vec3 a = 1.0 / startToEnd;
	vec3 b = a * AABBToRayStart;
	vec3 c = abs(a) * AABBLengths;
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

void tryNewClosestHit(inout bool foundHit, inout RaycastHit closestForwardHit, RaycastHit newHit) {
	// Is it forward?
	if (newHit.t < 0.0) {
		return;
	}
	// Nothing to compare to? Is it closer?
	if (!foundHit || newHit.t < closestForwardHit.t) {
		closestForwardHit = newHit;
		foundHit = true;
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

	bool foundHit = false;
	RaycastHit closestForwardHit;

	float sphereRadius = 1.0;
	ConvexRaycastResult sphereResult = sphereRaycast(vec3(10.0, 1.0, 0.0), sphereRadius, fragmentPosition, fragmentPosition + fragmentRayDirection);
	if (sphereResult.hit) {
		tryNewClosestHit(foundHit, closestForwardHit, sphereResult.hits[0]);
		tryNewClosestHit(foundHit, closestForwardHit, sphereResult.hits[1]);
	}

	float cubeSideLength = 1.0;
	ConvexRaycastResult AABBResult = AABBRaycast(vec3(10.0, 1.0, 2.5), vec3(cubeSideLength), fragmentPosition, fragmentPosition + fragmentRayDirection);
	if (AABBResult.hit) {
		tryNewClosestHit(foundHit, closestForwardHit, AABBResult.hits[0]);
		tryNewClosestHit(foundHit, closestForwardHit, AABBResult.hits[1]);
	}

	if (foundHit) {
		return vec4(closestForwardHit.normal / 2.0 + 0.5, 1.0);
	}

	return vec4(0.0);
}

#endif
