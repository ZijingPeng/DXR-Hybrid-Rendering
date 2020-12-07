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
#include <iostream>

namespace {
	const char* kCompareShader = "compare.ps.hlsl";
};

ComparePass::ComparePass(const std::string &output)
	: ::RenderPass("Compare Pass", "Compare Options")
{
	mOutputChannel = output;
}

bool ComparePass::initialize(RenderContext* pRenderContext, ResourceManager::SharedPtr pResManager)
{
	if (!pResManager) return false;
	mpResManager = pResManager;
	mLeftBuffers.push_back({ -1, "< None >" });
	mRightBuffers.push_back({ -1, "< None >" });
	mpResManager->requestTextureResource(mOutputChannel);
	// Create our graphics state and accumulation shader
	mpGfxState = GraphicsState::create();
	mpCompareShader = FullscreenLaunch::create(kCompareShader);
	return true;
}


void ComparePass::renderGui(Gui* pGui)
{
	std::string outText = "Current buffer size " + std::to_string(mLeftBuffers.size());
	pGui->addText(outText.c_str());
	pGui->addDropdown("Buffer left", mLeftBuffers, mSelectLeft);
    pGui->addDropdown("Buffer right", mRightBuffers, mSelectRight);
}

void ComparePass::resize(uint32_t width, uint32_t height) {
	mpInternalFbo = ResourceManager::createFbo(width, height, ResourceFormat::RGBA32Float);
	mpGfxState->setFbo(mpInternalFbo);
}


void ComparePass::execute(RenderContext* pRenderContext)
{
	Texture::SharedPtr outputTexture = mpResManager->getTexture(mOutputChannel);
	if (!outputTexture || mSelectRight == uint32_t(-1) || mSelectLeft == uint32_t(-1)) return;
	Texture::SharedPtr leftTexture = mpResManager->getTexture(mSelectLeft);
	Texture::SharedPtr rightTexture = mpResManager->getTexture(mSelectRight);

	auto shaderVars = mpCompareShader->getVars();
	shaderVars["gLeft"] = leftTexture;
	shaderVars["gRight"] = rightTexture;
	mpCompareShader->execute(pRenderContext, mpGfxState);
	pRenderContext->blit(mpInternalFbo->getColorTexture(0)->getSRV(), outputTexture->getRTV());
}

void ComparePass::updateDropdown(ResourceManager::SharedPtr pResManager) {
	if (!pResManager) return;
	mpResManager = pResManager;
	mLeftBuffers.clear();
	mRightBuffers.clear();
	int32_t outputChannel = mpResManager->getTextureIndex(mOutputChannel);
	for (uint32_t i = 0; i < mpResManager->getTextureCount(); i++)
	{
		if (i == outputChannel) continue;
		mLeftBuffers.push_back({ int32_t(i), mpResManager->getTextureName(i) });
		mRightBuffers.push_back({ int32_t(i), mpResManager->getTextureName(i) });
		if (mSelectLeft == uint32_t(-1)) mSelectLeft = i;
		if (mSelectRight == uint32_t(-1)) mSelectRight = i;
	}
}


void ComparePass::pipelineUpdated(ResourceManager::SharedPtr pResManager)
{
	updateDropdown(pResManager);
}