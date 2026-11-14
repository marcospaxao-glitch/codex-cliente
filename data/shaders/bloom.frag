uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

void main()
{
    vec4 color = texture2D(u_Tex0, v_TexCoord);

    // CODEX: laco no formato aceito pelo WebGL (variavel declarada no proprio for)
    for (int i = -4; i <= 4; i++)
        for (int j = -4; j <= 4; j++)
            color += texture2D(u_Tex0, v_TexCoord + vec2(float(i), float(j)) * 0.003) * 0.008;

    gl_FragColor = color;
}
