Texture2D   gLeft;
Texture2D   gRight;

float4 main(float2 texC : TEXCOORD, float4 pos : SV_Position) : SV_TARGET0
{
    uint2 pixelPos = (uint2) pos.xy;
    return texC.x < 0.5f ? gLeft[pixelPos] : gRight[pixelPos];
}