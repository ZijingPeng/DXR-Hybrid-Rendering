# DXR-Hybrid-Rendering

![](/img/ours.png)

**University of Pennsylvania, CIS 565: GPU Programming and Architecture Final Project**

- [Shenyue Chen](https://github.com/EvsChen)
- [Szeyu Chan](https://github.com/AsteriskChan)
- [Zijing Peng](https://github.com/ZijingPeng)

## Introduction

This project is to implement a hybrid rendering pipeline that combines both rasterization and raytracing to generate real-time effects. This hybrid rendering pipeline is built based on EA's [PICA PICA](https://www.ea.com/seed/news/seed-project-picapica) project. The pipeline includes multiple passes -- shadow, ambient occlusions, direct lighting and reflection. To denoise our results, we also implemented a SVGF filter. 

## Prerequisites

- Windows 10 version 1809 or newer
- Visual Studio 2019
- [Microsoft Windows SDK version 1903 (10.0.18362.1)](https://developer.microsoft.com/en-us/windows/downloads/sdk-archive)

## Features

### Pipeline

![](/img/pipeline.png)

### Shadow

Shadows are implemented by launching rays towards the light source. To create soft penumbra shadows, we cast rays by sampling in the shape of a cone.

| Hard Shadow              | Soft Shadow (100 spp) |
| ------------------------ | --------------------- |
| ![](/img/hardshadow.png) |  ![](/img/softshadow.png)   |

To filter the shadows, we applied a SVGF-based filter. 

| Raytraced Shadow (1 spp) | Raytraced Shadow with Filter (1 spp) |
| ------------------------ | ------------------------------------ |
| ![](/img/shadow.png)     | ![](/img/shadow_svgf.png)            |

### Ambient Occlusion

We did not implement global illumination in this project, ambient occlusion is used to add realism to our renders. We also used the SVGF-based filter for denoising AO results.

| AO (1 spp)       | AO with filter (1 spp) |
| ---------------- | ---------------------- |
| ![](/img/ao.png) | ![](/img/ao_svgf.png)  |

To improve the performance, we merge the shadow buffer and the AO buffer and add the filter.

### Reflection

To create a nice visual effect of reflection, we first sampled the normal distribution at the intersection of the specular surface. With this sampled normal, we could launch a reflected ray and collect the information when it first hit another object. We used the Halton sequence for sampling because it is well distributed for low and high sample counts.

Another SVGF-based filter is applied for denoising the result.

We also tried to improve the performance by launching a quarter ray per pixel. In our test scene, when the camera is static, the filtered results of 1 spp reflection and 1/4 spp reflection are similar. When the camera is moving fast, the filtered result of quarter resolution reflection is more noisy than the other. However, after applying the quarter resolution reflection, our improvement hugely improved. We'll discuss the improvement at the next section.

| Reflection (1/4 spp)      | Reflection with filter (1/4 spp)   |
| ------------------------- | ---------------------------------- |
| ![](/img/reflection0.png) | ![](/img/reflection1.png)          |
| **Reflection (1 spp)**    | **Reflection with filter (1 spp)** |
| ![](/img/reflection3.png) | ![](/img/reflection2.png)          |

## Performance Analysis

## Results

![](/img/classroom.png)

![](/img/livingroom.png)

## Credit

- [GDC Talk: Shiny Pixels and Beyond: Real-Time Raytracing at SEED](https://www.gdcvault.com/play/1024801/-Real-time-Raytracing-for) 
- [Hybrid Rendering for Real-Time Ray Tracing](https://link.springer.com/chapter/10.1007/978-1-4842-4427-2_25)
- [Falcor](https://github.com/NVIDIAGameWorks/Falcor)
- [Introduction To DirectX Raytracing](http://cwyman.org/code/dxrTutors/dxr_tutors.md.html)
- [Pica Pica Assets](https://github.com/SEED-EA/pica-pica-assets)
- https://sketchfab.com/3d-models/mirrors-edge-apartment-interior-scene-9804e9f2fe284070b081c96ceaf8af96 by Aurélien Martel
  

