precision mediump float;
uniform sampler2D u_banner;
varying mediump vec2 v_uv;

void main() {
    gl_FragColor = texture2D(u_banner, v_uv);
}
