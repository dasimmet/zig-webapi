precision mediump float;
uniform sampler2D u_dice;
uniform vec3 u_tint;
varying mediump vec2 v_uv;
varying mediump float v_light;

void main() {
    vec3 face_color = texture2D(u_dice, v_uv).rgb;
    gl_FragColor = vec4(face_color * u_tint * v_light, 1.0);
}
