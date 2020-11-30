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

#include "ComparePass.h"

namespace {
	const char* kCompareShader = "compare.ps.hlsl";
};

ComparePass::ComparePass()
	: ::RenderPass("Compare Pass", "Compare Options")
{

}

bool ComparePass::initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager)
{
	if (!pResManager) return false;

	// Stash our resource manager; ask for the texture the developer asked us to accumulate
	mpResManager = pResManager;
  mLeftBuffers.push_back({ -1, "< None >" });
  mRightBuffers.push_back({ -1, "< None >" });


	// Create our graphics state and accumulation shader
	mpGfxState = GraphicsState::create();
	mpCompareShader = FullscreenLaunch::create(kCompareShader);

	return true;
}


void ComparePass::renderGui(Gui* pGui)
{
		pGui->addDropdown("Buffer left", mLeftBuffers, mSelectLeft);
    pGui->addDropdown("Buffer right", mRightBuffers, mSelectRight);
}

void ComparePass::resize(uint32_t width, uint32_t height) {
	mpInternalFbo = ResourceManager::createFbo(width, height, ResourceFormat::RGBA32Float);
	mpGfxState->setFbo(mpInternalFbo);
}


void ComparePass::execute(RenderContext* pRenderContext)
{
	// Grab the texture to accumulate
	
	Texture::SharedPtr outputTexture = mpResManager->getTexture(ResourceManager::kOutputChannel);

	if ( !outputTexture || mSelectRight == uint32_t(-1) || mSelectLeft == uint32_t(-1)) return;
 
  Texture::SharedPtr leftTexture = mpResManager->getTexture(mSelectLeft);
	Texture::SharedPtr rightTexture = mpResManager->getTexture(mSelectRight);

	// Set shader parameters for our accumulation
	auto shaderVars = mpCompareShader->getVars();
	shaderVars["gLeft"] = leftTexture;
	shaderVars["gRight"] = rightTexture;

	// Do the accumulation
	mpCompareShader->execute(pRenderContext, mpGfxState);

	// We've accumulated our result.  Copy that back to the input/output buffer
	// Keep a copy for next frame (we need this to avoid reading & writing to the same resource)
	pRenderContext->blit(mpInternalFbo->getColorTexture(0)->getSRV(), outputTexture->getRTV());
}


void ComparePass::pipelineUpdated(ResourceManager::SharedPtr pResManager)
{
	// This method gets called when the pipeline changes.  We ask the resource manager what resources
	//     are available to use.  We then create a list of these resources to provide to the user 
	//     via the GUI window, so they can choose which to display on screen.

	// This only works if we have a valid resource manager
	if (!pResManager) return;
	mpResManager = pResManager;

	// Clear the GUI's list of displayable textures
	mLeftBuffers.clear();
  mRightBuffers.clear();

	// We're not allowing the user to display the output buffer, so identify that resource
	int32_t outputChannel = mpResManager->getTextureIndex(ResourceManager::kOutputChannel);

	// Loop over all resources available in the resource manager
	for (uint32_t i = 0; i < mpResManager->getTextureCount(); i++)
	{
		// If this one is the output resource, skip it
		if (i == outputChannel) continue;

		// Add the name of this resource to our GUI's list of displayable resources
		mLeftBuffers.push_back({ int32_t(i), mpResManager->getTextureName(i) });
    mRightBuffers.push_back({ int32_t(i), mpResManager->getTextureName(i) });

		// If our UI currently had an invalid buffer selected, select this valid one now.
		if (mSelectLeft == uint32_t(-1)) mSelectLeft = i;
		if (mSelectRight == uint32_t(-1)) mSelectRight = i;
	}
}