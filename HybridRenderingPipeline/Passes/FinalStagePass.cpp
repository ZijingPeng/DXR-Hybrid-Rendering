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

#include "FinalStagePass.h"

namespace {
	// Where is our shader located?
    const char *kLambertShader = "finalStage.ps.hlsl";
    const char *kShadowAOChannel = "shadowFilter";
    const char *kDirectLightChannel = "directLightingChannel";
    const char *kReflectionChannel = "reflectionFilter";
	const char* kEmissiveChannel = "MaterialEmissive";
	const char* kWorldPos = "WorldPosition";
};

// Define our constructor methods
FinalStagePass::SharedPtr FinalStagePass::create(const std::string & bufferOut)
{ 
	return SharedPtr(new FinalStagePass(bufferOut));
}

FinalStagePass::FinalStagePass(const std::string &bufferOut)
	: ::RenderPass("FinalStagePass Pass", "FinalStage Options")
{
	mOutputTexName = bufferOut;
}

bool FinalStagePass::initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager)
{
	// Stash our resource manager; ask for the texture the developer asked us to write
	mpResManager = pResManager;
	mpResManager->requestTextureResources({ kWorldPos, kShadowAOChannel, kDirectLightChannel, kReflectionChannel });
	mpResManager->requestTextureResource(mOutputTexName);

	// Create our graphics state and an accumulation shader
	mpGfxState = GraphicsState::create();
	mpShader = FullscreenLaunch::create(kLambertShader);

	return true;
}

void FinalStagePass::initScene(RenderContext* pRenderContext, Scene::SharedPtr pScene)
{

	// When our renderer moves around we want to reset accumulation, so stash the scene pointer
	mpScene = std::dynamic_pointer_cast<RtScene>(pScene);
	if (!mpScene) return;
}

void FinalStagePass::resize(uint32_t width, uint32_t height)
{
	// We need a framebuffer to attach to our graphics pipe state (when running our full-screen pass).  We can ask our
	//    resource manager to create one for us, with specified width, height, and format and one color buffer.
	mpInternalFbo = ResourceManager::createFbo(width, height, ResourceFormat::RGBA32Float);
	mpGfxState->setFbo(mpInternalFbo);
}

void FinalStagePass::renderGui(Gui* pGui)
{
	// Print the name of the buffer we're accumulating from and into.  Add a blank line below that for clarity
    pGui->addText( (std::string("Direct Ligting buffer:   ") + mOutputTexName).c_str() );
    pGui->addText("");  

	// Display a count of accumulated frames
	pGui->addText("");
}

void FinalStagePass::execute(RenderContext* pRenderContext)
{
    // Grab the texture to write to
	Texture::SharedPtr pDstTex = mpResManager->getTexture(mOutputTexName);

	// If our input texture is invalid, or we've been asked to skip accumulation, do nothing.
  if (!pDstTex) return;

	// Pass our G-buffer textures down to the HLSL so we can shade
	auto shaderVars = mpShader->getVars();
	shaderVars["gReflection"] = mpResManager->getTexture(kReflectionChannel);
	shaderVars["gDirectLighting"] = mpResManager->getTexture(kDirectLightChannel);
	shaderVars["gShadowAO"] = mpResManager->getTexture(kShadowAOChannel);
	shaderVars["gEmissive"] = mpResManager->getTexture(kEmissiveChannel);
	shaderVars["gPos"] = mpResManager->getTexture(kWorldPos);

  // Execute the accumulation shader
  mpShader->execute(pRenderContext, mpGfxState);

  // We've accumulated our result.  Copy that back to the input/output buffer
  pRenderContext->blit(mpInternalFbo->getColorTexture(0)->getSRV(), pDstTex->getRTV());
}
