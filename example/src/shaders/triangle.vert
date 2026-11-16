attribute vec2 a_pos;
uniform float u_angle;
varying vec2 v_pos;

void main() {
    float c = cos(u_angle);
    float s = sin(u_angle);
    vec2 rotated = vec2(
        a_pos.x * c - a_pos.y * s,
        a_pos.x * s + a_pos.y * c
    );
    v_pos = a_pos;
    gl_Position = vec4(rotated, 0.0, 1.0);
}
