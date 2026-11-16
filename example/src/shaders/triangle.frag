precision mediump float;
uniform vec3 u_tint;
varying vec2 v_pos;

void main() {
    vec3 gradient = vec3(
        0.5 + 0.5 * v_pos.x,
        0.5 + 0.5 * v_pos.y,
        0.8
    );
    gl_FragColor = vec4(gradient * u_tint, 1.0);
}
