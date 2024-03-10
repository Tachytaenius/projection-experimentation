// Dependencies:
// include/lib/simplex3d.glsl

vec3 sampleSky(vec3 direction) {
	return vec3(simplex3d(direction * 3.0) * 0.5 + 0.5);
}
