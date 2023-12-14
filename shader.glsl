varying vec3 fragmentPosition;
// varying vec3 fragmentNormal;

uniform vec3 pupilPosition;

#ifdef VERTEX

uniform float aspectRatio;
uniform float verticalFOV; // TODO
uniform mat4 retinaToWorld;
// uniform mat3 retinaToWorldNormal;

// attribute vec3 VertexNormal;

vec4 position(mat4 loveTransform, vec4 homogenVertexPosition) {
	fragmentPosition = (retinaToWorld * VertexPosition).xyz;
	// fragmentNormal = retinaToWorldNormal * VertexNormal;
	vec4 ret = homogenVertexPosition;
	ret.y *= aspectRatio;
	return ret;
}

#endif

#ifdef PIXEL

// TODO: Struct instead?
bool sphereRaycast(vec3 spherePosition, float sphereRadius, vec3 rayStart, vec3 rayEnd, out float[2] result) {
	if (rayStart == rayEnd) {
		return false;
	}

	vec3 startToEnd = rayEnd - rayStart;
	vec3 startToSphere = spherePosition - rayStart;

	float a = dot(startToEnd, startToEnd);
	float b = 2.0 * dot(startToSphere, startToEnd);
	float c = dot(startToSphere, startToSphere) - pow(sphereRadius, 2.0);

	float discriminant = pow(b, 2.0) - 4.0 * a * c;
	if (discriminant < 0.0) {
		return false;
	}

	result[0] = (b - sqrt(discriminant)) / (2.0 * a);
	result[1] = (b + sqrt(discriminant)) / (2.0 * a);
	return true;
}

vec4 effect(vec4 colour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	// fragmentRayDirection = fragmentNormal;
	vec3 fragmentRayDirection = normalize(fragmentPosition - pupilPosition);
	// return (vec4(fragmentRayDirection / 2.0 + 0.5, 1.0));
	float[2] result;
	if (sphereRaycast(vec3(50.0, 300.0, 240.0), 1.0, fragmentPosition, fragmentPosition + fragmentRayDirection, result)) {
		if (result[0] > 0.0 && result[1] > 0.0) {
			return vec4(result[0] - result[1], result[1] - result[0], 1.0, 1.0);
		}
	}
	return vec4(0.0, 0.0, 0.0, 1.0);
}

#endif
