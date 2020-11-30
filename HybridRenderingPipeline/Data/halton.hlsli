struct HaltonState
{
    uint dimension;
    uint sequenceIndex;
};

void haltonInit(inout HaltonState hState,
    int x, int y,
    int path, int numPaths,
    int frameId,
    int loop)
{
    hState.dimension = 2;
    hState.sequenceIndex = haltonIndex(x, y,
        (frameId * numPaths + path) % (loop * numPaths));
}

float haltonSample(uint dimension, uint sampleIndex)
{
    int base = 0;

    // Use a prime number.
    switch (dimension)
    {
    case 0:  base = 2;   break;
    case 1:  base = 3;   break;
    case 2:  base = 5;   break;
    case 3:  base = 7;   break;
    case 4:  base = 11;   break;
    case 5:  base = 13;   break;
    case 6:  base = 15;   break;
    case 7:  base = 17;   break;
    case 8:  base = 19;   break;
    case 9:  base = 23;   break;
    case 10:  base = 29;   break;
    case 11:  base = 31;   break;
    case 12:  base = 37;   break;
    case 13:  base = 41;   break;
    case 14:  base = 43;   break;
    case 15:  base = 47;   break;
    case 16:  base = 53;   break;
    case 17:  base = 59;   break;
    case 18:  base = 61;   break;
    case 19:  base = 67;   break;
    case 20:  base = 71;   break;
    case 21:  base = 73;   break;
    case 22:  base = 79;   break;
    case 23:  base = 83;   break;
    case 24:  base = 89;   break;
    case 25:  base = 97;   break;
    case 26:  base = 101;   break;
    case 27:  base = 103;   break;
    case 28:  base = 109;   break;
    case 29:  base = 113;   break;
    case 30:  base = 127;   break;
    case 31: base = 131; break;
    default: base = 2;   break;
    }

    // Compute the radical inverse.
    float a = 0;
    float invBase = 1.0f / float(base);

    for (float mult = invBase;
        sampleIndex != 0; sampleIndex /= base, mult *= invBase)
    {
        a += float(sampleIndex % base) * mult;
    }

    return a;
}

float haltonNext(inout HaltonState state)
{
    return haltonSample(state.dimension++, state.sequenceIndex);
}

// Modified from [pbrt]
uint haltonIndex(uint x, uint y, uint i)
{
    return ((halton2Inverse(x % 256, 8) * 76545 +
        halton3Inverse(y % 256, 6) * 110080) % 3) + i * 186624;
}

// Modified from [pbrt]
uint halton2Inverse(uint index, uint digits)
{
    index = (index << 16) | (index >> 16);
    index = ((index & 0x00ff00ff) << 8) | ((index & 0xff00ff00) >> 8);
    index = ((index & 0x0f0f0f0f) << 4) | ((index & 0xf0f0f0f0) >> 4);
    index = ((index & 0x33333333) << 2) | ((index & 0xcccccccc) >> 2);
    index = ((index & 0x55555555) << 1) | ((index & 0xaaaaaaaa) >> 1);
    return index >> (32 - digits);
}

// Modified from [pbrt]
uint halton3Inverse(uint index, uint digits)
{
    uint result = 0;
    for (uint d = 0; d < digits; ++d)
    {
        result = result * 3 + index % 3;
        index /= 3;
    }
    return result;
}