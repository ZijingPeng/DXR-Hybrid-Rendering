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

#include "DirectLightingPass.h"

namespace {
	// Where is our shader located?
    const char *kLambertShader = "lambert.ps.hlsl";
};

// Define our constructor methods
DirectLightingPass::SharedPtr DirectLightingPass::create(const std::string & bufferOut)
{ 
	return SharedPtr(new DirectLightingPass(bufferOut));
}

DirectLightingPass::DirectLightingPass(const std::string &bufferOut)
	: ::RenderPass("DirectLighting Pass", "DirectLighting Options")
{
	mOutputTexName = bufferOut;
}

bool DirectLightingPass::initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager)
{
	// Stash our resource manager; ask for the texture the developer asked us to write
	mpResManager = pResManager;
	mpResManager->requestTextureResources({ "WorldPosition", "WorldNormal", "MaterialDiffuse", "MaterialSpecRough" });
	mpResManager->requestTextureResource(mOutputTexName);

	// Create our graphics state and an accumulation shader
	mpGfxState = GraphicsState::create();
	mpLambertShader = FullscreenLaunch::create(kLambertShader);

	if (mpScene)
	{
		mpLambertShader->setLights(mpScene->getLights());
	}
	return true;
}

void DirectLightingPass::initScene(RenderContext* pRenderContext, Scene::SharedPtr pScene)
{

	// When our renderer moves around we want to reset accumulation, so stash the scene pointer
	mpScene = std::dynamic_pointer_cast<RtScene>(pScene);
	if (!mpScene) return;
	mpLambertShader->setLights(mpScene->getLights());
}

void DirectLightingPass::resize(uint32_t width, uint32_t height)
{
	// We need a framebuffer to attach to our graphics pipe state (when running our full-screen pass).  We can ask our
	//    resource manager to create one for us, with specified width, height, and format and one color buffer.
	mpInternalFbo = ResourceManager::createFbo(width, height, ResourceFormat::RGBA32Float);
	mpGfxState->setFbo(mpInternalFbo);
}

void DirectLightingPass::renderGui(Gui* pGui)
{
	// Print the name of the buffer we're accumulating from and into.  Add a blank line below that for clarity
    pGui->addText( (std::string("Direct Ligting buffer:   ") + mOutputTexName).c_str() );
    pGui->addText("");  

	// Display a count of accumulated frames
	pGui->addText("");
}

void DirectLightingPass::execute(RenderContext* pRenderContext)
{
    // Grab the texture to write to
	Texture::SharedPtr pDstTex = mpResManager->getTexture(mOutputTexName);

	// If our input texture is invalid, or we've been asked to skip accumulation, do nothing.
    if (!pDstTex) return;

	mpLambertShader->setLights(mpScene->getLights());
	// Pass our G-buffer textures down to the HLSL so we can shade
	auto shaderVars = mpLambertShader->getVars();
	shaderVars["gPos"] = mpResManager->getTexture("WorldPosition");
	shaderVars["gNorm"] = mpResManager->getTexture("WorldNormal");
	shaderVars["gDiffuseMatl"] = mpResManager->getTexture("MaterialDiffuse");
	shaderVars["gSpecMatl"] = mpResManager->getTexture("MaterialSpecRough");

    // Execute the accumulation shader
    mpLambertShader->execute(pRenderContext, mpGfxState);

    // We've accumulated our result.  Copy that back to the input/output buffer
    pRenderContext->blit(mpInternalFbo->getColorTexture(0)->getSRV(), pDstTex->getRTV());
}
