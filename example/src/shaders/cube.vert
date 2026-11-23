attribute vec3 a_pos;
attribute vec2 a_uv;
attribute vec3 a_normal;
uniform float u_yaw;
uniform float u_pitch;
uniform float u_scale;
uniform float u_aspect;
varying mediump vec2 v_uv;
varying mediump float v_light;

vec3 rotate(vec3 point) {
    float cy = cos(u_yaw);
    float sy = sin(u_yaw);
    vec3 yaw_rotated = vec3(
        point.x * cy + point.z * sy,
        point.y,
        -point.x * sy + point.z * cy
    );

    float cp = cos(u_pitch);
    float sp = sin(u_pitch);
    return vec3(
        yaw_rotated.x,
        yaw_rotated.y * cp - yaw_rotated.z * sp,
        yaw_rotated.y * sp + yaw_rotated.z * cp
    );
}

void main() {
    vec3 rotated = rotate(a_pos);
    float depth = 3.6 - rotated.z;
    float focal_length = 3.5 * u_scale;
    v_uv = a_uv;
    v_light = 0.55 + 0.45 * max(dot(rotate(a_normal), normalize(vec3(-0.5, 0.8, 1.0))), 0.0);
    gl_Position = vec4(
        rotated.x * focal_length / u_aspect,
        rotated.y * focal_length - 0.18 * depth,
        (21.0 * depth - 40.0) / 19.0,
        depth
    );
}
