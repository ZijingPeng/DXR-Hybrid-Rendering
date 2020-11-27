/**********************************************************************************************************************
# Copyright (c) 2018, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
# following conditions are met:
#  * Redistributions of code must retain the copyright notice, this list of conditions and the following disclaimer.
#  * Neither the name of NVIDIA CORPORATION nor the names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT
# SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,
# OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**********************************************************************************************************************/

#include "Falcor.h"
#include "../SharedUtils/RenderingPipeline.h"
#include "Passes/AmbientOcclusionPass.h"
#include "Passes/ShadowPass.h"
#include "Passes/ReflectionPass.h"
#include "Passes/DirectLightingPass.h"
#include "Passes/FinalStagePass.h"
#include "../CommonPasses/SimpleGBufferPass.h"
#include "../CommonPasses/SimpleAccumulationPass.h"
#include "../CommonPasses/CopyToOutputPass.h"
#include "./SVGFPass.h"

int WINAPI WinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance, _In_ LPSTR lpCmdLine, _In_ int nShowCmd)
{
	// Create our rendering pipeline
	RenderingPipeline *pipeline = new RenderingPipeline();

	// Add passes into our pipeline
	pipeline->setPass(0, SimpleGBufferPass::create());        
	pipeline->setPass(1, AmbientOcclusionPass::create("aoChannel"));
	pipeline->setPass(2, SimpleAccumulationPass::create("aoChannel"));
	pipeline->setPass(3, ShadowPass::create("shadowChannel"));
	pipeline->setPass(4, SimpleAccumulationPass::create("shadowChannel"));
	pipeline->setPass(5, ReflectionPass::create("reflectionChannel"));
	pipeline->setPass(6, SimpleAccumulationPass::create("reflectionChannel"));
	pipeline->setPass(7, DirectLightingPass::create("directLightingChannel"));
	pipeline->setPass(8, FinalStagePass::create("finalOutput"));
  pipeline->setPass(9, SVGFPass::create("finalOutput", ResourceManager::kOutputChannel));
	//pipeline->setPass(9, SimpleAccumulationPass::create());

	// Define a set of config / window parameters for our program
    SampleConfig config;
    config.windowDesc.title = "Hybrid Rendering";
    config.windowDesc.resizableWindow = true;

	// Start our program!
	RenderingPipeline::run(pipeline, config);
}
